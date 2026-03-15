#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
ALIFE_DIR="$PROJECT_DIR/alife"
source "$SCRIPT_DIR/config.sh"

LOGDIR="$PROJECT_DIR/logs"
SESSIONS_LOG="$LOGDIR/sessions.log"
mkdir -p "$LOGDIR"

LOG_BASENAME="$(date +%Y%m%d_%H%M%S)"
LOG_PLANNER="$LOGDIR/${LOG_BASENAME}_planner.log"

# Choose engine for this session
ENGINE=$(choose_engine)

echo "$(date -u +%Y-%m-%dT%H:%M:%SZ)|started|engine=${ENGINE}|$LOG_BASENAME" >> "$SESSIONS_LOG"

# Helper: run prompt through chosen engine
run_agent() {
  local prompt="$1"
  local workdir="$2"
  local log_out="$3"
  local log_err="$4"
  local timeout_min="$5"

  if [ "$ENGINE" = "claude" ]; then
    (cd "$workdir" && timeout "${timeout_min}m" claude -p \
      --model sonnet \
      --dangerously-skip-permissions \
      --append-system-prompt "$prompt" \
      "Execute the task described in your system prompt." \
      > "$log_out" 2>"$log_err")
  else
    timeout "${timeout_min}m" codex exec \
      "$prompt" \
      --dangerously-bypass-approvals-and-sandbox \
      --cd "$workdir" \
      --json > "$log_out" 2>"$log_err"
  fi
}

# --- Step 1: Session Planner ---
echo "[$(date -u +%Y-%m-%dT%H:%M:%SZ)] Starting Session Planner (engine=$ENGINE)"
PLANNER_EXIT=0
run_agent "$(cat "$HOME/AGENTS.md" "$SCRIPT_DIR/PLANNER_PROMPT.md")" "$ALIFE_DIR" "$LOG_PLANNER" "$LOG_PLANNER.err" "${PLANNER_TIMEOUT:-45}" || PLANNER_EXIT=$?
echo "[$(date -u +%Y-%m-%dT%H:%M:%SZ)] Session Planner finished (exit=$PLANNER_EXIT)"

if [ "$PLANNER_EXIT" -ne 0 ]; then
  echo "[$(date -u +%Y-%m-%dT%H:%M:%SZ)] Session Planner failed — aborting"
  echo "$(date -u +%Y-%m-%dT%H:%M:%SZ)|aborted|planner_exit=$PLANNER_EXIT|$LOG_BASENAME" >> "$SESSIONS_LOG"
  exit 1
fi

# --- Step 2: Parse bet count from SESSION_PLAN.md ---
SESSION_PLAN="$ALIFE_DIR/docs/SESSION_PLAN.md"
BET_COUNT=$(grep -c '^### Bet [0-9]' "$SESSION_PLAN" 2>/dev/null || echo 0)

# Fallback: if planner used old format (Selected Bet), run as single actor
if [ "$BET_COUNT" -eq 0 ]; then
  echo "[$(date -u +%Y-%m-%dT%H:%M:%SZ)] No Bet Queue found — running single actor (legacy mode)"
  BET_COUNT=1
  LEGACY_MODE=1
else
  LEGACY_MODE=0
fi

MAX="${MAX_ACTORS:-3}"
[ "$BET_COUNT" -gt "$MAX" ] && BET_COUNT="$MAX"

# --- Step 3: Sequential Actor loop ---
ACTORS_SUCCEEDED=0
ACTORS_FAILED=0
ACTOR_RESULTS=""

