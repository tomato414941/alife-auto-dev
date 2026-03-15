# alife-auto-dev

Orchestrator for autonomous alife simulation development.

## Structure

- `orchestrator/` — session pipeline scripts and agent prompts
  - `run.sh` — entrypoint (lock, load secrets, call session.sh)
  - `session.sh` — Planner → Actor → Verifier pipeline
  - `config.sh` — timeout settings
  - `PLANNER_PROMPT.md` / `ACTOR_PROMPT.md` — agent prompts
  - `verify.sh` — deterministic post-session checks
- `alife/` — separate git repo (`autonomy414941/alife`). Do not modify from here.
- `docs/` — research notes and analysis
- `logs/` — per-session logs (gitignored)

## Pipeline

```
run.sh (lock, secrets, choose_engine)
  └─ session.sh
       ├─ Planner (codex or claude, random) — pick 4 bets → docs/SESSION_PLAN.md
       ├─ Actor x4 (codex or claude, random per actor)
       │    └─ Verifier (bash) — tests, build, git/doc checks
       └─ Critic (codex or claude, random) — structural ceilings → docs/BACKLOG.md
```

## Rules

- `alife/` is read-only from this repo. All simulation changes go through the Actor.
- Orchestrator changes (prompts, scripts, config) are committed to this repo.
- Logs are gitignored. Session history is in `logs/sessions.log`.
- Environment-specific config is in `AGENTS.override.md` (not committed).
