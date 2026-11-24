# halogen-setup

Configurazione **verificata sul campo** per far girare il modello linguistico
`halogen-qwen3.8-flash-next` interamente in locale su una macchina AMD Strix
Halo con Podman, e usarlo da un coding agent fino a 4 sessioni in parallelo.

Non è documentazione ufficiale del produttore: è la ricetta che abbiamo
misurato, con i numeri. Ogni scelta ha accanto il motivo e il costo, così puoi
adattarla alla tua macchina invece di copiarla alla cieca.

> English version: [README.en.md](README.en.md)

```
  opencode run -m halogen/halogen-qwen3.8-flash-next#xhigh
                     │
                     ▼  http://127.0.0.1:8731/v1
  ┌──────────────────────────────────────────────────────────────┐
  │ quadlet: halogen-flash.container (Podman, utente)            │
  │  ctx 131072 · pool KV 524288 · 4 slot · vision · cache disk  │
  └──────────────────────────────────────────────────────────────┘
                     │
                     ▼  /models (read-only)
  /mnt/llm/AI/Models/halogen-qwen3.8-flash-next  (~115 GB)
```

## Contenuto

| Percorso | Cosa |
|---|---|
| `quadlet/halogen-flash.container` | unit Podman utente, pronta da copiare |
| `opencode/halogen-provider.json` | blocco `providers.halogen` per OpenCode V2 |
| `tools/health.sh` | stato, pool, cache, throughput, memoria del processo |
| `tools/agent.sh` | lancia un agente di coding sul modello, con timeout e log |
| `docs/sizing.md` | ctx e pool KV: il conto della RAM, e cosa cambiare |
| `docs/opencode.md` | varianti di thinking, budget dei token, timeout |
| `docs/measured.md` | i numeri misurati su questa macchina |
| `docs/troubleshooting.md` | i problemi che ci sono costati tempo |

## Quick start

Requisiti: Linux con Podman ≥ 5, GPU AMD con `/dev/kfd` e `/dev/dri`, almeno
96 GB di RAM, i pesi già su disco.

```bash
# 1. pesi (~115 GB): dove vuoi, anche su un altro disco
#    es. /mnt/llm/AI/Models/halogen-qwen3.8-flash-next

# 2. unit Podman utente (mai root)
mkdir -p ~/.config/containers/systemd
cp quadlet/halogen-flash.container ~/.config/containers/systemd/
#    apri il file e correggi i due path:
#      Volume=<pesi>:/models:ro
#      Volume=<cache>:/cache

# 3. cache del prompt su disco (fuori da tmpfs/overlay)
mkdir -p ~/.cache/halogen-cache

# 4. avvio
systemctl --user daemon-reload
systemctl --user start halogen-flash
curl -s localhost:8731/health | jq '{status,model,context,slots}'

# 5. OpenCode: incolla il blocco di opencode/halogen-provider.json
#    sotto "providers" in ~/.config/opencode/opencode.json, poi:
opencode run -m halogen/halogen-qwen3.8-flash-next "ciao"
```

Verifica che tutto sia su con **`tools/health.sh`**.

## Le cinque scelte che rendono questa configurazione "ottimizzata"

1. **`HALOGEN_CTX=131072` invece del default 262144.** Il pool KV resta quello
   ufficiale: stesse prestazioni, ma 4 conversazioni da 128k residenti invece di
   2 da 256k. Le sessioni agentiche vere stanno sotto i 128k, e quando non ci
   stanno la compaction costa meno di un prefill freddo.
2. **`HALOGEN_KV_POOL_POSITIONS=524288` (4 × ctx).** Quattro sessioni in volo,
   la quinta aspetta invece di fallire. È il numero che il produttore consiglia
   con 4 slot.
3. **`HALOGEN_VISION_TOWER=1`.** È ciò che permette a un agente di leggere uno
   screenshot e verificare da solo una UI o un sito. Costa qualche GiB di VRAM.
4. **`HALOGEN_CACHE_DIR=/cache` su bind mount reale.** Una conversazione da 38k
   riprende in 193 ms invece di 24 s di prefill. Deve stare su un filesystem
   che accetta `O_DIRECT`: btrfs/ext4 sì, tmpfs e overlay no.
5. **`HALOGEN_MAX_TOKENS_DEFAULT=16384`.** Copre reasoning + tool call +
   risposta di un turno agentico ordinario, per i client che non mandano
   `max_tokens`.

E una sesta, imparata a nostre spese: **`HALOGEN_CACHE_DISK_GIB=96`**. Il
default di 64 GiB si è riempito in 5 ore di lavoro agentico (17 conversazioni
da ~3,8 GiB) e ha cominciato a sfrattare proprio le sessioni in corso.

## Cosa NON attivare senza misurarlo

- `HALOGEN_INDEXER_BUDGET=4096` — retrieval leggermente migliore, prefill +6,7%,
  risposte non byte-identiche. Il default 2048 va bene.
- `HALOGEN_COMPOSABLE_CONTEXT=1` — compaction più veloce **ma rifiuta le
  immagini**: se ti serve la visione, lascialo spento.

## Numeri (misurati, non stimati)

| | |
|---|---|
| Generazione | ~58 tok/s (media end-to-end con coda: ~23 tok/s) |
| Prefill | ~1.060 tok/s |
| Conversazione calda | 114 ms · dopo un riavvio dal disco 193 ms |
| Cache hit, 5 agenti per 5 ore | **93,8%** — 86M token di prompt evitati |
| RAM server | ~89,8 GiB su 121 (pesi 62,9 + pool 14,4 + working 12,4) |

Dettagli e comandi per riprodurre in [`docs/measured.md`](docs/measured.md).

## Chi lo usa già

Questa configurazione è quella di un esperimento reale: cinque progetti software
completi (due siti, una web app full-stack, un'app GTK4 e una soluzione .NET)
costruiti da cinque agenti in parallelo sul modello locale, con verifica
indipendente via test e screenshot riletti dal modello stesso.

## Licenza

Ricetta e script: MIT. Pesi e immagine del server restano dei loro autori
(`ghcr.io/peonist-ai/halogen-flash-server`) e non sono inclusi qui.
