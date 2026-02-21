# Status - 2026-02-21

Current phase: first playable simulation core in `sim/`.

What exists now:
- TypeScript + Vitest project initialized with npm.
- Deterministic simulation loop (`LifeSimulation`) with seeded RNG.
- World resources regenerate on a toroidal grid.
- Agents move toward food, pay metabolic/movement costs, harvest energy.
- Multi-agent cell encounters transfer energy based on aggression.
- Reproduction creates offspring with mutated genomes.
- Death by starvation/age is enforced.
- CLI runner prints periodic population and trait summaries.
- Test suite covers determinism, reproduction/mutation, aggression encounters, starvation death.

Verification:
- `cd sim && npm run build` passes.
- `cd sim && npm test` passes (4 tests).
- `cd sim && npm start` runs 200 ticks and shows trait drift.

Next focus:
- Add explicit heritable species/clade tracking and selection metrics over time.