for i in $(seq 1 "$BET_COUNT"); do
  LOG_ACTOR="$LOGDIR/${LOG_BASENAME}_actor${i}.log"
  LOG_VERIFY="$LOGDIR/${LOG_BASENAME}_verify${i}.log"

  # Extract bet into SESSION_BET.md (skip in legacy mode)
  if [ "$LEGACY_MODE" -eq 0 ]; then
    echo "[$(date -u +%Y-%m-%dT%H:%M:%SZ)] Extracting Bet $i/$BET_COUNT"
    if [ "$i" -eq "$BET_COUNT" ]; then
      sed -n "/^### Bet $i/,\$p" "$SESSION_PLAN" > "$ALIFE_DIR/docs/SESSION_BET.md"
    else
      NEXT=$((i + 1))
      sed -n "/^### Bet $i/,/^### Bet $NEXT/{/^### Bet $NEXT/!p}" "$SESSION_PLAN" > "$ALIFE_DIR/docs/SESSION_BET.md"
    fi

    # Skip empty bets
    if [ ! -s "$ALIFE_DIR/docs/SESSION_BET.md" ]; then
      echo "[$(date -u +%Y-%m-%dT%H:%M:%SZ)] Bet $i is empty — skipping"
      ACTOR_RESULTS="${ACTOR_RESULTS}|bet${i}=empty"
      continue
    fi
  fi

  ACTOR_BASE_REV="$(git -C "$ALIFE_DIR" rev-parse HEAD)"

  # Run Actor
  echo "[$(date -u +%Y-%m-%dT%H:%M:%SZ)] Starting Actor $i/$BET_COUNT"
  ACTOR_EXIT=0
  run_agent "$(cat "$HOME/AGENTS.md" "$SCRIPT_DIR/ACTOR_PROMPT.md")" "$ALIFE_DIR" "$LOG_ACTOR" "$LOG_ACTOR.err" "${ACTOR_TIMEOUT:-45}" || ACTOR_EXIT=$?
  echo "[$(date -u +%Y-%m-%dT%H:%M:%SZ)] Actor $i finished (exit=$ACTOR_EXIT)"

  if [ "$ACTOR_EXIT" -ne 0 ]; then
    echo "[$(date -u +%Y-%m-%dT%H:%M:%SZ)] Actor $i failed — reverting"
    git -C "$ALIFE_DIR" reset --hard "$ACTOR_BASE_REV"
    ACTORS_FAILED=$((ACTORS_FAILED + 1))
    ACTOR_RESULTS="${ACTOR_RESULTS}|bet${i}=actor_fail(${ACTOR_EXIT})"
    continue
  fi

  # Run Verifier (skip upstream check — push is deferred)
  echo "[$(date -u +%Y-%m-%dT%H:%M:%SZ)] Starting Verifier for Actor $i"
  VERIFY_EXIT=0
  SKIP_UPSTREAM_CHECK=1 timeout "${VERIFY_TIMEOUT:-15}m" \
    bash "$SCRIPT_DIR/verify.sh" "$ALIFE_DIR" "$ACTOR_BASE_REV" \
    > "$LOG_VERIFY" 2>"$LOG_VERIFY.err" || VERIFY_EXIT=$?
  echo "[$(date -u +%Y-%m-%dT%H:%M:%SZ)] Verifier $i finished (exit=$VERIFY_EXIT)"

  if [ "$VERIFY_EXIT" -ne 0 ]; then
    echo "[$(date -u +%Y-%m-%dT%H:%M:%SZ)] Verifier $i failed — reverting"
    git -C "$ALIFE_DIR" reset --hard "$ACTOR_BASE_REV"
    ACTORS_FAILED=$((ACTORS_FAILED + 1))
    ACTOR_RESULTS="${ACTOR_RESULTS}|bet${i}=verify_fail(${VERIFY_EXIT})"
    continue
  fi

  # Push
  echo "[$(date -u +%Y-%m-%dT%H:%M:%SZ)] Pushing Actor $i changes"
  if git -C "$ALIFE_DIR" push; then
    ACTORS_SUCCEEDED=$((ACTORS_SUCCEEDED + 1))
    ACTOR_RESULTS="${ACTOR_RESULTS}|bet${i}=ok"
  else
    echo "[$(date -u +%Y-%m-%dT%H:%M:%SZ)] Push failed for Actor $i — reverting"
    git -C "$ALIFE_DIR" reset --hard "$ACTOR_BASE_REV"
    ACTORS_FAILED=$((ACTORS_FAILED + 1))
    ACTOR_RESULTS="${ACTOR_RESULTS}|bet${i}=push_fail"
  fi
done

# Cleanup
rm -f "$ALIFE_DIR/docs/SESSION_BET.md"

# --- Step 4 (optional): Critic ---
if true; then
  LOG_CRITIC="$LOGDIR/${LOG_BASENAME}_critic.log"
  echo "[$(date -u +%Y-%m-%dT%H:%M:%SZ)] Starting Critic"
  CRITIC_EXIT=0
  run_agent "$(cat "$HOME/AGENTS.md" "$SCRIPT_DIR/CRITIC_PROMPT.md")" "$ALIFE_DIR" "$LOG_CRITIC" "$LOG_CRITIC.err" "${CRITIC_TIMEOUT:-30}" || CRITIC_EXIT=$?
  echo "[$(date -u +%Y-%m-%dT%H:%M:%SZ)] Critic finished (exit=$CRITIC_EXIT)"
  if [ "$CRITIC_EXIT" -eq 0 ]; then
    if git -C "$ALIFE_DIR" diff --quiet docs/BACKLOG.md 2>/dev/null; then
      echo "[$(date -u +%Y-%m-%dT%H:%M:%SZ)] Critic made no BACKLOG changes"
    else
      git -C "$ALIFE_DIR" add docs/BACKLOG.md
      git -C "$ALIFE_DIR" commit -m "critic: add structural ceiling findings to backlog"
      git -C "$ALIFE_DIR" push || echo "[$(date -u +%Y-%m-%dT%H:%M:%SZ)] Critic push failed (non-fatal)"
    fi
  fi
fi

# Log summary
STATUS="finished"
[ "$ACTORS_SUCCEEDED" -eq 0 ] && STATUS="all_failed"
echo "$(date -u +%Y-%m-%dT%H:%M:%SZ)|${STATUS}|planner_exit=$PLANNER_EXIT|succeeded=${ACTORS_SUCCEEDED}|failed=${ACTORS_FAILED}${ACTOR_RESULTS}|$LOG_BASENAME" >> "$SESSIONS_LOG"

# Auto-cleanup: keep only last 30 days of logs
find "$LOGDIR" -name "*.log" -mtime +30 -delete 2>/dev/null || true
find "$LOGDIR" -name "*.log.err" -mtime +30 -delete 2>/dev/null || true

# Exit non-zero only if ALL actors failed
[ "$ACTORS_SUCCEEDED" -gt 0 ] || exit 1
