import { describe, it, expect } from 'vitest';
import { createDefender, stepDefender, guardSpot, ankleBreakCheck, startContest } from '../src/game/defender.js';
import { RIM } from '../src/core/shooting.js';

const attrs = { perimeterDefense: 80, speed: 75, acceleration: 75 };

describe('defender', () => {
  it('guard spot sits between handler and rim', () => {
    const s = guardSpot({ x: 0, z: 25 }, RIM, 4);
    expect(s.z).toBeCloseTo(21);
  });

  it('converges to a spot between handler and rim', () => {
    const d = createDefender(attrs, 79);
    d.x = 10;
    d.z = 30;
    for (let i = 0; i < 300; i++) stepDefender(d, { x: 0, z: 25 }, RIM, 1 / 60);
    expect(Math.abs(d.x)).toBeLessThan(0.5);
    expect(d.z).toBeLessThan(25);
    expect(d.z).toBeGreaterThan(18);
  });

  it('stays put while stumbling', () => {
    const d = createDefender(attrs, 79);
    d.stumble = 1;
    const z = d.z;
    stepDefender(d, { x: 0, z: 40 }, RIM, 0.1);
    expect(d.z).toBeCloseTo(z);
    expect(d.stumble).toBeCloseTo(0.9);
  });

  it('ankle breaks need proximity and skill', () => {
    const base = { effectiveness: 0.6, ballHandle: 95, defense: 60, roll: 0.3 };
    expect(ankleBreakCheck({ ...base, distanceFt: 10 })).toBe(0);
    expect(ankleBreakCheck({ ...base, distanceFt: 3 })).toBeGreaterThan(0);
    expect(ankleBreakCheck({ ...base, ballHandle: 50, defense: 99, distanceFt: 3 })).toBe(0);
  });

  it('only contests when close and upright', () => {
    const d = createDefender(attrs, 79);
    d.x = 0;
    d.z = 20;
    expect(startContest(d, { x: 0, z: 23 })).toBe(true);
    expect(startContest({ ...d, stumble: 1 }, { x: 0, z: 23 })).toBe(false);
    expect(startContest(d, { x: 0, z: 35 })).toBe(false);
  });
});
