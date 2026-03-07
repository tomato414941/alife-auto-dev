#!/bin/bash
# ASI (Agent Stability Index) — alife-auto-dev edition
# Computes behavioral drift metrics from session history.
# Based on: arxiv.org/abs/2601.04170 (Agent Drift, Rath 2026)
#
# 7 dimensions (mapped to paper's 4 categories):
#   Response Consistency (25%):
#     1. Git Commit Consistency  (0.15) — detects erratic output
#     2. Output Consistency      (0.10) — detects behavioral instability
#   Tool Usage Patterns (25%):
#     3. Tool Selection          (0.15) — detects tool usage drift
#     4. Tool Sequencing         (0.10) — detects workflow pattern drift
#   Execution Reliability (10%):
#     5. Session Reliability     (0.10) — detects infra issues
#   Behavioral Boundaries (25%):
#     6. Research Progression    (0.25) — detects stagnation
#
# Output: ASI metrics to stdout (for prompt injection)
# Side effect: appends to asi_history.jsonl
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
GIT_REPO="$PROJECT_DIR/alife"
LOGDIR="$PROJECT_DIR/logs"
ASI_HISTORY="$LOGDIR/asi_history.jsonl"

SESSIONS_LOG="$LOGDIR/sessions.log"

WINDOW=10       # sessions to analyze
TIMESTAMP=$(date -u +%Y-%m-%dT%H:%M:%SZ)

# --- Helper: safe tail that handles missing/empty files ---
safe_tail() {
  local file="$1" n="$2"
  if [ -f "$file" ] && [ -s "$file" ]; then
    tail -n "$n" "$file"
  fi
}

# --- Helper: list recent actor log files ---
actor_logs() {
  find "$LOGDIR" -maxdepth 1 -name '????????_??????.log' \
    -not -name '*_state_eval.log' -not -name '*_action_eval.log' \
    -not -name 'sessions.log' -not -name 'cron.log' \
    -not -name 'runner.log' -not -name 'manual.log' \
    2>/dev/null | sort | tail -n "$WINDOW"
}

# --- Helper: get finished session timestamps ---
finished_sessions() {
  safe_tail "$SESSIONS_LOG" $((WINDOW * 2)) | grep '|finished|' | tail -n "$WINDOW"
}

