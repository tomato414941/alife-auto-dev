import { describe, expect, it } from 'vitest';
import { LifeSimulation } from '../src/simulation';

describe('LifeSimulation', () => {
  it('is deterministic with the same seed', () => {
    const a = new LifeSimulation({ seed: 42 });
    const b = new LifeSimulation({ seed: 42 });

    a.run(40);
    b.run(40);

    expect(a.snapshot()).toEqual(b.snapshot());
  });

  it('creates mutated offspring when reproduction triggers', () => {
    const sim = new LifeSimulation({
      seed: 7,
      config: {
        width: 1,
        height: 1,
        maxResource: 0,
        resourceRegen: 0,
        metabolismCostBase: 0,
        moveCost: 0,
        harvestCap: 0,
        reproduceThreshold: 10,
        reproduceProbability: 1,
        offspringEnergyFraction: 0.5,
        mutationAmount: 0.3,
        maxAge: 100
      },
      initialAgents: [
        {
          x: 0,
          y: 0,
          energy: 30,
          genome: { metabolism: 1, harvest: 1, aggression: 0.5 }
        }
      ]
    });

    const before = sim.snapshot().agents[0].genome;
    const summary = sim.step();
    const after = sim.snapshot().agents;

    expect(summary.births).toBe(1);
    expect(after).toHaveLength(2);

    const child = after.find((agent) => agent.age === 0);
    expect(child).toBeDefined();

    const delta =
      Math.abs(child!.genome.metabolism - before.metabolism) +
      Math.abs(child!.genome.harvest - before.harvest) +
      Math.abs(child!.genome.aggression - before.aggression);

    expect(delta).toBeGreaterThan(0);
  });

  it('lets aggressive agents steal energy in shared cells', () => {
    const sim = new LifeSimulation({
      seed: 11,
      config: {
        width: 1,
        height: 1,
        maxResource: 0,
        resourceRegen: 0,
        metabolismCostBase: 0,
        moveCost: 0,
        harvestCap: 0,
        reproduceProbability: 0,
        maxAge: 100
      },
      initialAgents: [
        {
          x: 0,
          y: 0,
          energy: 10,
          genome: { metabolism: 1, harvest: 1, aggression: 1 },
          lineage: 1
        },
        {
          x: 0,
          y: 0,
          energy: 10,
          genome: { metabolism: 1, harvest: 1, aggression: 0 },
          lineage: 2
        }
      ]
    });

    sim.step();
    const agents = sim.snapshot().agents;

    const dominant = agents.find((agent) => agent.lineage === 1)!;
    const passive = agents.find((agent) => agent.lineage === 2)!;

    expect(dominant.energy).toBeGreaterThan(10);
    expect(passive.energy).toBeLessThan(10);
  });

  it('removes agents that run out of energy', () => {
    const sim = new LifeSimulation({
      seed: 3,
      config: {
        width: 1,
        height: 1,
        maxResource: 0,
        resourceRegen: 0,
        metabolismCostBase: 1,
        moveCost: 0,
        harvestCap: 0,
        reproduceProbability: 0,
        maxAge: 100
      },
      initialAgents: [
        {
          x: 0,
          y: 0,
          energy: 0.2,
          genome: { metabolism: 1, harvest: 1, aggression: 0 }
        }
      ]
    });

    const summary = sim.step();

    expect(summary.population).toBe(0);
    expect(summary.deaths).toBe(1);
  });
});
