# Numeri misurati (Strix Halo, 121 GiB, server 0.20.7)

Tutto quello che segue è stato misurato su questa macchina, non copiato dalla
documentazione. Riproducibile con i comandi in fondo.

## Inferenza

| metrica | valore |
|---|---|
| Generazione aggregata | **58 tok/s** |
| Prefill | **~1.060 tok/s** |
| Prefill su prompt freddo da 38k | ~24 s |
| Prefill su prompt freddo da 120k | ~72 s |
| Prima risposta con conversazione in RAM | **114 ms** |
| Prima risposta dopo un riavvio (38k dal disco) | **193 ms** |

## Cache del prompt su disco

| metrica | valore |
|---|---|
| Peso per token di contesto | ~27 KiB |
| 38k token | ~1 GB |
| 128k token | ~3,5 GB |
| Hit rate in una sessione di 5 ore, 5 agenti | **93,8%** |
| Token di prompt evitati | **86,3 milioni** |
| Cache dopo 5 ore | 20 GiB (17 conversazioni prima della potatura) |

Il costo che la cache elimina: un turno da 38.593 token costa 24,2 s a freddo e
**193 ms** dopo un riavvio, ripristinato dal disco byte per byte.

## Concorrenza

| prova | risultato |
|---|---|
| 4 stream API, prompt condiviso ~5k, 256 token risposta, thinking off | 25,6–34,0 tok/s per stream, 46,6 aggregati |
| 8 richieste corte su 4 slot | prime 4 a 0,68 s, altre a 1,24–1,82 s, tutte corrette |
| 4 sessioni OpenCode in parallelo (con una già in volo) | 5 richieste → 4 in volo + 1 in coda, 4/4 corrette, 47–54 s |

Il prefisso condiviso viene ripreso dalla cache **anche partendo in parallelo**:
è la ragione per cui 4 agenti su 5 progetti diversi non si rallentano a vicenda
sul prompt di sistema.

## Cache in RAM (accounting del server)

`/cache` riporta `token_hit_rate`, `prompt_tokens_saved`, `disk.{bytes,records,
lineages}`, `pool.{used,positions}`. Attenzione: l'accounting **riparte da zero
al riavvio del server** — il disco no.

## Come riprodurre

```bash
# stato autoritativo
curl -s localhost:8731/health | jq '{status,model,context,slots,vision}'

# pool KV e cache
curl -s localhost:8731/cache | jq '{token_hit_rate, prompt_tokens_saved, pool}'

# throughput e richieste
curl -s localhost:8731/metrics | grep -E '^llamacpp:(tokens_predicted|prompt_tokens)_(total|seconds)'

# una misura di latenza pulita
time curl -s localhost:8731/v1/chat/completions \
  -H 'Content-Type: application/json' \
  -d '{"model":"halogen-qwen3.8-flash-next","messages":[{"role":"user","content":"ciao"}],"max_tokens":128}' \
  | jq '.usage'
```

## Nota sulla GPU

La GPU condivisa è da **4 GiB di VRAM** su questa APU, e durante l'inferenza sta
al ~5% di utilizzo: il modello lavora soprattutto su CPU e GTT (fino a 124 GiB
condivisi). Se ti aspetti `nvidia-smi`-style a 100%, non è quella la metrica
giusta qui: guarda `flash_serve` in `ps` e i token/s.
