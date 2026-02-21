#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
ALIFE_DIR="$PROJECT_DIR/alife"
LOGDIR="$PROJECT_DIR/logs"

source "$SCRIPT_DIR/config.sh"

EVAL_LOG="$LOGDIR/$(date +%Y%m%d_%H%M%S)_eval.log"

echo "$(date -u +%Y-%m-%dT%H:%M:%SZ) eval_start" >> "$LOGDIR/sessions.log"

# Load API key
source ~/.secrets/openai

timeout "${EVAL_TIMEOUT:-10}m" codex exec \
  "$(cat "$SCRIPT_DIR/EVAL_PROMPT.md")" \
  --dangerously-bypass-approvals-and-sandbox \
  --cd "$ALIFE_DIR" \
  --json > "$EVAL_LOG" 2>"$EVAL_LOG.err" &

CODEX_PID=$!
set +e
wait $CODEX_PID 2>/dev/null
EXIT_STATUS=$?
set -e

echo "$(date -u +%Y-%m-%dT%H:%M:%SZ) eval_end code=$EXIT_STATUS log_size=$(wc -c < "$EVAL_LOG")" >> "$LOGDIR/sessions.log"
