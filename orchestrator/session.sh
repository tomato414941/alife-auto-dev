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

# Allow launching Claude Code from within another session (cron is fine, manual test may be nested)
unset CLAUDECODE 2>/dev/null || true

timeout "${TIMEOUT:-45}m" /home/dev/.local/bin/claude -p "$(cat "$SCRIPT_DIR/AGENT_PROMPT.md")" \
  --dangerously-skip-permissions \
  --max-turns "${MAX_TURNS:-80}" \
  --model "${MODEL:-sonnet}" \
  --output-format stream-json \
  --verbose > "$LOG" 2>"$LOG.err" &

CLAUDE_PID=$!
wait $CLAUDE_PID 2>/dev/null
EXIT_STATUS=$?

echo "$(date -u +%Y-%m-%dT%H:%M:%SZ) session_end code=$EXIT_STATUS log_size=$(wc -c < "$LOG")" >> "$SESSIONS_LOG"

# Auto-cleanup: keep only last 30 days of logs
find "$LOGDIR" -name "*.log" -mtime +30 -delete 2>/dev/null || true
find "$LOGDIR" -name "*.log.err" -mtime +30 -delete 2>/dev/null || true
