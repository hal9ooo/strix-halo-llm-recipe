#!/usr/bin/env bash
# agent.sh — lancia un coding agent (OpenCode) sul modello locale.
#
#   tools/agent.sh <workdir> <prompt-o-file> [session-id]
#
# Env:
#   MODEL    default halogen/halogen-qwen3.8-flash-next#xhigh
#   TIMEOUT  secondi, default 5400 (90 min)
#   LOG      path del log (default: <workdir>/../run/<nome>-<timestamp>.log)
#
# Exit: 0 ok · 124 timeout · altro = errore dell'agente.
#
# Perché serve: un turno agentico su questo modello può durare 30-90 minuti.
# `timeout` evita che un agente bloccato resti appeso, e il log su file è
# l'unico modo per capire dopo cosa ha fatto.
set -uo pipefail

WORKDIR="${1:?workdir}"
PROMPT_ARG="${2:?prompt o file}"
SESSION="${3:-}"
MODEL="${MODEL:-halogen/halogen-qwen3.8-flash-next#xhigh}"
TIMEOUT="${TIMEOUT:-5400}"

PROMPT="$PROMPT_ARG"
[[ -f "$PROMPT_ARG" ]] && PROMPT="$(cat "$PROMPT_ARG")"

NAME="$(basename "$(cd "$WORKDIR" && pwd)")"
STAMP="$(date +%Y%m%d-%H%M%S)"
LOG="${LOG:-$(cd "$WORKDIR/.." && pwd)/run/${NAME}-${STAMP}.log}"
mkdir -p "$(dirname "$LOG")"

cd "$WORKDIR" || exit 2

ARGS=(run --auto -m "$MODEL" --title "$NAME")
[[ -n "$SESSION" ]] && ARGS+=(--session "$SESSION")
ARGS+=("$PROMPT")

echo "[agent] $(date -Is) $NAME model=$MODEL timeout=${TIMEOUT}s log=$LOG"
timeout "$TIMEOUT" opencode "${ARGS[@]}" >"$LOG" 2>&1
CODE=$?
echo "[agent] $(date -Is) $NAME exit=$CODE"
# le ultime righe senza codici colore
tail -n 30 "$LOG" | sed 's/\x1b\[[0-9;]*m//g'
exit "$CODE"
