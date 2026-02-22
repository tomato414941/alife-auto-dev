#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
source "$SCRIPT_DIR/config.sh"

LOGDIR="$PROJECT_DIR/logs"
SESSIONS_LOG="$LOGDIR/sessions.log"
mkdir -p "$LOGDIR"

LOG_BASENAME="$(date +%Y%m%d_%H%M%S)"
LOG_PRE_EVAL="$LOGDIR/${LOG_BASENAME}_pre_eval.log"
LOG_ACTOR="$LOGDIR/${LOG_BASENAME}.log"
LOG_POST_EVAL="$LOGDIR/${LOG_BASENAME}_post_eval.log"

echo "$(date -u +%Y-%m-%dT%H:%M:%SZ)|started|$LOG_BASENAME" >> "$SESSIONS_LOG"

# --- Step 1: Pre-Evaluator ---
echo "[$(date -u +%Y-%m-%dT%H:%M:%SZ)] Starting Pre-Evaluator"
PRE_EVAL_EXIT=0
timeout "${PRE_EVAL_TIMEOUT:-5}m" codex exec \
  "$(cat "$HOME/AGENTS.md" "$SCRIPT_DIR/EVAL_PRE_PROMPT.md")" \
  --dangerously-bypass-approvals-and-sandbox \
  --cd "$PROJECT_DIR/alife" \
  --json > "$LOG_PRE_EVAL" 2>"$LOG_PRE_EVAL.err" || PRE_EVAL_EXIT=$?
echo "[$(date -u +%Y-%m-%dT%H:%M:%SZ)] Pre-Evaluator finished (exit=$PRE_EVAL_EXIT)"

# --- Step 2: Actor ---
echo "[$(date -u +%Y-%m-%dT%H:%M:%SZ)] Starting Actor"
ACTOR_EXIT=0
timeout "${TIMEOUT:-35}m" codex exec \
  "$(cat "$HOME/AGENTS.md" "$SCRIPT_DIR/AGENT_PROMPT.md")" \
  --dangerously-bypass-approvals-and-sandbox \
  --cd "$PROJECT_DIR/alife" \
  --json > "$LOG_ACTOR" 2>"$LOG_ACTOR.err" || ACTOR_EXIT=$?
echo "[$(date -u +%Y-%m-%dT%H:%M:%SZ)] Actor finished (exit=$ACTOR_EXIT)"

# --- Step 3: Post-Evaluator ---
echo "[$(date -u +%Y-%m-%dT%H:%M:%SZ)] Starting Post-Evaluator"
POST_EVAL_EXIT=0
source ~/.secrets/openai
timeout "${EVAL_TIMEOUT:-5}m" codex exec \
  "$(cat "$SCRIPT_DIR/EVAL_POST_PROMPT.md")" \
  --dangerously-bypass-approvals-and-sandbox \
  --cd "$PROJECT_DIR/alife" \
  --json > "$LOG_POST_EVAL" 2>"$LOG_POST_EVAL.err" || POST_EVAL_EXIT=$?
echo "[$(date -u +%Y-%m-%dT%H:%M:%SZ)] Post-Evaluator finished (exit=$POST_EVAL_EXIT)"

echo "$(date -u +%Y-%m-%dT%H:%M:%SZ)|finished|pre_exit=$PRE_EVAL_EXIT|actor_exit=$ACTOR_EXIT|post_exit=$POST_EVAL_EXIT|$LOG_BASENAME" >> "$SESSIONS_LOG"

# Auto-cleanup: keep only last 30 days of logs
find "$LOGDIR" -name "*.log" -mtime +30 -delete 2>/dev/null || true
find "$LOGDIR" -name "*.log.err" -mtime +30 -delete 2>/dev/null || true
