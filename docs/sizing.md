# Dimensionamento: ctx, pool KV, RAM

La confusione più comune è credere che "ctx 128k" significhi "128k di prompt".
Non è così. Questa pagina è il conto che serve per non far rifiutare il server
all'avvio.

## La regola

```
HALOGEN_CTX = prompt + max_tokens
```

`HALOGEN_CTX` è il **totale** di una singola richiesta, non il solo prompt.
Con `HALOGEN_MAX_TOKENS_DEFAULT=16384`, il prompt più lungo che un client può
mandare è `131072 − 16384 = 114688` token. Il server rifiuta solo ciò che sfora
davvero: se la risposta è corta, il prompt può essere più lungo.

## Il pool KV

`HALOGEN_KV_POOL_POSITIONS` è la memoria condivisa in cui vivono le
conversazioni. Ogni richiesta **prenota `prompt + max_tokens`**, non `prompt`.
Una conversazione da 79.096 token con `max_tokens=16384` prenota 95.744
posizioni.

| pool | quante conversazioni | RAM device |
|---|---|---|
| 262144 (2 × 128k) | 2 da 128k | ~7 GiB |
| 524288 (4 × 128k) | **4 da 128k** ← noi | ~14,4 GiB |
| 1048576 (8 × 128k) | 8 da 128k | ~29 GiB |

La quinta richiesta contemporanea **aspetta**, non fallisce. Il produttore
consiglia 524288 con 4 slot: è il compromesso giusto per 4 sessioni agentiche.

> Se le conversazioni sono molto lunghe (oltre ~64k) e vuoi che restino calde
> tra un riavvio e l'altro, il produttore suggerisce di **ridurre** il pool a
> 262144: la copia su disco della cache rallenta quando il pool è pieno.

## Il conto della RAM

| voce | GiB |
|---|---|
| Pesi (62,9 miliardi di parametri) | 62,9 |
| Pool KV (524288 posizioni) | 14,4 |
| Working set | 12,4 |
| **Totale server** | **~89,8** |
| Host residuo (con 121 GiB) | ~18,4 |

Con meno di 96 GiB di RAM il server **non parte**: l'allocazione non ci sta e
lo dice. Non è un caso di swap: è un rifiuto all'avvio.

## Cosa cambiare se hai meno RAM

```
HALOGEN_CTX=65536
HALOGEN_KV_POOL_POSITIONS=262144
```

Stesse 4 conversazioni, metà della profondità: ~7 GiB di pool invece di 14,4.
Per un coding agent a turni brevi va benissimo; perde il long-context, che è
il motivo per cui hai scelto questo modello.

## Visione

`HALOGEN_VISION_TOWER=1` carica la torre visiva (un checkpoint accanto al
principale, `qwen38-flash-next-vision.hgn`). Serve a far leggere gli screenshot
al modello: è così che un agente verifica da solo una GUI. Costa qualche GiB di
VRAM e un po' di prefill sulle richieste con immagini.
