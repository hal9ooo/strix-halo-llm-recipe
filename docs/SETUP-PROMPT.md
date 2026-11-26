# Setup di una macchina Strix Halo con la ricetta halogen

Sei un agente. Il tuo compito è portare questa macchina da "niente" a "un
modello locale che risponde su http://127.0.0.1:8731/v1 e un coding agent ci
lavora sopra". Segui questa procedura nell'ordine. Non improvvisare: ogni passo
esiste perché senza fallisce in un modo che sembra un altro problema.

Macchina bersaglio attesa: AMD Ryzen AI MAX+ 395 (Strix Halo, gfx1151),
Radeon 8060S, almeno 96 GB di RAM, Linux nativo. Se la macchina non è questa,
fermati al passo 1 e riporta cosa hai trovato.

---

## 0. Il repository

```bash
git clone https://github.com/hal9ooo/strix-halo-llm-recipe.git
cd strix-halo-llm-recipe
```

Leggi `AGENTS.md`: è il contratto. `docs/requirements.md` spiega i prerequisiti
d'host; `docs/troubleshooting.md` i problemi reali con sintomo, causa e rimedio.

## 1. Fermati subito se la macchina non può — e dillo

```bash
bash tools/preflight.sh
```

Solo lettura, nessun effetto collaterale. È il passo più importante di tutti:
dice in una schermata qualcosa che altrimenti costa ore.

- **exit 0** → la macchina è pronta, vai al passo 2.
- **exit 1** → leggi ogni riga `FAIL`. Ognuna nomina la cosa mancante e dove
  sta la spiegazione. **Riporta all'operatore e fermati.** In particolare:

| FAIL | cosa significa | cosa dire all'operatore |
|---|---|---|
| `sei su Windows` | il motore non esiste per Windows; i pesi `.hgn` non si aprono con llama.cpp/vLLM/transformers | serve avviare Linux su questa macchina; nessun workaround |
| `sei su WSL2` | passa per `/dev/dxg`, non per KFD, la registrazione viene rifiutata | idem: serve Linux nativo |
| `/sys/class/kfd` assente | manca il driver amdgpu/KFD | Linux nativo con driver AMD, o i permessi |
| `manca CONFIG_HSA_AMD_SVM` | ogni registrazione read-only fallisce, qualunque dimensione | kernel Ubuntu ≥ 6.17 o Fedora ≥ 6.18.7 |
| `manca cwsr_size` | il kernel non ha le due fix gfx1151 di AMD | kernel ≥ 6.18.4 / Ubuntu HWE `6.17.0-19.19` |
| `RAM totale … GiB` | sotto i 96 GB il server rifiuta di partire | usare `docs/sizing.md` §"Cosa cambiare se hai meno RAM" |
| pesi `incompleto` | download troncato | rilancia `hf download`, riprende da solo |

Non provare varianti creative su questi. Non c'è un trucco che li aggira, e
dirlo chiaramente è il lavoro fatto bene.

## 2. I pesi (~115 GB, pubblici)

```bash
pip install -U "huggingface_hub[cli]"
mkdir -p ~/halogen-models
hf download peonist-ai/halogen-qwen3.8-flash-next --local-dir ~/halogen-models
```

Servono `qwen38-flash-next-v2.hgn` (62,11 GiB),
`qwen38-flash-next-ngram.hgn` (47,68 GiB),
`qwen38-flash-next-drafter-r2-ht4.hgn` (1,39 GiB),
`qwen38-flash-next-vision.hgn` (0,84 GiB) e `tokenizer/`. Lo spazio richiesto è
questo **più** la cache: almeno 220 GB liberi in totale, anche su due dischi.
Se il download si interrompe, rilancia lo stesso comando.

## 3. Preparare la macchina

```bash
# cache del prompt su un filesystem che accetta O_DIRECT (NON tmpfs/overlay)
mkdir -p ~/.cache/halogen-cache

# il servizio deve sopravvivere al logout
sudo loginctl enable-linger "$USER"
```

Se la BIOS non è ancora stata toccata: il carve-out `UMA Frame Buffer` va al
**minimo esplicito**, non su `Auto` (su alcune schede `Auto` = 64 GiB e i pesi
non partono). Richiede un riavvio: segnalalo all'operatore come azione sua, non
farla tu.

## 4. La unit

```bash
mkdir -p ~/.config/containers/systemd
cp quadlet/halogen-flash.container ~/.config/containers/systemd/
```

Poi correggi **tre** cose nel file copiato, con i valori veri di questa macchina:

1. `Volume=<dove sono i pesi>:/models:ro`
2. `Volume=<home dell'utente>/.cache/halogen-cache:/cache`
3. `ContainerName=`, solo se ne gira più di una

