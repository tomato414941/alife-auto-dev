# alife-auto-dev

Orchestrator for autonomous artificial life simulation development.

A Codex CLI-driven pipeline that autonomously develops an artificial life simulation (`autonomy414941/alife`) through daily cron sessions.

## Architecture

```
cron (daily 03:00 UTC)
  └─ orchestrator/run.sh
       ├─ State Evaluator   — analyzes project state + external trends
       ├─ Actor              — implements features, runs tests, pushes code
       └─ Action Evaluator   — reviews session output and provides feedback
```

- **Orchestrator** (`orchestrator/`): Session management, prompts, and pipeline scripts.
- **Simulation** (`alife/`): Separate git repo ([autonomy414941/alife](https://github.com/autonomy414941/alife)). Managed by the Actor agent.
- **Logs** (`logs/`): Per-session logs for each pipeline stage (gitignored).

## Design Decisions

### Autonomous execution with full permissions

All pipeline stages run with `--dangerously-bypass-approvals-and-sandbox` and the Actor pushes directly to `main`. This is intentional:

- The project runs on a **dedicated autonomous server** (not a shared or production environment).
- It operates under the **autonomy414941 account**, isolated from personal infrastructure.
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
- The Evaluators provide feedback but do not gate or veto development.
- The experiment is as much about the autonomous development process as it is about the simulation itself.

## Setup

Runs on the autonomous server via cron:

```bash
# Daily session at 03:00 UTC
0 3 * * * /home/dev/projects/alife-auto-dev/orchestrator/run.sh >> /home/dev/projects/alife-auto-dev/logs/cron.log 2>&1
```

## Related

- Simulation repo: [autonomy414941/alife](https://github.com/autonomy414941/alife)
- Owner repo: [tomato414941/alife-auto-dev](https://github.com/tomato414941/alife-auto-dev)
