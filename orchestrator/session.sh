#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
source "$SCRIPT_DIR/config.sh"

LOGDIR="$PROJECT_DIR/logs"
SESSIONS_LOG="$LOGDIR/sessions.log"
mkdir -p "$LOGDIR"

LOG_BASENAME="$(date +%Y%m%d_%H%M%S)"
LOG_STATE_EVAL="$LOGDIR/${LOG_BASENAME}_state_eval.log"
LOG_ACTOR="$LOGDIR/${LOG_BASENAME}.log"
LOG_ACTION_EVAL="$LOGDIR/${LOG_BASENAME}_action_eval.log"

# --- Session counter ---
COUNTER_FILE="$LOGDIR/.session_counter"
if [ -f "$COUNTER_FILE" ]; then
  SESSION_NUM=$(( $(cat "$COUNTER_FILE") + 1 ))
else
  SESSION_NUM=22  # continuing from 21 existing sessions
fi
echo "$SESSION_NUM" > "$COUNTER_FILE"

echo "$(date -u +%Y-%m-%dT%H:%M:%SZ)|started|session=$SESSION_NUM|$LOG_BASENAME" >> "$SESSIONS_LOG"

# --- Step 1: State Evaluator ---
echo "[$(date -u +%Y-%m-%dT%H:%M:%SZ)] Starting State Evaluator"
STATE_EVAL_EXIT=0
timeout "${STATE_EVAL_TIMEOUT:-30}m" codex exec \
  "$(cat "$HOME/AGENTS.md" "$SCRIPT_DIR/EVAL_STATE_PROMPT.md")" \
  --dangerously-bypass-approvals-and-sandbox \
  --cd "$PROJECT_DIR/alife" \
  --json > "$LOG_STATE_EVAL" 2>"$LOG_STATE_EVAL.err" || STATE_EVAL_EXIT=$?
echo "[$(date -u +%Y-%m-%dT%H:%M:%SZ)] State Evaluator finished (exit=$STATE_EVAL_EXIT)"

if [ "$STATE_EVAL_EXIT" -ne 0 ]; then
  echo "[$(date -u +%Y-%m-%dT%H:%M:%SZ)] State Evaluator failed — skipping Actor and Action Evaluator"
  echo "$(date -u +%Y-%m-%dT%H:%M:%SZ)|aborted|state_exit=$STATE_EVAL_EXIT|session=$SESSION_NUM|$LOG_BASENAME" >> "$SESSIONS_LOG"
  exit 1
fi

# --- Research checkpoint flag ---
RESEARCH_FLAG=""
if (( SESSION_NUM % RESEARCH_CHECKPOINT_INTERVAL == 0 )); then
  RESEARCH_FLAG="

--- RESEARCH CHECKPOINT (session $SESSION_NUM) ---
Before deciding what to implement, spend time reviewing your trajectory:
- Read docs/RESEARCH.md if it exists. Are your questions getting answered?
- Look at your recent sessions in docs/DEVLOG.md. What pattern do you see?
- Is the simulation producing any behavior you did not predict?
- Is there a question you have been avoiding?
You may still implement code this session. But start by thinking."
fi

# --- Step 2: Actor ---
echo "[$(date -u +%Y-%m-%dT%H:%M:%SZ)] Starting Actor (session=$SESSION_NUM)"
ACTOR_EXIT=0
timeout "${TIMEOUT:-35}m" codex exec \
  "$(cat "$HOME/AGENTS.md" "$SCRIPT_DIR/AGENT_PROMPT.md")$RESEARCH_FLAG" \
  --dangerously-bypass-approvals-and-sandbox \
  --cd "$PROJECT_DIR/alife" \
  --json > "$LOG_ACTOR" 2>"$LOG_ACTOR.err" || ACTOR_EXIT=$?
echo "[$(date -u +%Y-%m-%dT%H:%M:%SZ)] Actor finished (exit=$ACTOR_EXIT)"

if [ "$ACTOR_EXIT" -ne 0 ]; then
  echo "[$(date -u +%Y-%m-%dT%H:%M:%SZ)] Actor failed — skipping Action Evaluator"
  echo "$(date -u +%Y-%m-%dT%H:%M:%SZ)|aborted|state_exit=$STATE_EVAL_EXIT|actor_exit=$ACTOR_EXIT|session=$SESSION_NUM|$LOG_BASENAME" >> "$SESSIONS_LOG"
  exit 1
fi

# --- Step 3: Action Evaluator ---
echo "[$(date -u +%Y-%m-%dT%H:%M:%SZ)] Starting Action Evaluator"
ACTION_EVAL_EXIT=0
source ~/.secrets/openai
ACTION_EVAL_PROMPT="$(cat "$SCRIPT_DIR/EVAL_ACTION_PROMPT.md")

The actor session log is at: $LOG_ACTOR"
timeout "${ACTION_EVAL_TIMEOUT:-30}m" codex exec \
  "$ACTION_EVAL_PROMPT" \
  --dangerously-bypass-approvals-and-sandbox \
  --cd "$PROJECT_DIR/alife" \
  --json > "$LOG_ACTION_EVAL" 2>"$LOG_ACTION_EVAL.err" || ACTION_EVAL_EXIT=$?
echo "[$(date -u +%Y-%m-%dT%H:%M:%SZ)] Action Evaluator finished (exit=$ACTION_EVAL_EXIT)"

echo "$(date -u +%Y-%m-%dT%H:%M:%SZ)|finished|state_exit=$STATE_EVAL_EXIT|actor_exit=$ACTOR_EXIT|action_exit=$ACTION_EVAL_EXIT|session=$SESSION_NUM|$LOG_BASENAME" >> "$SESSIONS_LOG"

# Auto-cleanup: keep only last 30 days of logs
find "$LOGDIR" -name "*.log" -mtime +30 -delete 2>/dev/null || true
find "$LOGDIR" -name "*.log.err" -mtime +30 -delete 2>/dev/null || true