Non toccare gli altri valori senza aver letto `docs/sizing.md` e rifatto il
conto: `HALOGEN_KV_POOL_POSITIONS` troppo grande fa **rifiutare l'avvio**, non
swappare. E `PublishPort` resta `127.0.0.1:8731:8731`: il server non ha API key,
su `0.0.0.0` chiunque sulla LAN legge le conversazioni.

## 5. Avvio

```bash
systemctl --user daemon-reload
systemctl --user start halogen-flash
```

Il primo avvio mappa 115 GB: **minuti**, non secondi. `health.sh` in quel
momento dice `container: running ma l'API non risponde — sta ancora caricando i
pesi?`. È atteso: aspetta e rileggi, non riavviare.

```bash
# ripeti finché non risponde (max ~15 min)
bash tools/health.sh
```

Deve comparire `== halogen <versione>` con `contesto: 131072`, `pool KV:
524288`, `slot: 4`, `visione: attiva`, e `su disco: … / 96 GiB`.

## 6. La prova che conta

```bash
time curl -s http://127.0.0.1:8731/v1/chat/completions \
  -H 'Content-Type: application/json' \
  -d '{"model":"halogen-qwen3.8-flash-next",
       "messages":[{"role":"user","content":"Rispondi solo: pronto"}],
       "max_tokens":32}' | jq -r '.choices[0].message.content'
```

Deve rispondere in pochi secondi. Se risponde, il modello è servito e hai
finito la parte difficile.

## 7. Il client (OpenCode)

Incolla il blocco di `opencode/halogen-provider.json` sotto la chiave
`providers` in `~/.config/opencode/opencode.json` (schema V2). Poi:

```bash
opencode run -m halogen/halogen-qwen3.8-flash-next "ciao"
```

Varianti di thinking e budget dei token: `docs/opencode.md`. Il default è
`xhigh`, che è la raccomandazione della model card per il lavoro agentico.
**Non** usare `#none` per il codice: su un conteggio banale sbaglia.

## 8. Rapporto finale

Riporta, in ordine, con i numeri veri che hai letto:

- `preflight.sh`: exit code, e i `FAIL`/`warn` che hai trovato
- host: modello CPU, GPU, GiB di RAM **visti dal sistema** (il carve-out conta)
- versioni: kernel, podman, immagine del server
- `health.sh` completo, e il throughput che riporta
- latenza della prova del passo 6
- cosa hai dovuto cambiare rispetto al repo, e perché
- cosa resta da fare a mano (per esempio la BIOS)

Se sei bloccato: il sintomo esatto, il comando, e le ultime 50 righe di
`podman logs --tail 50 halogen-flash` o
`journalctl --user -u halogen-flash -n 50`. Non riportare "non funziona":
riporta la riga.

---

## Regole che non si negoziano

1. **Mai root.** È una unit `systemd --user`. Se l'hai messa in
   `/etc/containers/systemd/` hai sbagliato destinazione.
2. **La porta resta su `127.0.0.1`.** Per l'accesso da rete servono
   `HALOGEN_API_KEY` **e** un reverse proxy con TLS.
3. **Un solo processo che carica il modello.** Due si rubano la RAM e bloccano
   la macchina per minuti: se lanci test con un server, usa una porta effimera
   (`PORT=8199`) e ferma solo i processi tuoi.
4. **Non modificare i numeri misurati** (`docs/measured.md`, `docs/sizing.md`,
   i due README) senza rimisurare.
5. **Non attivare** `HALOGEN_INDEXER_BUDGET=4096` né
   `HALOGEN_COMPOSABLE_CONTEXT=1`: il secondo **rifiuta le immagini**, quindi
   spegne la visione.
6. Se `preflight.sh` dice che la macchina non è quella giusta, **la risposta è
   dirlo**, non tentare una variante.

---

## Come passare questo prompt a un agente

Non serve clonare niente prima: il prompt si scarica da solo e contiene i
passi. Da qualsiasi cartella:

```bash
codex exec "$(curl -fsSL https://raw.githubusercontent.com/hal9ooo/strix-halo-llm-recipe/main/docs/SETUP-PROMPT.md)" --full-auto
```

oppure, con OpenCode su un modello che non è quello in fase di setup (per
esempio il tuo provider cloud attuale):

```bash
opencode run "$(curl -fsSL https://raw.githubusercontent.com/hal9ooo/strix-halo-llm-recipe/main/docs/SETUP-PROMPT.md)"
```

oppure il testo in un file, da dare a mano a qualsiasi altro harness:

```bash
curl -fsSL https://raw.githubusercontent.com/hal9ooo/strix-halo-llm-recipe/main/docs/SETUP-PROMPT.md -o setup.md
```

Il prompt è autosufficiente: comincia dicendo all'agente di clonare il repo,
e al passo 1 gli dice di fermarsi e riportare se la macchina non è quella
giusta. Non serve altro contesto.
