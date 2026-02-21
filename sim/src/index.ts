import { LifeSimulation } from './simulation';

const STEPS = 200;
const REPORT_EVERY = 25;

const simulation = new LifeSimulation({ seed: 20260221 });

for (let i = 0; i < STEPS; i += 1) {
  const summary = simulation.step();
  if (summary.tick % REPORT_EVERY === 0 || summary.population === 0) {
    console.log(
      `tick=${summary.tick} population=${summary.population} births=${summary.births} deaths=${summary.deaths} ` +
        `meanEnergy=${summary.meanEnergy.toFixed(2)} ` +
        `traits(m=${summary.meanGenome.metabolism.toFixed(2)},h=${summary.meanGenome.harvest.toFixed(2)},a=${summary.meanGenome.aggression.toFixed(2)})`
    );
  }
  if (summary.population === 0) {
    break;
  }
}

const final = simulation.snapshot();
console.log(`final tick=${final.tick} population=${final.population} meanEnergy=${final.meanEnergy.toFixed(2)}`);
