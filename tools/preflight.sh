#!/usr/bin/env bash
# preflight.sh — "posso far partire la ricetta su questa macchina?"
#
# Controlla i prerequisiti che fanno fallire il setup in silenzio: kernel/KFD,
# SVM, dispositivi, pesi, RAM, spazio per la cache, podman. Non avvia niente e
# non modifica niente: solo lettura.
#
# Exit: 0 = pronto, 1 = manca qualcosa (ogni riga FAIL dice cosa).
#       Con --warn-only i FAIL diventano avvisi ed esce 0.
#
#   bash tools/preflight.sh [--warn-only] [--models DIR] [--cache DIR]
#
set -uo pipefail

WARN_ONLY=0
MODELS="${HALOGEN_MODELS:-$HOME/halogen-models}"
CACHE="${HALOGEN_CACHE:-$HOME/.cache/halogen-cache}"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --warn-only) WARN_ONLY=1 ;;
    --models) MODELS="${2:?}"; shift ;;
    --cache)  CACHE="${2:?}"; shift ;;
    -h|--help) sed -n '2,14p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "argomento sconosciuto: $1" >&2; exit 2 ;;
  esac
  shift
done

FAILS=0
ok()   { printf '  \033[32mok\033[0m    %s\n' "$*"; }
warn() { printf '  \033[33mwarn\033[0m  %s\n' "$*"; }
bad()  { printf '  \033[31mFAIL\033[0m  %s\n' "$*"; FAILS=$((FAILS+1)); }
head_() { printf '\n%s\n' "$*"; }

# --- 1. host: Linux nativo, non WSL, non container -------------------------
head_ "host"
if [[ -r /proc/version ]] && grep -qi microsoft /proc/version; then
  bad "sei su WSL2: il motore passa per /dev/dxg e la registrazione viene rifiutata. Serve Linux nativo."
elif [[ ! -e /proc/version ]]; then
  bad "non sembra Linux: il motore esiste solo per Linux nativo (amdgpu/KFD)."
else
  ok "Linux nativo ($(uname -r))"
fi
if [[ -f /run/.containerenv ]] || [[ -f /.dockerenv ]]; then
  warn "stai girando dentro un container: i controlli su /dev e sysfs riflettono quello"
fi

# --- 2. kernel: gfx1151 + SVM ---------------------------------------------
head_ "kernel / KFD"
if [[ ! -d /sys/class/kfd/kfd/topology/nodes ]]; then
  bad "/sys/class/kfd non c'è: manca il driver amdgpu/KFD o i permessi. Con i pesi mappati in place il server non parte."
