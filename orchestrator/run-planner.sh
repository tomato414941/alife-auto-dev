#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
ALIFE_DIR="$PROJECT_DIR/alife"
source "$SCRIPT_DIR/config.sh"
source ~/.secrets/openai

echo "Running Planner..."
timeout "${PLANNER_TIMEOUT:-45}m" codex exec \
  "$(cat "$HOME/AGENTS.md" "$SCRIPT_DIR/PLANNER_PROMPT.md")" \
  --dangerously-bypass-approvals-and-sandbox \
  --cd "$ALIFE_DIR" \
  --json
echo "Planner finished."
