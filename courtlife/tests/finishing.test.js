import { describe, it, expect } from 'vitest';
import {
  chooseFinish, finishProfile, finishMakeProbability, finishRating, dunkReachIn, isBlocked, sampleFinishPose,
  FINISH_MAX_RANGE_FT, RIM_HEIGHT_IN, DUNK_CLEARANCE_IN,
} from '../src/core/finishing.js';
import { computeShotProfile, sampleShotPose } from '../src/core/jumpshot.js';
import { contestLevel } from '../src/core/shooting.js';

const slasher = { closeShot: 75, drivingLayup: 80, drivingDunk: 85, vertical: 85 };
const finesse = { closeShot: 80, drivingLayup: 90, drivingDunk: 40, vertical: 60 };

describe('chooseFinish', () => {
  it('takes a jumper beyond finishing range', () => {
    expect(chooseFinish({ distanceFt: FINISH_MAX_RANGE_FT + 0.5, speedFtPerSec: 14, attrs: slasher, heightIn: 80 })).toBeNull();
    expect(chooseFinish({ distanceFt: 20, speedFtPerSec: 0, attrs: slasher, heightIn: 80 })).toBeNull();
  });

  it('athletic slashers dunk close to the rim', () => {
    expect(chooseFinish({ distanceFt: 3, speedFtPerSec: 12, attrs: slasher, heightIn: 80 })).toBe('dunk');
  });

  it('players without a dunk rating lay it up', () => {
    expect(chooseFinish({ distanceFt: 3, speedFtPerSec: 12, attrs: finesse, heightIn: 80 })).toBe('layup');
  });

  it('short players who cannot reach the rim lay it up', () => {
    const attrs = { ...slasher, vertical: 30 };
    expect(dunkReachIn(70, 30, 12)).toBeLessThan(RIM_HEIGHT_IN + DUNK_CLEARANCE_IN);
    expect(chooseFinish({ distanceFt: 3, speedFtPerSec: 12, attrs, heightIn: 70 })).toBe('layup');
  });

  it('dunks need closer range than layups', () => {
    expect(chooseFinish({ distanceFt: 8.5, speedFtPerSec: 12, attrs: slasher, heightIn: 80 })).toBe('layup');
  });

  it('speed favors dunks for balanced finishers', () => {
    const attrs = { closeShot: 70, drivingLayup: 75, drivingDunk: 65, vertical: 75 };
    expect(chooseFinish({ distanceFt: 3, speedFtPerSec: 0, attrs, heightIn: 78 })).toBe('layup');
    expect(chooseFinish({ distanceFt: 3, speedFtPerSec: 14, attrs, heightIn: 78 })).toBe('dunk');
  });

  it('standing still shrinks layup range', () => {
    expect(chooseFinish({ distanceFt: 7.5, speedFtPerSec: 0, attrs: finesse, heightIn: 78 })).toBeNull();
    expect(chooseFinish({ distanceFt: 7.5, speedFtPerSec: 10, attrs: finesse, heightIn: 78 })).toBe('layup');
  });
});

describe('finishProfile', () => {
  it('has gather before release and release before the end', () => {
    for (const type of ['layup', 'dunk']) {
      const p = finishProfile(type, { rating: 80, vertical: 75, heightIn: 78, distanceFt: 4 });
      expect(p.type).toBe(type);
      expect(p.gatherMs).toBeGreaterThan(0);
      expect(p.releaseTimeMs).toBeGreaterThan(p.gatherMs);
      expect(p.releaseTimeMs).toBeLessThan(p.durationMs);
      expect(p.releaseT).toBeCloseTo(p.releaseTimeMs / p.durationMs, 10);
      expect(p.greenWindowMs).toBeGreaterThanOrEqual(20);
      expect(p.contestResist).toBeGreaterThanOrEqual(0);
      expect(p.contestResist).toBeLessThanOrEqual(1);
    }
  });

  it('further takeoffs take longer to gather', () => {
    expect(finishProfile('layup', { distanceFt: 8 }).gatherMs).toBeGreaterThan(finishProfile('layup', { distanceFt: 2 }).gatherMs);
  });

  it('dunks are harder to contest than layups', () => {
    const ctx = { rating: 80, vertical: 80, heightIn: 80, distanceFt: 3 };
    expect(finishProfile('dunk', ctx).contestResist).toBeGreaterThan(finishProfile('layup', ctx).contestResist);
  });

  it('better ratings widen the (future) timing window', () => {
    expect(finishProfile('layup', { rating: 95 }).greenWindowMs).toBeGreaterThan(finishProfile('layup', { rating: 50 }).greenWindowMs);
  });

  it('a dunker reaches the rim at release', () => {
    const p = finishProfile('dunk', { rating: 85, vertical: 85, heightIn: 80 });
    expect(p.releaseHeightFt).toBeGreaterThan(10);
  });
});

