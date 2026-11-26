# Ottenere i pesi e preparare l'host

Due cose bloccano il 90% dei setup che falliscono, e non sono il modello:
**i pesi non sono citati con il comando per prenderli**, e **l'host ha bisogno
di due prerequisiti** che nessun errore ti spiega. Questa pagina è quella
procedura.

## 1. I pesi (~115 GB, pubblici, senza login)

Il repository è `peonist-ai/halogen-qwen3.8-flash-next` su Hugging Face. Non è
gated: non serve token, non serve accettare una licenza. Servono questi file,
**tutti nella stessa directory**, perché il server li cerca lì per nome:

| file | GiB | serve? |
|---|---|---|
| `qwen38-flash-next-v2.hgn` | 62,11 | **sì** — il checkpoint |
| `qwen38-flash-next-ngram.hgn` | 47,68 | **sì** — la lookup table |
| `qwen38-flash-next-drafter-r2-ht4.hgn` | 1,39 | **sì** — testa di draft (0.20.7) |
| `qwen38-flash-next-vision.hgn` | 0,84 | per la visione (`HALOGEN_VISION_TOWER=1`) |
| `tokenizer/` | ~30 MB | **sì** — la directory intera |

Non scaricare `qwen38-flash-next-w4b.hgn` (115,55 GiB): è il checkpoint della
0.14, lo carica ancora ma non è quello di questa ricetta. `ht43.hgn` è
l'alternativa più leggera, opt-in: vedi `docs/sizing.md`.

```bash
# una volta sola, ~115 GB
pip install -U "huggingface_hub[cli]"
mkdir -p ~/halogen-models
hf download peonist-ai/halogen-qwen3.8-flash-next \
  --local-dir ~/halogen-models

# la verifica che conta: i quattro file + tokenizer, alle dimensioni giuste
cd ~/halogen-models
du -sh . tokenizer
ls -l qwen38-flash-next-v2.hgn qwen38-flash-next-ngram.hgn \
      qwen38-flash-next-drafter-r2-ht4.hgn qwen38-flash-next-vision.hgn
```

`hf download` riprende da dove si era interrotto: se cade la rete, rilancia lo
stesso comando. I file parziali hanno estensione `.incomplete` e non vanno
rinominati a mano.

Lo spazio è il vincolo vero: ~115 GB per i pesi **più** fino a
`HALOGEN_CACHE_DISK_GIB` (96 nella quadlet) per la cache del prompt. Servono
almeno 220 GB liberi sulla stessa partizione, oppure due partizioni diverse.

## 2. La BIOS: carve-out UMA al minimo

Questo motore vuole la **RAM**, non la VRAM dedicata. Va contro l'istinto, e la
maggior parte dei server di inferenza su questa APU vuole il contrario.

Nella BIOS cerca `UMA Frame Buffer Size` (o `Dedicated Graphics Memory`) e
mettilo al **valore minimo esplicito**, non su `Auto`. Su alcune schede `Auto`
significa 64 GiB: il sistema operativo vede 61 GiB su 128 e i pesi non partono.
Su un ASUS con 128 GB il minimo riporta circa 512 MiB.

Il server stampa quello che ha trovato all'avvio e avvisa quando è grande:

```
memory: 16.0 GiB of this machine's RAM is carved out for the iGPU in firmware.
```

Se leggi quella riga con un numero grande, torna nella BIOS prima di
smontare il resto: il pool KV si dimensiona sulla RAM **che il sistema
riporta**, quindi un carve-out grosso fa scegliere un pool più piccolo in
silenzio.

## 3. Il kernel: gfx1151 e SVM

Il checkpoint è un file mappato in sola lettura e registrato con la GPU in
place. Per farlo il kernel deve avere entrambe:

1. **Le due fix di AMD al driver KFD per gfx1151.** Il minimo indicato da AMD
   per Strix Halo è Linux 6.18.4, oppure Ubuntu 24.04 HWE `6.17.0-19.19~24.04.2`
   / OEM `6.14.0-1018`, o successivi.
2. **`CONFIG_HSA_AMD_SVM`** (che richiede `CONFIG_DEVICE_PRIVATE`). Senza SVM la
   registrazione in sola lettura fallisce **qualunque sia la dimensione**. Fedora
   6.18.6-200.fc43 era compilato senza, e la 6.18.7-200.fc43 l'ha riacceso.
   I kernel Ubuntu ce l'hanno.

Si leggono senza container, sul nodo KFD con `gfx_target_version` = `110501`:

```bash
for p in /sys/class/kfd/kfd/topology/nodes/*/properties; do
  grep -q 110501 "$p" 2>/dev/null || continue
  grep -E '^(capability|cwsr_size|ctl_stack_size|simd_count)' "$p"
done
```

Nella riga `capability` deve essere acceso il bit `0x08000000` (SVM c'è).
E deve esistere una riga `cwsr_size` uguale a
`ctl_stack_size + (simd_count / 2) * 479232`: è così che si riconoscono le due
fix di gfx1151.

**Se il server parte ma non arriva mai a "ready", il sospetto numero uno è
questo**, non la quadlet: leggi il prologo del container, la riga che nomina la
registrazione rifiutata dice quale dei due manca.

## 4. Gli altri due "lascia perdere"

- **WSL2 non è un host supportato.** Passa per `/dev/dxg`, non per KFD: la
  registrazione viene rifiutata e il server non arriva a ready. Serve Linux
  nativo, sul ferro. Stessa cosa per Windows nativo: il motore non esiste lì,
  e i `.hgn` non si aprono con llama.cpp, vLLM o transformers.
- **Una macchina dedicata.** Il server tiene residenti i pesi e prenota il pool
  KV: su 128 GB restano ~12 GiB. Se ci metti sopra altro (database, altri
  container, un altro modello) non fallisce in modo pulito: il kernel cerca
  memoria contigua, e sia il server sia il vicino possono fermarsi per minuti
  al 100% di un core senza scrivere niente. Non è un crash e non serve
  riavviarlo. Guarda la riga `host memory left` all'avvio e dimensiona i
  vicini su quella, non su `free`.

## L'ordine giusto

```bash
# 1. BIOS (riavvio) -> 2. kernel -> 3. pesi -> 4. quadlet -> 5. health
bash tools/preflight.sh          # dice se i punti 2-3 ci sono, senza container
```

Se `preflight.sh` passa tutto, la quadlet parte. Se non passa, il motivo è
scritto lì e non serve niente di questa pagina oltre la sezione relativa.
