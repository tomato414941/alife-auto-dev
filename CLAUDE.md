# CLAUDE.md

## Project
alife-auto-dev: AI-driven autonomous artificial life simulation development.
Claude Code runs daily via cron, building an alife simulation from scratch in sim/.

## Language
- Code and comments in English
- Commit messages in English

## Package Manager
npm (package-lock.json)

## Structure
- `orchestrator/` — Session scripts (DO NOT MODIFY)
- `sim/` — Simulation source code (your workspace)
- `docs/` — Project documentation (you maintain this)
- `logs/` — Session logs (gitignored)

## Testing
- Use vitest for tests
- Run `cd sim && npx vitest run` before committing
- Type check: `cd sim && npx tsc --noEmit`

## Git
- Push to main directly
- Commit format: `type: description` (feat/fix/refactor/test/docs/chore)
- Commit frequently, push at session end
- Never commit broken code

## Important
- Never modify files in orchestrator/
- Always leave the repo in a buildable, testable state
- Read docs/STATUS.md at session start
- Update docs/STATUS.md at session end
