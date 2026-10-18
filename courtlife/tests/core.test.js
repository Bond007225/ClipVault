import { describe, it, expect } from 'vitest';
import { createDefaultPlayer, normalizePlayer } from '../src/core/player.js';
import { attributeCaps, legalizeAttributes, pointsUsed, ATTRIBUTE_BUDGET, setAttribute, overallRating } from '../src/core/attributes.js';
import { computeShotProfile, sampleShotPose, SHOT_BASES, SHOT_RELEASES } from '../src/core/jumpshot.js';
import { buildComboTimeline, sampleCombo, validateCombo, normalizeCombos, maxStepSpeed, DRIBBLE_MOVES } from '../src/core/dribble.js';
import { gradeRelease, makeProbability, isThree, contestLevel } from '../src/core/shooting.js';
import { exportBuildCode, importBuildCode, savePlayer, loadPlayers, deletePlayer } from '../src/core/storage.js';
import { reachArm, rigDimensions } from '../src/core/locomotion.js';

const memoryStore = () => {
  const m = new Map();
  return { getItem: (k) => m.get(k) ?? null, setItem: (k, v) => m.set(k, String(v)) };
};

describe('player', () => {
  it('default player is legal and stable under normalization', () => {
    const p = createDefaultPlayer();
    expect(normalizePlayer(p)).toEqual(p);
    expect(pointsUsed(p.attributes)).toBeLessThanOrEqual(ATTRIBUTE_BUDGET);
  });

  it('sanitizes garbage input', () => {
    const p = normalizePlayer({
      name: '   ', body: { heightIn: 200, skinTone: 'red' }, face: { hairStyle: 'nope' },
      tattoos: [{ slot: 'leftForearm', design: 'rose' }, { slot: 'moon', design: 'rose' }, { slot: 'neck', design: 'script', text: 'x'.repeat(50) }],
      combos: [{ name: 'a', key: 'Z', steps: [{ move: 'teleport' }] }],
    });
    expect(p.name).toBe('Rookie');
    expect(p.body.heightIn).toBe(87);
    expect(p.body.skinTone).toMatch(/^#/);
    expect(p.face.hairStyle).toBe('fade');
    expect(p.tattoos).toHaveLength(2);
    expect(p.tattoos[1].text.length).toBeLessThanOrEqual(16);
    expect(p.combos).toEqual([]);
  });

  it('caps tattoos per slot', () => {
    const t = Array.from({ length: 5 }, () => ({ slot: 'neck', design: 'stars' }));
    expect(normalizePlayer({ tattoos: t }).tattoos).toHaveLength(3);
  });
});

describe('attributes', () => {
  it('tall players get lower handle caps and higher block caps', () => {
    const guard = attributeCaps({ heightIn: 72, weightLb: 175, wingspanIn: 74 });
    const big = attributeCaps({ heightIn: 85, weightLb: 260, wingspanIn: 90 });
    expect(guard.ballHandle).toBeGreaterThan(big.ballHandle);
    expect(big.block).toBeGreaterThan(guard.block);
  });

  it('legalize respects caps and budget', () => {
    const body = { heightIn: 84, weightLb: 250, wingspanIn: 88 };
    const maxed = Object.fromEntries(Object.keys(attributeCaps(body)).map((k) => [k, 99]));
    const out = legalizeAttributes(maxed, body);
    const caps = attributeCaps(body);
    for (const k of Object.keys(out)) expect(out[k]).toBeLessThanOrEqual(caps[k]);
    expect(pointsUsed(out)).toBeLessThanOrEqual(ATTRIBUTE_BUDGET);
  });

  it('setAttribute cannot exceed remaining budget', () => {
    const p = createDefaultPlayer();
    const v = setAttribute(p.attributes, p.body, 'threePoint', 99);
    expect(pointsUsed({ ...p.attributes, threePoint: v })).toBeLessThanOrEqual(ATTRIBUTE_BUDGET);
  });

  it('overall is within rating range', () => {
    const p = createDefaultPlayer();
    const ovr = overallRating(p.attributes, p.position);
    expect(ovr).toBeGreaterThanOrEqual(25);
    expect(ovr).toBeLessThanOrEqual(99);
  });
});

describe('jumpshot', () => {
  it('faster speed releases sooner', () => {
    const slow = computeShotProfile({ speed: 1 });
    const fast = computeShotProfile({ speed: 5 });
    expect(fast.releaseTimeMs).toBeLessThan(slow.releaseTimeMs);
  });

  it('better shooters get a bigger green window', () => {
    const a = computeShotProfile({}, { threePoint: 60 });
    const b = computeShotProfile({}, { threePoint: 95 });
    expect(b.greenWindowMs).toBeGreaterThan(a.greenWindowMs);
  });

  it('clashing release tempos hurt rhythm at a 50/50 blend', () => {
    const pure = computeShotProfile({ release1: 'quickFlick', release2: 'highArc', blend: 0 });
    const mixed = computeShotProfile({ release1: 'quickFlick', release2: 'highArc', blend: 50 });
    expect(mixed.greenWindowMs).toBeLessThan(pure.greenWindowMs);
  });

  it('every base/release combo produces finite poses', () => {
    for (const base of Object.keys(SHOT_BASES)) {
      for (const release1 of Object.keys(SHOT_RELEASES)) {
        const prof = computeShotProfile({ base, release1, release2: 'push', blend: 40 });
        for (let t = 0; t <= 1; t += 0.05) {
          const pose = sampleShotPose(prof, t);
          for (const e of Object.values(pose.joints)) e.forEach((v) => expect(Number.isFinite(v)).toBe(true));
          expect(Number.isFinite(pose.rootY)).toBe(true);
        }
      }
    }
  });
});

describe('dribble', () => {
  const combo = { name: 'x', key: '1', steps: [{ move: 'crossover', speed: 1 }, { move: 'snatchBack', speed: 1.5 }] };

  it('locks moves and caps speed by ball handle', () => {
    const v = validateCombo(combo, 60);
    expect(v.ok).toBe(false);
    expect(v.errors.length).toBe(2);
    expect(validateCombo(combo, 99).ok).toBe(true);
    expect(maxStepSpeed(99)).toBeCloseTo(1.5);
  });

  it('timeline drops locked moves and tracks hand switches', () => {
    const tl = buildComboTimeline(combo, 60);
    expect(tl.segments).toHaveLength(1);
    expect(tl.endHand).toBe('L');
    const full = buildComboTimeline(combo, 99);
    expect(full.segments).toHaveLength(2);
    expect(full.totalMs).toBeCloseTo(380 + 440 / 1.5);
  });

  it('right-hand crossover moves the player to their left (+X)', () => {
    const tl = buildComboTimeline({ steps: [{ move: 'crossover', speed: 1 }] }, 80, 'R');
    expect(tl.offset.x).toBeGreaterThan(0);
    const start = sampleCombo(tl, 0);
    const end = sampleCombo(tl, tl.totalMs);
    expect(start.ball.x).toBeLessThan(0);
    expect(end.ball.x).toBeGreaterThan(0);
    expect(end.done).toBe(true);
  });

  it('normalizes duplicate key bindings', () => {
    const out = normalizeCombos([
      { name: 'a', key: '1', steps: [{ move: 'spin' }] },
      { name: 'b', key: '1', steps: [{ move: 'spin' }] },
    ]);
    expect(out[0].key).not.toBe(out[1].key);
  });

  it('all moves have ball keyframes spanning 0..1', () => {
    for (const m of Object.values(DRIBBLE_MOVES)) {
      expect(m.ball[0].t).toBe(0);
      expect(m.ball[m.ball.length - 1].t).toBe(1);
    }
  });
});

describe('shooting', () => {
  const prof = computeShotProfile({}, { threePoint: 85 });
  it('grades timing', () => {
    expect(gradeRelease(prof, prof.releaseTimeMs).grade).toBe('green');
    expect(gradeRelease(prof, prof.releaseTimeMs - 400).grade).toBe('early');
    expect(gradeRelease(prof, prof.releaseTimeMs + 400).grade).toBe('late');
  });
  it('greens beat bad releases', () => {
    const g = makeProbability({ grade: 'green', rating: 70, distanceFt: 24, contest: 0.2 });
    const l = makeProbability({ grade: 'late', rating: 99, distanceFt: 24, contest: 0 });
    expect(g).toBeGreaterThan(0.9);
    expect(l).toBeLessThan(0.15);
  });
  it('three point line', () => {
    expect(isThree(0, 25)).toBe(true);
    expect(isThree(0, 15)).toBe(false);
    expect(isThree(22.5, 0)).toBe(true);
  });
  it('contest drops off with distance', () => {
    expect(contestLevel(2, 80, 0)).toBeGreaterThan(contestLevel(6, 80, 0));
    expect(contestLevel(null, 80, 0)).toBe(0);
  });
});

describe('storage', () => {
  it('round-trips build codes with a fresh id', () => {
    const p = createDefaultPlayer();
    p.name = 'Ünïcode Hooper';
    const back = importBuildCode(exportBuildCode(p));
    expect(back.name).toBe(p.name);
    expect(back.id).not.toBe(p.id);
    expect(back.jumpshot).toEqual(p.jumpshot);
  });
  it('rejects bad codes', () => {
    expect(() => importBuildCode('hello')).toThrow();
    expect(() => importBuildCode('CL1.@@@')).toThrow();
  });
  it('saves, updates and deletes', () => {
    const store = memoryStore();
    const p = savePlayer(createDefaultPlayer(), store);
    savePlayer({ ...p, name: 'Updated' }, store);
    expect(loadPlayers(store)).toHaveLength(1);
    expect(loadPlayers(store)[0].name).toBe('Updated');
    deletePlayer(p.id, store);
    expect(loadPlayers(store)).toHaveLength(0);
  });
});

describe('locomotion', () => {
  it('reachArm returns finite angles and straightens for far targets', () => {
    const dims = rigDimensions(createDefaultPlayer().body);
    const near = reachArm(dims, 'R', { x: -0.5, y: 1, z: 0.5 });
    const far = reachArm(dims, 'R', { x: -0.5, y: -3, z: 0.5 });
    expect(Math.abs(far.elbow[0])).toBeLessThan(Math.abs(near.elbow[0]));
    [...near.shoulder, ...near.elbow].forEach((v) => expect(Number.isFinite(v)).toBe(true));
  });
});