# --- 1. Git Commit Consistency ---
# CV of commit counts per session window.
# Stable agent makes consistent number of commits each session.
calc_git_commit_consistency() {
  if [ ! -d "$GIT_REPO/.git" ]; then
    echo "null"
    return
  fi

  local sessions
  sessions=$(finished_sessions)
  if [ -z "$sessions" ]; then
    echo "null"
    return
  fi

  # Extract session timestamps
  local timestamps=()
  while IFS='|' read -r ts status rest; do
    timestamps+=("$ts")
  done <<< "$sessions"

  local n=${#timestamps[@]}
  if [ "$n" -lt 3 ]; then
    echo "null"
    return
  fi

  # Count commits in each session window (between consecutive timestamps)
  local counts=""
  for ((i = 1; i < n; i++)); do
    local since="${timestamps[$((i-1))]}"
    local until="${timestamps[$i]}"
    local c
    c=$(git -C "$GIT_REPO" log --oneline --after="$since" --before="$until" 2>/dev/null | wc -l)
    counts="${counts}${c}"$'\n'
  done

  # Also count commits from last session to now
  local last_ts="${timestamps[$((n-1))]}"
  local c
  c=$(git -C "$GIT_REPO" log --oneline --after="$last_ts" 2>/dev/null | wc -l)
  counts="${counts}${c}"$'\n'

  echo "$counts" | awk '
  NF > 0 {
    vals[++n] = $1
    sum += $1
  }
  END {
    if (n < 3) { print "null"; exit }
    mean = sum / n
    if (mean == 0) { print "0.500"; exit }  # no commits at all = neutral
    ss = 0
    for (i = 1; i <= n; i++) ss += (vals[i] - mean) ^ 2
    sd = sqrt(ss / n)
    cv = sd / mean
    score = 1 - cv
    if (score < 0) score = 0
    if (score > 1) score = 1
    printf "%.3f\n", score
  }'
}

# --- 2. Output Consistency ---
# 1 - coefficient_of_variation(actor_log_sizes)
calc_output_consistency() {
  local log_sizes
  log_sizes=$(for f in $(actor_logs); do wc -c < "$f"; done 2>/dev/null)

  if [ -z "$log_sizes" ] || [ "$(echo "$log_sizes" | wc -l)" -lt 3 ]; then
    echo "null"
    return
  fi

  echo "$log_sizes" | awk '
  {
    vals[NR] = $1
    sum += $1
    n++
  }
  END {
    if (n < 3) { print "null"; exit }
    mean = sum / n
    if (mean == 0) { print "null"; exit }
    for (i = 1; i <= n; i++) {
      ss += (vals[i] - mean) ^ 2
    }
    sd = sqrt(ss / n)
    cv = sd / mean
    score = 1 - cv
    if (score < 0) score = 0
    if (score > 1) score = 1
    printf "%.3f\n", score
  }'
}

# --- 3. Tool Selection Stability ---
# Stability of item.type distribution across actor sessions.
calc_tool_selection_stability() {
  local logs
  logs=$(actor_logs)
  if [ -z "$logs" ] || [ "$(echo "$logs" | wc -l)" -lt 3 ]; then
    echo "null"
    return
  fi

  local session_data=""
  local sid=0
  while IFS= read -r logfile; do
    sid=$((sid + 1))
    local counts
    counts=$(jq -r 'select(.type == "item.completed") | .item.type // "unknown"' "$logfile" 2>/dev/null | sort | uniq -c | awk -v s="$sid" '{print s, $2, $1}')
    if [ -n "$counts" ]; then
      session_data="${session_data}${counts}"$'\n'
    fi
  done <<< "$logs"

  if [ -z "$session_data" ]; then
    echo "null"
    return
  fi

  echo "$session_data" | awk '
  NF == 3 {
    sessions[$1] = 1
    types[$2] = 1
    count[$1, $2] = $3
    total[$1] += $3
  }
  END {
    ns = 0; for (s in sessions) ns++
    if (ns < 3) { print "null"; exit }

    nt = 0; for (t in types) { type_list[++nt] = t }

    sum_cv = 0; n_types = 0
    for (ti = 1; ti <= nt; ti++) {
      t = type_list[ti]
      sum_p = 0; n_s = 0
      for (s in sessions) {
        p = (total[s] > 0) ? count[s, t] / total[s] : 0
        props[++n_s] = p
        sum_p += p
      }
      mean_p = sum_p / n_s
      if (mean_p < 0.01) continue

      ss = 0
      for (i = 1; i <= n_s; i++) ss += (props[i] - mean_p) ^ 2
      sd = sqrt(ss / n_s)
      cv = sd / mean_p
      sum_cv += cv
      n_types++
      delete props
    }

    if (n_types == 0) { print "null"; exit }
    avg_cv = sum_cv / n_types
    score = 1 - avg_cv
    if (score < 0) score = 0
    if (score > 1) score = 1
    printf "%.3f\n", score
  }'
}

# --- 4. Tool Sequence Consistency ---
# Stability of item.type transition patterns (bigrams) across actor sessions.
calc_tool_sequence_consistency() {
  local logs
  logs=$(actor_logs)
  if [ -z "$logs" ] || [ "$(echo "$logs" | wc -l)" -lt 3 ]; then
    echo "null"
    return
  fi

  local bigram_data=""
  local sid=0
  while IFS= read -r logfile; do
    sid=$((sid + 1))
    local bigrams
    bigrams=$(jq -r 'select(.type == "item.completed") | .item.type // "unknown"' "$logfile" 2>/dev/null \
      | awk 'NR>1 {print prev">"$0} {prev=$0}' \
      | sort | uniq -c | awk -v s="$sid" '{print s, $2, $1}')
    if [ -n "$bigrams" ]; then
      bigram_data="${bigram_data}${bigrams}"$'\n'
    fi
  done <<< "$logs"

  if [ -z "$bigram_data" ]; then
    echo "null"
    return
  fi

  echo "$bigram_data" | awk '
  NF == 3 {
    sessions[$1] = 1
    bigrams[$2] = 1
    count[$1, $2] = $3
    total[$1] += $3
  }
  END {
    ns = 0; for (s in sessions) { s_list[++ns] = s }
    if (ns < 3) { print "null"; exit }
    nb = 0; for (b in bigrams) { b_list[++nb] = b }

    for (bi = 1; bi <= nb; bi++) {
      b = b_list[bi]
      s_sum = 0
      for (si = 1; si <= ns; si++) {
        s = s_list[si]
        p = (total[s] > 0) ? count[s, b] / total[s] : 0
        s_sum += p
      }
      mean_dist[b] = s_sum / ns
    }

    sum_cos = 0
    for (si = 1; si <= ns; si++) {
      s = s_list[si]
      dot = 0; mag_s = 0; mag_m = 0
      for (bi = 1; bi <= nb; bi++) {
        b = b_list[bi]
        p_s = (total[s] > 0) ? count[s, b] / total[s] : 0
        p_m = mean_dist[b]
        dot += p_s * p_m
        mag_s += p_s * p_s
        mag_m += p_m * p_m
      }
      mag_s = sqrt(mag_s); mag_m = sqrt(mag_m)
      cosim = (mag_s > 0 && mag_m > 0) ? dot / (mag_s * mag_m) : 0
      sum_cos += cosim
    }

    score = sum_cos / ns
    if (score < 0) score = 0
    if (score > 1) score = 1
    printf "%.3f\n", score
  }'
}

# --- 5. Session Reliability ---
# finished / (finished + aborted) over last N sessions
calc_session_reliability() {
  local data
  data=$(safe_tail "$SESSIONS_LOG" $((WINDOW * 2)))
  if [ -z "$data" ]; then
    echo "null"
    return
  fi

  echo "$data" | awk -F'|' '
  {
    if ($2 == "finished") finished++
    else if ($2 == "aborted") aborted++
  }
  END {
    total = finished + aborted
    if (total == 0) { print "null"; exit }
    printf "%.3f\n", finished / total
  }'
}

# --- 6. Research Progression ---
# Ratio of feat/fix commits (recent half) vs (older half).
# Measures whether the agent continues producing meaningful research output.
calc_research_progression() {
  if [ ! -d "$GIT_REPO/.git" ]; then
    echo "null"
    return
  fi

  # Get feat/fix commit counts from recent WINDOW*2 commits
  local commits
  commits=$(git -C "$GIT_REPO" log --oneline -n $((WINDOW * 4)) 2>/dev/null)
  if [ -z "$commits" ]; then
    echo "null"
    return
  fi

  local total
  total=$(echo "$commits" | wc -l)
  if [ "$total" -lt 4 ]; then
    echo "null"
    return
  fi

  local half=$((total / 2))

  # Count feat/fix commits in older and recent halves
  local older_feat recent_feat
  older_feat=$(echo "$commits" | tail -n "$half" | grep -cE '^[0-9a-f]+ (feat|fix):' 2>/dev/null || echo "0")
  recent_feat=$(echo "$commits" | head -n "$half" | grep -cE '^[0-9a-f]+ (feat|fix):' 2>/dev/null || echo "0")

  awk -v o="$older_feat" -v r="$recent_feat" 'BEGIN {
    if (o <= 0 && r <= 0) { printf "%.3f\n", 0.5; exit }
    if (o <= 0) { printf "%.3f\n", 1.0; exit }
    ratio = r / o
    # Sigmoid normalization: ratio 0.5->0.2, 1.0->0.5, 2.0->0.8
    score = 1 / (1 + exp(-2 * (ratio - 1)))
    printf "%.3f\n", score
  }'
}

