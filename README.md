# alife-auto-dev

Orchestrator for autonomous artificial life simulation development.

A Codex CLI-driven pipeline that autonomously develops an artificial life simulation (`autonomy414941/alife`) through daily cron sessions.

## Architecture

```
cron (daily 03:00 UTC)
  └─ orchestrator/run.sh
       ├─ Session Planner    — analyzes state + external trends, then picks one bounded bet
       ├─ Actor              — implements features, runs tests, pushes code
       └─ Deterministic Verifier — runs tests/build/session-plan/git checks
```

- **Orchestrator** (`orchestrator/`): Session management, prompts, and pipeline scripts.
- **Simulation** (`alife/`): Separate git repo ([autonomy414941/alife](https://github.com/autonomy414941/alife)). Managed by the Actor agent.
- **Logs** (`logs/`): Per-session logs for each pipeline stage (gitignored).

## Design Decisions

### Autonomous execution with full permissions

All pipeline stages run with `--dangerously-bypass-approvals-and-sandbox` and the Actor pushes directly to `main`. This is intentional:

- The project is designed to run on a **dedicated, isolated server** (not a shared or production environment).
- The simulation repository (`autonomy414941/alife`) is a standalone project with no downstream dependencies.
- The blast radius is contained: worst case is a broken commit in an isolated repo, easily reverted.

Restricting permissions would undermine the project's core premise — letting an AI agent develop freely with full agency.

### Open-ended direction

There is no fixed goal or success criteria. This is intentional. The project has two layers of purpose:

1. **Process**: Can an AI agent autonomously make meaningful development decisions over time — finding its own direction without being told what to build?
2. **Product**: Does the resulting simulation become something interesting as a consequence?

The Actor is given a broad mission ("build a living world") and decides its own direction each session. Neither layer has a predefined endpoint:

- Emergent behavior cannot be planned top-down.
- Constraining direction would narrow the space of possible discoveries.
- The planner guides direction, but does not dictate implementation details.
- The experiment is as much about the autonomous development process as it is about the simulation itself.

### Bounded autonomy over sprawling sessions

Recent agent-evals work suggests that current frontier agents are far more
reliable on bounded, verifiable slices of work than on messy, ambiguous,
long-horizon projects. This pipeline therefore separates:

- **Session planning**: understand the project and external context, then choose one bounded, high-leverage bet with clear stop conditions
- **Execution**: implement only that slice
- **Deterministic verification**: fail fast on broken builds, failing tests, missing session plan, or uncommitted tracked changes

The intent is not to reduce autonomy, but to keep each daily run inside a task
horizon the agent can realistically finish without a human in the loop.

## Setup

Runs via cron on a dedicated server. See `AGENTS.override.md` (not committed) for environment-specific configuration.

## Related

- Simulation repo: [autonomy414941/alife](https://github.com/autonomy414941/alife)
- Owner repo: [tomato414941/alife-auto-dev](https://github.com/tomato414941/alife-auto-dev)
