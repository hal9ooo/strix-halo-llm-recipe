# OpenCode: varianti di thinking

Il server gira a `xhigh` di default ed è la **raccomandazione del model card**
per il lavoro agentico. Le varianti servono ad abbassarlo per i task facili, non
a migliorare l'accuratezza.

| variante | cosa manda | quando |
|---|---|---|
| `#xhigh` | `reasoning_effort: xhigh` | **default per lavoro agentico** |
| `#high` / `#medium` / `#low` | l'effort corrispondente | task semplici, meno latenza |
| `#none` | `enable_thinking: false` | più veloce, **sbaglia i conteggi semplici** |

Sul nostro test: con `#none` il modello sbaglia un conteggio banale, con
thinking lo azzecca. Non usare `#none` per codice.

```bash
opencode run -m halogen/halogen-qwen3.8-flash-next "ciao"          # xhigh
opencode run -m halogen/halogen-qwen3.8-flash-next#none "ciao"     # veloce
```

## Perché "il default del server è quello che usa il tuo harness"

OpenCode non manda un controllo di thinking a un endpoint custom: quindi il
modello usa il default del template, che è già `xhigh`. **Non serve**
`HALOGEN_REASONING_EFFORT` nel quadlet.

## Budget dei token

`HALOGEN_MAX_TOKENS_DEFAULT=16384` è il taglio che copre reasoning + tool call +
risposta di un turno agentico ordinario, per i client che **non** mandano
`max_tokens`. OpenCode manda il suo 16384.

Il server lascia sempre `max(1024, 15% di max_tokens)` token per la risposta
quando il thinking sta per mangiarsi tutto il budget: con 16384 sono ~2.457
token, quindi non torna mai una risposta vuota con `finish_reason: length`.

## Il conto del contesto, in pratica

```
prompt (system + storia + tool result + messaggio)
+ max_tokens (thinking + tool call + risposta)
≤ 131072
```

Se una sessione agentica si avvicina al limite, il server tronca la richiesta
piuttosto che fallire — ma è il momento di compattare la storia.

## Timeout

`headerTimeout: 600000` (10 minuti) nel provider. I turni agentici lunghi con
thinking `xhigh` possono superare i 5 minuti: senza questo, il client chiude la
connessione a metà.
