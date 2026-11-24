# Problemi che abbiamo incontrato davvero

Non teoria: ognuno di questi ci è costato tempo.

## Il servizio non parte e resta in coda ~90 secondi

**Sintomo:** `systemctl --user start halogen-flash` non torna, `journalctl` non
mostra errori, dopo ~90 s fallisce.

**Causa:** la unit ha `After=network-online.target` (o lo eredita). Su questa
macchina quel target **non viene mai raggiunto**.

**Rimedio:** nessuna dipendenza dalla rete. Il container non apre connessioni:
i pesi sono già su disco (niente `HALOGEN_DOWNLOAD`). La nostra unit non ha
`After=` di rete, per questo.

## Il server rifiuta di partire: "allocation does not fit"

**Causa:** `HALOGEN_CTX` o il pool troppo grandi per la RAM.

**Rimedio:** vedi `sizing.md`. Con 121 GiB: ctx 131072 + pool 524288 = ~89,8 GiB
di server. Non alzare `HALOGEN_KV_POOL_POSITIONS` "per avere più sessioni"
senza fare il conto.

## La cache su disco non si attiva

**Sintomo:** `HALOGEN_CACHE_DIR` impostata, `/cache` riporta `disk.on: false` o
il server logga un rifiuto.

**Causa:** il filesystem non accetta `O_DIRECT`. **tmpfs e overlay sono
rifiutati**; la cache resta in memoria.

**Rimedio:** bind mount su un filesystem reale (btrfs/ext4). Da noi è la
partizione LUKS di `/home`, che sta sullo stesso SSD dei pesi ma fuori dalla
NTFS che li ospita.

## La cache si riempie e sfratta le sessioni in corso

**Sintomo:** dopo ore di lavoro, `/cache` mostra `evicted` che sale e le
conversazioni attive tornano a riprefillare.

**Causa:** `HALOGEN_CACHE_DISK_GIB` default **64 GiB**, e una conversazione da
128k pesa ~3,5 GiB: 17 conversazioni lo saturano.

**Rimedio:** alza il bound (`HALOGEN_CACHE_DISK_GIB=96`) **e** pota a mano le
conversazioni vecchie. Le sottodirectory sono una per conversazione: si cancellano
con `rm -rf` quelle che non servono, identificandole per data di modifica. Il
server non se ne accorge male: le rilegge solo se richieste.

## `systemctl --user restart` sembra lento

**Causa:** stop con 60 s di grazia per scrivere l'ultimo turno su disco. È
voluto: interromperlo perde la cache dell'ultimo turno.

**Rimedio:** aspettare. A caldo il riavvio è ~13 s; con conversazioni da
scrivere arriva a 60.

## La porta 8731 è aperta sulla LAN senza API key

**Sintomo:** `ss -ltnp | grep 8731` mostra `0.0.0.0:8731`, non `127.0.0.1`.

**Causa:** `PublishPort=8731:8731` pubblica su tutte le interfacce.

**Rimedio:** `PublishPort=127.0.0.1:8731:8731`, oppure `HALOGEN_API_KEY`.
Chiunque sulla LAN può usare il modello e leggere le tue conversazioni.

## Un agente ha ucciso il server di un altro progetto

Non è il modello, è il processo: quando più agenti girano in parallelo, ognuno
deve usare una **porta effimera** per i propri test (`PORT=8199 ./run.sh`) e
fermare **solo** i processi che ha avviato, tramite pidfile. Lo abbiamo messo
nel contratto degli agenti dopo che è successo.
