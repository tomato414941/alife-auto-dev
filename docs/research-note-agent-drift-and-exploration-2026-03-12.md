# Research Note: Agent Drift, Exploration Strategies, and Simulation Analysis

Date: 2026-03-12

## Background

The alife-auto-dev orchestrator runs a Planner → Actor → Verify pipeline daily
via Codex CLI on the autonomous server. After ~3 weeks (84 commits), the system
exhibited classic **agent drift**: all recent commits stayed on a single axis
(lineage-aware spatial ecology) with diminishing returns.

## Problem: Autonomous Agent Drift

Long-running AI agents converge on narrow, easy tasks. This is a known problem
in the literature:

- **Agent Drift**: successful patterns reinforce themselves; the agent avoids
  risk and repeats the same axis of work.
- **Mode Collapse**: even with candidate generation (3 options), candidates
  cluster around recent success.
- **Context Trap**: SESSION_PLAN.md carries forward recent context, biasing
  the next session toward the same direction.

### Key References

- [Cursor: Scaling Long-Running Autonomous Coding](https://cursor.com/blog/scaling-agents)
  — periodic fresh starts to combat drift; hierarchical planner-worker architecture
- [AI Scientist-v2](https://arxiv.org/abs/2504.08066)
  — best-first tree search for research exploration
- [UltraHorizon](https://openreview.net/forum?id=FTZfVHWAIq)
  — agents underperform humans in ultra long-horizon settings
- [Karpathy's autoresearch](https://github.com/karpathy/autoresearch)
  — linear search with fast feedback (5min experiments), keep/discard binary decisions

### Karpathy's autoresearch vs alife-auto-dev

| Aspect              | autoresearch              | alife-auto-dev            |
|---------------------|---------------------------|---------------------------|
| Feedback speed      | 5 min per experiment      | 20-50 min per session     |
| Evaluation          | Single metric (val_bpb)   | Single metric (actDelta)  |
| Exploration         | "think harder" (implicit) | Axis tracking (explicit)  |
| Failure cost        | git reset (instant)       | Dead code remains         |
| Scope               | 1 file (train.py)         | Full codebase             |

## Interventions Applied (2026-03-12)

### 1. Exploration Axis Tracking (Planner prompt)

Added axis classification of recent commits with forced diversification:
- 3/5 same axis → at least one candidate on different axis
- 5/5 same axis → selected bet MUST be different axis

**Result**: Immediately effective. First session after change moved from
lineage crowding to encounter-risk aversion.

### 2. Session Type Diversity (Planner + Actor prompts)

Expanded session types from implicit feat-only to 13 explicit types:

| Type        | Description                                          |
|-------------|------------------------------------------------------|
| feat        | New mechanism or interaction                         |
| refactor    | Consolidate duplicates, split files                  |
| validate    | Long-horizon benchmarks, reproduction                |
| review      | Analyze past results for patterns                    |
| cleanup     | Remove dead code, unused artifacts                   |
| test        | Improve coverage, find edge cases                    |
| revert      | Remove failed experiment code                        |
| investigate | Diagnose WHY experiments fail                        |
| split       | Break apart God Objects (>2000 lines)                |
| benchmark   | Profile performance, optimize hot paths              |
| visualize   | Lightweight spatial pattern output                   |
| synthesize  | Test combinations of existing knobs                  |
| strategize  | Question evaluation metrics and research direction   |

### 3. Trigger Rules

| Trigger              | Condition                                    | Required action          |
|----------------------|----------------------------------------------|--------------------------|
| Validation           | 5+ feat sessions since last validate         | validate candidate       |
| Investigation        | 3+ consecutive feat experiments worsened      | investigate/strategize   |
| Revert               | 5+ dead knobs (default 0/-1, no positive)    | revert candidate         |
| Code health          | File >2000 lines, 5+ duplicate files, etc.   | refactor/split/cleanup   |

## Experiment Results (2026-03-12, 8 sessions)

### Short-horizon smoke tests (1000 steps)

| Session | Type     | Axis                     | actDelta (on) | vs baseline |
|---------|----------|--------------------------|---------------|-------------|
| 1       | feat     | offspring ecology settle  | +29.3         | BEST        |
| 2       | feat     | encounter-risk aversion  | -60.8         | fail        |
| 3       | feat     | decomposition spillover  | +14.9         | worse       |
| 5       | feat     | ecology-gated cladogene  | +5.3          | worse       |
| 6       | feat     | trophic opportunity      | -17.2         | fail        |
| 7       | feat     | trait novelty gate       | +1.5          | worse       |

Baseline (all knobs off): +29.3

### Long-horizon validation (4000 steps, session 4)

| Threshold | Survival | Baseline (3/10) | Current | Improvement |
|-----------|----------|-----------------|---------|-------------|
| 1.0       | 50       | -317.6          | -34.6   | +283 (89%)  |
| 1.0       | 100      | -737.1          | -111.8  | +625 (85%)  |
| 1.2       | 50       | -247.3          | -18.2   | +229 (93%)  |
| 1.2       | 100      | -584.6          | -93.6   | +491 (84%)  |

Still negative (below null) but massive improvement from prior baseline.

### Refactor session (session 8)

Extracted shared smoke-study harness: +595 lines, -1,437 lines = **-842 net**.

### Session type distribution

| Type     | Count | Notes                              |
|----------|-------|------------------------------------|
| feat     | 6     | 5 new axes, all failed vs baseline |
| validate | 1     | First self-initiated validation    |
| refactor | 1     | First self-initiated refactor      |

## Simulation Code Analysis

### Critical Issues

1. **Genome is only 3-dimensional** (metabolism, harvest, aggression).
   This is likely the root bottleneck for open-ended evolution. No matter how
   many config knobs are added, agents can only evolve along 3 trait axes.
   The strategy space has a hard ceiling.

2. **Memory leak in localityFrames**: every step's LocalityFrame is kept
   forever. At 4000 steps × 400 cells, this is significant.

3. **resolveEncounters is O(n²)** per cell in worst case. Should be
   restructured to process cell-by-cell.

4. **Speciation is purely genetic distance**. No spatial isolation or
   ecological divergence mechanism. With 3D genome and distance threshold,
   species diversity has a structural upper bound.

5. **5 dead knobs accumulated** from failed experiments:
   encounterRiskAversion, trophicOpportunityAttraction,
   decompositionSpilloverFraction, cladogenesisEcologyAdvantageThreshold,
   cladogenesisTraitNoveltyThreshold

6. **Predation is symmetric aggression**, not true trophic dynamics.
   "Trophic level" is derived from genome but encounters are just
   energy theft, not predator-prey relationships.

7. **Single evaluation metric** (persistentActivityMeanDeltaVsNullMean).
   persistentWindowFractionDelta is always 0. No phylogenetic tree shape
   metrics, no niche overlap measures, no novelty detection.

### Architectural Debt

- simulation.ts: 2,745 lines (God Object)
- activity.ts: 2,550 lines
- types.ts: 1,137 lines (flat type dump)
- 15 study entrypoint files in src/

## Unimplemented Improvement Paths

### Pipeline Architecture

| Priority | Change                          | Effort |
|----------|---------------------------------|--------|
| 1        | Experiment log (results.tsv)    | Small  |
| 2        | Tree search with backtracking   | Large  |
| 3        | Weekly meta-planner             | Medium |
| 4        | Fast feedback loop (5min cycle) | Medium |

### Simulation Design

| Priority | Change                              | Rationale                          |
|----------|-------------------------------------|------------------------------------|
| 1        | Expand genome dimensionality        | 3D genome caps evolvable strategy  |
| 2        | Add spatial/ecological speciation   | Distance-only is too simple        |
| 3        | Implement true predator-prey        | Current encounters are symmetric   |
| 4        | Add alternative OEE metrics         | Single metric blinds exploration   |
| 5        | Fix localityFrames memory leak      | Enables longer simulations         |

## Conclusions

1. **Prompt-level interventions work** for axis diversification and session
   type variety, but they cannot fix fundamental simulation design limits.

2. **The 3-dimensional genome is the most likely structural bottleneck**.
   Config knobs control the environment; the genome controls what agents can
   evolve. With only 3 evolvable traits, the system cannot exhibit the kind
   of ongoing innovation that OEE requires.

3. **The evaluation methodology needs diversification**. A single
   relabel-null activity delta cannot capture all aspects of open-endedness.

4. **Dead code from failed experiments should be reverted** before adding
   more mechanisms. The revert trigger should ensure this happens.
