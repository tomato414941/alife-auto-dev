#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
source "$SCRIPT_DIR/config.sh"

LOGDIR="$PROJECT_DIR/logs"
SESSIONS_LOG="$LOGDIR/sessions.log"
mkdir -p "$LOGDIR"

LOG_BASENAME="$(date +%Y%m%d_%H%M%S)"
LOG_PLANNER="$LOGDIR/${LOG_BASENAME}_planner.log"
LOG_ACTOR="$LOGDIR/${LOG_BASENAME}.log"
LOG_VERIFY="$LOGDIR/${LOG_BASENAME}_verify.log"

echo "$(date -u +%Y-%m-%dT%H:%M:%SZ)|started|$LOG_BASENAME" >> "$SESSIONS_LOG"

# --- Phase 0: ASI (Agent Stability Index) ---
echo "[$(date -u +%Y-%m-%dT%H:%M:%SZ)] Computing ASI metrics"
ASI_EXIT=0
ASI_METRICS=$(bash "$SCRIPT_DIR/asi.sh") || ASI_EXIT=$?
echo "[$(date -u +%Y-%m-%dT%H:%M:%SZ)] ASI computation finished (exit=$ASI_EXIT)"

METRICS_BLOCK=""
if [ "$ASI_EXIT" -eq 0 ] && [ -n "$ASI_METRICS" ]; then
  METRICS_BLOCK="
## Current Metrics (deterministic)
$ASI_METRICS"
fi

# --- Step 1: Session Planner ---
echo "[$(date -u +%Y-%m-%dT%H:%M:%SZ)] Starting Session Planner"
PLANNER_EXIT=0
timeout "${PLANNER_TIMEOUT:-30}m" codex exec \
  "$(cat "$HOME/AGENTS.md" "$SCRIPT_DIR/PLANNER_PROMPT.md")$METRICS_BLOCK" \
  --dangerously-bypass-approvals-and-sandbox \
  --cd "$PROJECT_DIR/alife" \
  --json > "$LOG_PLANNER" 2>"$LOG_PLANNER.err" || PLANNER_EXIT=$?
echo "[$(date -u +%Y-%m-%dT%H:%M:%SZ)] Session Planner finished (exit=$PLANNER_EXIT)"

if [ "$PLANNER_EXIT" -ne 0 ]; then
  echo "[$(date -u +%Y-%m-%dT%H:%M:%SZ)] Session Planner failed — skipping Actor and Verifier"
  echo "$(date -u +%Y-%m-%dT%H:%M:%SZ)|aborted|planner_exit=$PLANNER_EXIT|$LOG_BASENAME" >> "$SESSIONS_LOG"
  exit 1
fi

ACTOR_BASE_REV="$(git -C "$PROJECT_DIR/alife" rev-parse HEAD)"

# --- Step 2: Actor ---
echo "[$(date -u +%Y-%m-%dT%H:%M:%SZ)] Starting Actor"
ACTOR_EXIT=0
timeout "${TIMEOUT:-35}m" codex exec \
  "$(cat "$HOME/AGENTS.md" "$SCRIPT_DIR/ACTOR_PROMPT.md")$METRICS_BLOCK" \
  --dangerously-bypass-approvals-and-sandbox \
  --cd "$PROJECT_DIR/alife" \
  --json > "$LOG_ACTOR" 2>"$LOG_ACTOR.err" || ACTOR_EXIT=$?
echo "[$(date -u +%Y-%m-%dT%H:%M:%SZ)] Actor finished (exit=$ACTOR_EXIT)"

if [ "$ACTOR_EXIT" -ne 0 ]; then
  echo "[$(date -u +%Y-%m-%dT%H:%M:%SZ)] Actor failed — skipping Verifier"
  echo "$(date -u +%Y-%m-%dT%H:%M:%SZ)|aborted|planner_exit=$PLANNER_EXIT|actor_exit=$ACTOR_EXIT|$LOG_BASENAME" >> "$SESSIONS_LOG"
  exit 1
fi

# --- Step 3: Deterministic Verifier ---
echo "[$(date -u +%Y-%m-%dT%H:%M:%SZ)] Starting Deterministic Verifier"
VERIFY_EXIT=0
timeout "${VERIFY_TIMEOUT:-15}m" bash "$SCRIPT_DIR/verify.sh" "$PROJECT_DIR/alife" "$ACTOR_BASE_REV" \
  > "$LOG_VERIFY" 2>"$LOG_VERIFY.err" || VERIFY_EXIT=$?
echo "[$(date -u +%Y-%m-%dT%H:%M:%SZ)] Deterministic Verifier finished (exit=$VERIFY_EXIT)"

if [ "$VERIFY_EXIT" -ne 0 ]; then
  echo "$(date -u +%Y-%m-%dT%H:%M:%SZ)|aborted|planner_exit=$PLANNER_EXIT|actor_exit=$ACTOR_EXIT|verify_exit=$VERIFY_EXIT|$LOG_BASENAME" >> "$SESSIONS_LOG"
  exit 1
fi

echo "$(date -u +%Y-%m-%dT%H:%M:%SZ)|finished|planner_exit=$PLANNER_EXIT|actor_exit=$ACTOR_EXIT|verify_exit=$VERIFY_EXIT|$LOG_BASENAME" >> "$SESSIONS_LOG"

# Auto-cleanup: keep only last 30 days of logs
find "$LOGDIR" -name "*.log" -mtime +30 -delete 2>/dev/null || true
find "$LOGDIR" -name "*.log.err" -mtime +30 -delete 2>/dev/null || true
