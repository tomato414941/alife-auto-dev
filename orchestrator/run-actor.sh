#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
ALIFE_DIR="$PROJECT_DIR/alife"
source "$SCRIPT_DIR/config.sh"
source ~/.secrets/openai

echo "Running Actor..."
timeout "${ACTOR_TIMEOUT:-60}m" codex exec \
  "$(cat "$HOME/AGENTS.md" "$SCRIPT_DIR/ACTOR_PROMPT.md")" \
  --dangerously-bypass-approvals-and-sandbox \
  --cd "$ALIFE_DIR" \
  --json
echo "Actor finished."
