#!/usr/bin/env bash
# health.sh — stato del server halogen + cosa sta facendo adesso.
# Nessuna dipendenza: curl e jq. Sicuro da lanciare a mano o in cron.
set -uo pipefail
BASE="${HALOGEN_URL:-http://127.0.0.1:8731}"

get() { curl -s --max-time 5 "$BASE$1" 2>/dev/null; }

h="$(get /health)"
if [[ -z $h ]]; then
  echo "halogen: DOWN ($BASE non risponde)"
  echo "  systemctl --user status halogen-flash"
  echo "  journalctl --user -u halogen-flash -n 50"
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
