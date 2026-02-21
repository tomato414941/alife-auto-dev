#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
source "$SCRIPT_DIR/config.sh"

LOGDIR="$PROJECT_DIR/logs"
SESSIONS_LOG="$LOGDIR/sessions.log"
mkdir -p "$LOGDIR"

LOG="$LOGDIR/$(date +%Y%m%d_%H%M%S).log"

echo "$(date -u +%Y-%m-%dT%H:%M:%SZ) session_start" >> "$SESSIONS_LOG"

cd "$PROJECT_DIR"

timeout "${TIMEOUT:-45}m" codex exec \
  "$(cat "$HOME/AGENTS.md" "$SCRIPT_DIR/AGENT_PROMPT.md")" \
  --dangerously-bypass-approvals-and-sandbox \
  --json > "$LOG" 2>"$LOG.err" &

CODEX_PID=$!
set +e
wait $CODEX_PID 2>/dev/null
EXIT_STATUS=$?
set -e

echo "$(date -u +%Y-%m-%dT%H:%M:%SZ) session_end code=$EXIT_STATUS log_size=$(wc -c < "$LOG")" >> "$SESSIONS_LOG"

# Auto-cleanup: keep only last 30 days of logs
find "$LOGDIR" -name "*.log" -mtime +30 -delete 2>/dev/null || true
find "$LOGDIR" -name "*.log.err" -mtime +30 -delete 2>/dev/null || true
