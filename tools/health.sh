#!/usr/bin/env bash
# health.sh — stato del server halogen + cosa sta facendo adesso.
# Dipendenze: curl e jq. Sicuro da lanciare a mano o in cron.
# Exit: 0 = risponde, 1 = non risponde (con la causa probabile), 2 = manca jq.
set -uo pipefail
BASE="${HALOGEN_URL:-http://127.0.0.1:8731}"

if ! command -v jq >/dev/null; then
  echo "health.sh: manca jq (apt install jq / dnf install jq)" >&2
  exit 2
fi

get() { curl -s --max-time 5 "$BASE$1" 2>/dev/null; }

h="$(get /health)"
if [[ -z $h ]]; then
  echo "halogen: DOWN ($BASE non risponde)"
  # distinguere "container spento" da "container su ma non sano" è la
  # differenza fra un 'systemctl start' e un'indagine sul kernel.
  if command -v podman >/dev/null; then
    state=$(podman ps -a --filter name=^halogen-flash$ --format '{{.State}}' 2>/dev/null | head -1)
    case "$state" in
      "")
        echo "  container: non esiste — la quadlet non è installata o non è stata caricata"
        echo "  copia quadlet/halogen-flash.container in ~/.config/containers/systemd/ e:"
        echo "    systemctl --user daemon-reload && systemctl --user start halogen-flash" ;;
      running)
        echo "  container: running ma l'API non risponde — sta ancora caricando i pesi?"
        echo "  il primo avvio impiega minuti (mappa 115 GB): guarda il log"
        echo "    podman logs --tail 50 halogen-flash" ;;
      exited|created|paused|stopped)
        echo "  container: $state — non è partito, o è morto"
        echo "    journalctl --user -u halogen-flash -n 50"
        echo "    podman logs --tail 50 halogen-flash" ;;
      *)
        echo "  container: stato '$state'" ;;
    esac
  fi
  echo "  se il problema è all'avvio: bash tools/preflight.sh"
  exit 1
fi

echo "== halogen $(echo "$h" | jq -r '.version.api') — $BASE"
echo "$h" | jq -r '
  "   modello:    \(.model)",
  "   contesto:   \(.context) token per richiesta",
  "   pool KV:    \(.kv_pool_positions) posizioni",
  "   slot:       \(.slots) · in volo: \(.in_flight) · in coda: \(.queued)",
  "   visione:    \(if .vision.enabled then "attiva" else "spenta" end)",
  "   thinking:   default \(.reasoning_effort_default) · max_tokens \(.max_tokens_default)"'

c="$(get /cache)"
[[ -n $c ]] && echo "$c" | jq -r '
  "   cache:      hit \(.token_hit_rate | . * 100 | floor)% · \(.prompt_tokens_saved) token evitati",
  "   su disco:   \(.disk.bytes / 1073741824 | floor) GiB / \(.disk.budget_bytes / 1073741824 | floor) GiB · \(.disk.lineages) conversazioni"'

m="$(get /metrics)"
if [[ -n $m ]]; then
  # media dall'avvio: contatori cumulativi token/secondi
  awk '/^llamacpp:tokens_predicted_total /{t=$2} /^llamacpp:tokens_predicted_seconds_total /{s=$2}
       /^llamacpp:prompt_tokens_total /{pt=$2} /^llamacpp:prompt_seconds_total /{ps=$2}
       /^halogen:requests_total /{r=$2}
       END{
         gen = (s>0 ? t/s : 0); pre = (ps>0 ? pt/ps : 0);
         printf "   media:      %.1f tok/s gen · %.0f tok/s prefill · %d richieste servite\n", gen, pre, r
       }' <<<"$m"
fi

# memoria reale del processo, se è un container
name=$(podman ps --format '{{.Names}}' 2>/dev/null | grep -x halogen-flash)
if [[ -n $name ]]; then
  podman stats --no-stream --format '   memoria:    {{.MemUsage}} · cpu {{.CPUPerc}}' "$name" 2>/dev/null
fi