else
  found=0
  for p in /sys/class/kfd/kfd/topology/nodes/*/properties; do
    [[ -r $p ]] || continue
    grep -qx 'gfx_target_version 110501' "$p" 2>/dev/null || continue
    found=1
    ok "GPU gfx1151 trovata ($(dirname "$p" | xargs basename))"

    cap=$(awk '/^capability /{print $2; exit}' "$p")
    if [[ -n ${cap:-} ]] && (( cap & 0x08000000 )); then
      ok "SVM compilato nel kernel (capability bit 0x08000000)"
    else
      bad "manca CONFIG_HSA_AMD_SVM (capability=$cap): ogni registrazione read-only fallisce, qualunque dimensione. Kernel Ubuntu >= 6.17 o Fedora >= 6.18.7."
    fi

    cwsr=$(awk '/^cwsr_size /{print $2; exit}' "$p")
    ctl=$(awk '/^ctl_stack_size /{print $2; exit}' "$p")
    simd=$(awk '/^simd_count /{print $2; exit}' "$p")
    if [[ -z ${cwsr:-} ]]; then
      bad "manca cwsr_size: il kernel non ha le fix gfx1151 di AMD (serve >= 6.18.4, Ubuntu HWE 6.17.0-19.19)"
    elif [[ -n ${ctl:-} && -n ${simd:-} ]] && (( cwsr == ctl + (simd/2)*479232 )); then
      ok "le due fix gfx1151 sono presenti (cwsr_size coerente)"
    else
      warn "cwsr_size=$cwsr non corrisponde a ctl_stack_size+(simd_count/2)*479232: controlla la versione del kernel"
    fi
  done
  (( found )) || bad "nessun nodo KFD con gfx_target_version 110501: non è una Strix Halo (o il modulo non è caricato)"
fi

# --- 3. dispositivi -------------------------------------------------------
head_ "dispositivi"
for d in /dev/kfd /dev/dri; do
  if [[ -e $d ]]; then ok "$d presente"; else bad "$d manca: la quadlet ha AddDevice=$d e non partirà"; fi
done
if [[ -e /dev/dri/renderD128 ]]; then
  if [[ -r /dev/dri/renderD128 && -w /dev/dri/renderD128 ]]; then
    ok "/dev/dri/renderD128 accessibile al tuo utente"
  else
    bad "/dev/dri/renderD128 non accessibile: aggiungiti al gruppo render (o usa GroupAdd=keep-groups nella quadlet)"
  fi
fi

# --- 4. RAM ---------------------------------------------------------------
head_ "memoria"
if [[ -r /proc/meminfo ]]; then
  total_kb=$(awk '/^MemTotal:/{print $2}' /proc/meminfo)
  avail_kb=$(awk '/^MemAvailable:/{print $2}' /proc/meminfo)
  total_gib=$(( total_kb / 1048576 ))
  avail_gib=$(( avail_kb / 1048576 ))
  if (( total_gib >= 96 )); then
    ok "RAM totale ${total_gib} GiB (>= 96 richiesti)"
  else
    bad "RAM totale ${total_gib} GiB: il server chiede ~89,8 GiB con ctx 131072 e pool 524288. Con meno, vedi docs/sizing.md (ctx 65536 + pool 262144)."
  fi
  if (( avail_gib < 90 )); then
    warn "RAM disponibile ora ${avail_gib} GiB: chiudi quello che puoi, il server prenota il pool all'avvio"
  else
    ok "RAM disponibile ora ${avail_gib} GiB"
  fi
fi

# --- 5. pesi --------------------------------------------------------------
head_ "pesi ($MODELS)"
need=(qwen38-flash-next-v2.hgn qwen38-flash-next-ngram.hgn qwen38-flash-next-drafter-r2-ht4.hgn)
if [[ -d $MODELS ]]; then
  for f in "${need[@]}"; do
    if [[ -f $MODELS/$f ]]; then
      # dimensione minima plausibile: un file troncato da un download interrotto
      # è la causa più comune di "il server non parte" senza errore chiaro
      sz=$(stat -c %s "$MODELS/$f" 2>/dev/null || echo 0)
      if (( sz > 1200000000 )); then
        ok "$f ($(numfmt --to=iec --suffix=B "$sz" 2>/dev/null || echo "$sz B"))"
      else
        bad "$f è di $sz byte: scaricamento incompleto. Rilancia 'hf download' (riprende da solo)."
      fi
    else
      bad "$f manca in $MODELS"
    fi
  done
  if [[ -d $MODELS/tokenizer && -f $MODELS/tokenizer/tokenizer.json ]]; then
    ok "tokenizer/ presente"
  else
    bad "tokenizer/ manca: la chat template e i token si leggono da lì"
  fi
  [[ -f $MODELS/qwen38-flash-next-vision.hgn ]] && ok "vision tower presente" \
    || warn "qwen38-flash-next-vision.hgn assente: la quadlet ha HALOGEN_VISION_TOWER=1 e senza il file le immagini vengono rifiutate. Toglilo o scarica il file."
  # i file w4b sono della 0.14: se ci sono, nessun problema, ma non sono usati
  [[ -f $MODELS/qwen38-flash-next-w4b.hgn ]] && warn "c'è anche il checkpoint w4b (0.14): occupa 115 GiB e non viene usato da questa ricetta"
else
  bad "$MODELS non esiste: vedi docs/requirements.md per come prendere i pesi (~115 GB)"
  warn "alternativa: metti --models <dir> o HALOGEN_MODELS=<dir>"
fi

# --- 6. spazio per la cache ----------------------------------------------
head_ "spazio disco"
[[ -d $CACHE ]] || warn "$CACHE non esiste ancora (la crea la quadlet? no: fallo tu, vedi sotto)"
probe="$CACHE"
[[ -d $probe ]] || probe=$(dirname "$probe")
if avail=$(df -B1 --output=avail "$probe" 2>/dev/null | tail -1); then
  avail_gib=$(( avail / 1073741824 ))
  if (( avail_gib >= 100 )); then
    ok "${avail_gib} GiB liberi su $probe (la cache è limitata a 96 GiB)"
  elif (( avail_gib >= 40 )); then
    warn "${avail_gib} GiB liberi su $probe: sotto i 96 GiB di HALOGEN_CACHE_DISK_GIB. Abbassa il bound o sposta la cache."
  else
    bad "${avail_gib} GiB liberi su $probe: troppo pochi per la cache del prompt"
  fi
fi
if [[ -d $CACHE ]]; then
  # stat -f è l'unico affidabile: `df -T --output=fstype` è mutuamente esclusivo
  # (GNU coreutils rifiuta la combinazione) e il controllo salterebbe in silenzio.
  fs=$(stat -f -c %T "$CACHE" 2>/dev/null || true)
  case "$fs" in
    tmpfs|overlay|overlayfs|ramfs|none)
      bad "$CACHE è su $fs: la cache su disco richiede O_DIRECT e su tmpfs/overlay viene rifiutata (resta in memoria). Usa btrfs/ext4/xfs." ;;
    ext2/ext3)
      # stat -f riporta la firma del magic number: ext4 si presenta così
      ok "$CACHE è su ext4 (accetta O_DIRECT)" ;;
    "")
      warn "tipo di filesystem di $CACHE non riconosciuto: verifica che accetti O_DIRECT (non deve essere tmpfs/overlay)" ;;
    *)
      ok "$CACHE è su $fs (accetta O_DIRECT)" ;;
  esac
  [[ -w $CACHE ]] && ok "$CACHE è scrivibile" || bad "$CACHE non è scrivibile dal tuo utente"
fi

# --- 7. podman + systemd utente ------------------------------------------
head_ "runtime"
if command -v podman >/dev/null; then
  v=$(podman --version 2>/dev/null | awk '{print $3}')
  ok "podman $v"
  if podman info --format '{{.Host.Security.Rootless}}' 2>/dev/null | grep -qx true; then
    ok "podman rootless"
  else
    warn "podman non rootless (o non interrogabile): la ricetta assume rootless + systemctl --user"
  fi
else
  bad "podman non installato: la quadlet è una unit Podman utente"
fi
if systemctl --user show-environment >/dev/null 2>&1; then
  ok "systemd --user raggiungibile"
  if loginctl show-user "$USER" -p Linger 2>/dev/null | grep -q 'Linger=yes'; then
    ok "linger attivo: il servizio parte anche senza sessione aperta"
  else
    warn "linger spento: dopo il logout il servizio si ferma. 'sudo loginctl enable-linger $USER'"
  fi
else
  bad "systemd --user non raggiungibile: la quadlet non può girare"
fi

# --- 8. server già in ascolto? -------------------------------------------
head_ "stato"
if command -v curl >/dev/null && curl -s --max-time 3 http://127.0.0.1:8731/health >/dev/null 2>&1; then
  ok "un server risponde già su 127.0.0.1:8731 (usa tools/health.sh)"
else
  ok "porta 8731 libera"
fi

# --- verdetto -------------------------------------------------------------
printf '\n'
if (( FAILS == 0 )); then
  printf '\033[32mpronto\033[0m: la ricetta può partire. Copia la quadlet, correggi i due path, avvia.\n'
  exit 0
fi
if (( WARN_ONLY )); then
  printf '\033[33m%s problemi\033[0m (--warn-only: esco 0)\n' "$FAILS"
  exit 0
fi
printf '\033[31m%s problemi\033[0m da risolvere: ogni FAIL qui sopra dice cosa e dove.\n' "$FAILS"
printf 'Guida: docs/requirements.md\n'
exit 1
