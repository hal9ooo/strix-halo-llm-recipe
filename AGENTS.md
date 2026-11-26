<!-- sprint-flow:begin (gestito da sprint-flow: non modificare a mano) -->
## Backlog e changelog

- `BACKLOG.md`: le regole sono in testa al file. Una voce fatta si **toglie**
  nello stesso commit del lavoro; un bug o un'idea trovati per strada si
  **aggiungono** lì.
- `CHANGELOG.md` lo scrive ogni notte un timer, dai commit: non modificarlo.
  Scrivi messaggi di commit chiari (`feat(area): cosa cambia`), perché il
  changelog nasce da lì. Chi ha fatto cosa lo dicono i trailer `Agent:`: non
  toglierli.
<!-- sprint-flow:end -->

# Come si usa questa ricetta (contratto per agenti)

Sei un agente che ha appena clonato questo repo su una macchina Strix Halo.
Questo file è la procedura. Non improvvisare: ogni passo esiste perché senza
fallisce in un modo che sembra un altro problema.

## Che cosa è questo repo

Una **ricetta di deployment**, non software. Contiene una unit Podman, un
blocco di configurazione per OpenCode, tre script e la documentazione che
spiega perché ogni valore è quello. Non contiene il modello (115 GB, sta su
Hugging Face) né il motore (immagine chiusa su ghcr.io).

## Ordine obbligatorio

```bash
bash tools/preflight.sh        # 1. dice se la macchina può
```

Se `preflight.sh` esce **1**, fermati e leggi i `FAIL`: ognuno nomina la cosa
mancante e dove sta la spiegazione. Non aggirarli, non "provare lo stesso": i
quattro FAIL tipici (Windows/WSL2, `/dev/kfd` assente, SVM spento nel kernel,
pesi mancanti o troncati) non hanno workaround, e ognuno costa ore se
interpretato male.

Con `preflight.sh` a exit **0**:

```bash
# 2. pesi: ~115 GB, pubblici. Vedi docs/requirements.md per le dimensioni attese.
hf download peonist-ai/halogen-qwen3.8-flash-next --local-dir ~/halogen-models

# 3. unit, con i TRE path da correggere
mkdir -p ~/.config/containers/systemd
cp quadlet/halogen-flash.container ~/.config/containers/systemd/
#   Volume=<pesi>:/models:ro
#   Volume=<home>/.cache/halogen-cache:/cache   (la directory deve esistere)
#   ContainerName, se ne gira più di una

# 4. cache su disco reale + sopravvivenza al logout
mkdir -p ~/.cache/halogen-cache
sudo loginctl enable-linger "$USER"

# 5. avvio e verifica
systemctl --user daemon-reload
systemctl --user start halogen-flash
bash tools/health.sh
```

Il primo avvio **mappa 115 GB**: impiega minuti e `health.sh` dice
`container: running ma l'API non risponde — sta ancora caricando i pesi?`.
È normale. Non riavviare: aspetta e rileggi.

## Regole che non si negoziano

1. **Mai root.** La quadlet è una unit `systemd --user`. Se l'hai copiata in
   `/etc/containers/systemd/` hai sbagliato file di destinazione.
2. **La porta resta su `127.0.0.1`.** `PublishPort=127.0.0.1:8731:8731`, non
   `8731:8731`. Il server non ha API key: su `0.0.0.0` chiunque sulla LAN legge
   le conversazioni. Se ti serve da fuori, `HALOGEN_API_KEY` **e** un reverse
   proxy con TLS.
3. **Non alzare `HALOGEN_KV_POOL_POSITIONS`** senza rifare il conto di
   `docs/sizing.md`. Il server prenota tutto all'avvio e rifiuta di partire se
   non ci sta: non è swap, è un rifiuto.
4. **Non attivare `HALOGEN_INDEXER_BUDGET=4096` né `HALOGEN_COMPOSABLE_CONTEXT=1`**
   senza misurare. Il secondo **rifiuta le immagini**: se ti serve la visione,
   resta spento.
5. **La cache va su btrfs/ext4/xfs.** Su tmpfs e overlay il server la rifiuta e
   resta in memoria, in silenzio. `preflight.sh` lo controlla.
6. **Un test per volta, porta effimera.** Se lanci test che aprono un server,
   usa `PORT=8199` e ferma solo i processi tuoi (pidfile). Il modello è uno
   solo: due processi che lo caricano si rubano la RAM e bloccano la macchina.

## Se qualcosa non va

| sintomo | dove guardare |
|---|---|
| `preflight.sh` esce 1 | la riga `FAIL` stessa, poi `docs/requirements.md` |
| il container non esiste | la quadlet non è in `~/.config/containers/systemd/` o manca `daemon-reload` |
| `running` ma API muta | sta caricando: `podman logs --tail 50 halogen-flash` |
| `exited` subito | `journalctl --user -u halogen-flash -n 50`: RAM, SVM, o path dei volumi |
| parte e non arriva mai a ready | registro rifiutato → kernel senza SVM, vedi `requirements.md` §3 |
| cache `disk.on: false` | filesystem senza `O_DIRECT` (tmpfs/overlay) |
| muore dopo il logout | manca `loginctl enable-linger` |
| script: `pipefail: invalid option name` | fine riga CRLF, vedi `troubleshooting.md` |

Il resto dei problemi reali è in `docs/troubleshooting.md`, ognuno con sintomo,
causa e rimedio.

## Cosa NON è supportato, e non è un bug

- **Windows nativo**: il motore non esiste. I pesi `.hgn` non si aprono con
  llama.cpp, vLLM o transformers.
- **WSL2**: passa per `/dev/dxg`, non per KFD: la registrazione viene rifiutata.
- **GPU diverse da gfx1151**: nessun kernel è scritto per loro.
- **Meno di 96 GB di RAM** con i valori di questa ricetta: vedi `docs/sizing.md`
  per i valori ridotti.

In questi casi la risposta corretta è dirlo, non provare una variante.

## Se modifichi la ricetta

- Un numero misurato che cambi va rimisurato, e la pagina che lo cita va
  aggiornata insieme (`docs/measured.md`, `docs/sizing.md`, i due README).
- `tools/preflight.sh` deve continuare a uscire 0 su una macchina pronta e 1 su
  una che non lo è: è il contratto che rende il repo usabile da soli.
- Commit in `feat(area): cosa cambia` / `fix(area): ...`, con il trailer
  `Agent:`.