# --- Compute all dimensions ---
D_GIT_COMMIT=$(calc_git_commit_consistency)
D_CONSISTENCY=$(calc_output_consistency)
D_TOOL_SELECT=$(calc_tool_selection_stability)
D_TOOL_SEQ=$(calc_tool_sequence_consistency)
D_RELIABILITY=$(calc_session_reliability)
D_RESEARCH=$(calc_research_progression)

# --- Compute composite ASI ---
ASI=$(awk -v gc="$D_GIT_COMMIT" -v o="$D_CONSISTENCY" \
         -v ts="$D_TOOL_SELECT" -v tq="$D_TOOL_SEQ" \
         -v r="$D_RELIABILITY" \
         -v rp="$D_RESEARCH" '
BEGIN {
  dims = 0; weighted = 0; total_weight = 0
  if (gc != "null") { weighted += 0.15 * gc; total_weight += 0.15; dims++ }
  if (o != "null")  { weighted += 0.10 * o;  total_weight += 0.10; dims++ }
  if (ts != "null") { weighted += 0.15 * ts; total_weight += 0.15; dims++ }
  if (tq != "null") { weighted += 0.10 * tq; total_weight += 0.10; dims++ }
  if (r != "null")  { weighted += 0.10 * r;  total_weight += 0.10; dims++ }
  if (rp != "null") { weighted += 0.25 * rp; total_weight += 0.25; dims++ }

  if (dims == 0 || total_weight == 0) { print "null"; exit }
  printf "%.3f\n", weighted / total_weight
}')

# --- Drift alert level ---
ALERT="none"
if [ "$ASI" != "null" ]; then
  ALERT=$(awk -v a="$ASI" 'BEGIN {
    if (a < 0.4) print "critical"
    else if (a < 0.6) print "warning"
    else if (a < 0.8) print "watch"
    else print "none"
  }')
fi

# --- Output to stdout (for prompt injection) ---
cat <<EOF

agent_stability_index:
  composite: $ASI
  alert: $ALERT
  response_consistency:
    git_commit_consistency: $D_GIT_COMMIT
    output_consistency: $D_CONSISTENCY
  tool_usage_patterns:
    tool_selection_stability: $D_TOOL_SELECT
    tool_sequence_consistency: $D_TOOL_SEQ
  execution_reliability:
    session_reliability: $D_RELIABILITY
  behavioral_boundaries:
    research_progression: $D_RESEARCH
  window: $WINDOW sessions
EOF

# --- Append to history ---
NULL_SAFE() { if [ "$1" = "null" ]; then echo "null"; else echo "$1"; fi; }
cat >> "$ASI_HISTORY" <<HIST
{"timestamp":"$TIMESTAMP","asi":$(NULL_SAFE "$ASI"),"alert":"$ALERT","git_commit_consistency":$(NULL_SAFE "$D_GIT_COMMIT"),"output_consistency":$(NULL_SAFE "$D_CONSISTENCY"),"tool_selection_stability":$(NULL_SAFE "$D_TOOL_SELECT"),"tool_sequence_consistency":$(NULL_SAFE "$D_TOOL_SEQ"),"session_reliability":$(NULL_SAFE "$D_RELIABILITY"),"research_progression":$(NULL_SAFE "$D_RESEARCH"),"window":$WINDOW}
HIST