describe('finishMakeProbability', () => {
  it('stays within 0..1 for any input', () => {
    for (const type of ['layup', 'dunk']) {
      for (const rating of [25, 60, 99]) {
        for (const contest of [0, 0.5, 1]) {
          const v = finishMakeProbability({ type, rating, contest, distanceFt: 5 });
          expect(v).toBeGreaterThan(0);
          expect(v).toBeLessThan(1);
        }
      }
    }
  });

  it('open dunks are near automatic, open layups are not', () => {
    expect(finishMakeProbability({ type: 'dunk', rating: 85, contest: 0, distanceFt: 2 })).toBeGreaterThan(0.9);
    const layup = finishMakeProbability({ type: 'layup', rating: 85, contest: 0, distanceFt: 2 });
    expect(layup).toBeLessThan(0.9);
    expect(layup).toBeGreaterThan(0.7);
  });

  it('contest and distance lower the odds; skill raises them', () => {
    const base = { type: 'layup', rating: 75, contest: 0, distanceFt: 3 };
    expect(finishMakeProbability({ ...base, contest: 0.8 })).toBeLessThan(finishMakeProbability(base));
    expect(finishMakeProbability({ ...base, distanceFt: 8 })).toBeLessThan(finishMakeProbability(base));
    expect(finishMakeProbability({ ...base, rating: 95 })).toBeGreaterThan(finishMakeProbability(base));
  });

  it('uses contestLevel with the finish profile resist', () => {
    const p = finishProfile('dunk', { vertical: 90, heightIn: 82 });
    const contest = contestLevel(2, 80, p.contestResist);
    const loose = contestLevel(2, 80, 0);
    expect(contest).toBeLessThan(loose);
  });
});

describe('finishRating / blocks', () => {
  const attrs = { closeShot: 90, drivingLayup: 70, drivingDunk: 80 };
  it('dunks use drivingDunk; tight layups can use closeShot touch', () => {
    expect(finishRating(attrs, 'dunk', 3)).toBe(80);
    expect(finishRating(attrs, 'layup', 3)).toBe(90);
    expect(finishRating(attrs, 'layup', 7)).toBe(70);
  });
  it('only contested misses are blocks', () => {
    expect(isBlocked(false, 0.8)).toBe(true);
    expect(isBlocked(false, 0.2)).toBe(false);
    expect(isBlocked(true, 0.9)).toBe(false);
  });
});

describe('sampleFinishPose', () => {
  it('rises to its peak at release and lands at the end', () => {
    for (const type of ['layup', 'dunk']) {
      const p = finishProfile(type, { vertical: 80, heightIn: 78 });
      const start = sampleFinishPose(p, 0);
      const peak = sampleFinishPose(p, p.releaseT);
      const end = sampleFinishPose(p, 1);
      expect(start.rootY).toBe(0);
      expect(peak.rootY).toBeCloseTo(p.jumpFt, 6);
      expect(end.rootY).toBe(0);
      expect(peak.travel).toBe(1);
      expect(peak.joints.rShoulder[0]).toBeLessThan(-2.5); // arm overhead
      for (const e of Object.values(peak.joints)) for (const v of e) expect(Number.isFinite(v)).toBe(true);
    }
  });

  it('matches the jumpshot pose format', () => {
    const shot = sampleShotPose(computeShotProfile({}, {}), 0.5);
    const pose = sampleFinishPose(finishProfile('layup', {}), 0.5);
    for (const k of Object.keys(shot)) expect(pose).toHaveProperty(k);
    for (const k of Object.keys(shot.joints)) expect(pose.joints).toHaveProperty(k);
  });
});
