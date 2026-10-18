import { clamp, lerp, invLerp, sampleKeyframes } from './math.js';

// Finishing at the rim: layups and dunks. When the shot button is pressed
// close to the basket the game picks a finish instead of a jumper. Pure
// numbers only so the Unreal core (CLFinishing.cpp) can match it exactly.

export const FINISH_MAX_RANGE_FT = 9; // past this every shot is a jumper
export const RIM_HEIGHT_IN = 120;
export const DUNK_CLEARANCE_IN = 6; // the hand has to get this far above the rim
export const MIN_DUNK_RATING = 55;
export const BLOCK_CONTEST = 0.55; // a missed finish this contested reads as a block

const speedFactor = (speedFtPerSec) => invLerp(4, 14, speedFtPerSec ?? 0);

/** How high (inches) the hand gets at the peak of a running jump. */
export function dunkReachIn(heightIn, vertical, speedFtPerSec = 0) {
  const standingReach = heightIn * 1.33;
  const jump = lerp(16, 40, invLerp(25, 99, vertical));
  return standingReach + jump + speedFactor(speedFtPerSec) * 4;
}

/** Furthest distance (ft) a layup is taken from: a moving player can take off earlier. */
export function layupRangeFt(speedFtPerSec) {
  return lerp(6, FINISH_MAX_RANGE_FT, invLerp(2, 8, speedFtPerSec ?? 0));
}

/** Furthest distance (ft) a dunk is attempted from. */
export function dunkRangeFt(drivingDunk, speedFtPerSec) {
  return lerp(3, 7, invLerp(MIN_DUNK_RATING, 99, drivingDunk)) + speedFactor(speedFtPerSec) * 1.5;
}

/**
 * Pick the finish for a shot attempt.
 * @returns {'dunk'|'layup'|null} null = too far, take a jumper
 */
export function chooseFinish({ distanceFt, speedFtPerSec = 0, attrs, heightIn }) {
  if (!(distanceFt <= FINISH_MAX_RANGE_FT)) return null;
  const canDunk =
    attrs.drivingDunk >= MIN_DUNK_RATING &&
    distanceFt <= dunkRangeFt(attrs.drivingDunk, speedFtPerSec) &&
    dunkReachIn(heightIn, attrs.vertical, speedFtPerSec) >= RIM_HEIGHT_IN + DUNK_CLEARANCE_IN;
  // Attacking downhill favors throwing it down over laying it in.
  const dunkPreference = attrs.drivingDunk + speedFactor(speedFtPerSec) * 20;
  if (canDunk && dunkPreference >= attrs.drivingLayup) return 'dunk';
  if (distanceFt <= layupRangeFt(speedFtPerSec)) return 'layup';
  return null;
}

/** Which rating governs a finish. Right at the rim soft touch (closeShot) can carry a layup. */
export function finishRating(attrs, type, distanceFt) {
  if (type === 'dunk') return attrs.drivingDunk;
  return distanceFt <= 4 ? Math.max(attrs.closeShot, attrs.drivingLayup) : attrs.drivingLayup;
}

const FINISH_TIMING = {
  layup: { gatherMs: 260, airMs: 640, releaseT: 0.62, jump: 0.85 },
  dunk: { gatherMs: 300, airMs: 700, releaseT: 0.58, jump: 1.0 },
};

/**
 * Timing data for a finish, shaped like the jumpshot profile so a timed
 * finish meter can reuse the same grading later.
 * @param {'layup'|'dunk'} type
 * @param {object} ctx { rating, vertical, heightIn, distanceFt }
 */
export function finishProfile(type, ctx = {}) {
  const t = FINISH_TIMING[type] ?? FINISH_TIMING.layup;
  const rating = ctx.rating ?? 75;
  const vertical = ctx.vertical ?? 70;
  const heightIn = ctx.heightIn ?? 78;
  const distanceFt = clamp(ctx.distanceFt ?? 4, 0, FINISH_MAX_RANGE_FT);

  // Further out takes an extra step to get there.
  const gatherMs = Math.round(t.gatherMs + distanceFt * 12);
  const durationMs = gatherMs + t.airMs;
  const releaseTimeMs = Math.round(gatherMs + t.airMs * t.releaseT);
  const releaseT = releaseTimeMs / durationMs;
  const greenWindowMs = Math.round(lerp(20, 60, invLerp(40, 99, rating)));
  const jumpFt = t.jump * lerp(1.2, 3.0, invLerp(25, 99, vertical));
  const releaseHeightFt = (heightIn * 1.33) / 12 + jumpFt;
  const contestResist = clamp(invLerp(9, 12.5, releaseHeightFt) * 0.7 + (type === 'dunk' ? 0.2 : 0), 0, 1);
  return { type: type === 'dunk' ? 'dunk' : 'layup', gatherMs, durationMs, releaseTimeMs, releaseT, greenWindowMs, jumpFt, releaseHeightFt, contestResist };
}

/** 0..1 chance a finish goes down. contest comes from contestLevel(). */
export function finishMakeProbability({ type, rating, contest = 0, distanceFt = 0 }) {
  const skill = invLerp(40, 99, rating);
  if (type === 'dunk') {
    const base = lerp(0.82, 0.98, skill);
    return clamp(base - contest * lerp(0.45, 0.25, skill), 0.05, 0.98);
  }
  const base = lerp(0.55, 0.85, skill) - invLerp(2, 9, distanceFt) * 0.12;
  return clamp(base - contest * lerp(0.5, 0.3, skill), 0.05, 0.98);
}

export const isBlocked = (made, contest) => !made && contest >= BLOCK_CONTEST;

/**
 * Procedural finish pose at normalized time t (0..1), in the same format as
 * sampleShotPose. The ball rides in the right palm; `travel` (0..1) is how far
 * along the approach to the rim the body should be.
 */
export function sampleFinishPose(profile, t) {
  const dunk = profile.type === 'dunk';
  const g = profile.gatherMs / profile.durationMs;
  const rt = profile.releaseT;
  const j = profile.jumpFt;
  const reach = dunk ? -2.95 : -2.75;
  const frames = [
    { t: 0, rootY: 0, knee: 0.6, hip: -0.5, lift: 0, spine: 0.35, rSh: -0.9, rEl: -1.6, rWr: 0.3, lSh: -0.9, lEl: -1.5, lShZ: 0.1 },
    { t: g * 0.6, rootY: 0, knee: 0.9, hip: -0.75, lift: 0, spine: 0.4, rSh: -1.1, rEl: -1.7, rWr: 0.4, lSh: -1.1, lEl: -1.6, lShZ: 0.15 },
    { t: g, rootY: j * 0.15, knee: 0.5, hip: -0.4, lift: 0.6, spine: 0.25, rSh: -1.7, rEl: -1.6, rWr: 0.5, lSh: -1.6, lEl: -1.5, lShZ: 0.2 },
    { t: rt, rootY: j, knee: 0.15, hip: -0.1, lift: 1, spine: dunk ? 0.05 : -0.05, rSh: reach, rEl: dunk ? -0.35 : -0.15, rWr: dunk ? 0.6 : -0.5, lSh: dunk ? -2.4 : -1.4, lEl: -0.8, lShZ: 0.35 },
    { t: Math.min(0.97, rt + 0.12), rootY: j * 0.7, knee: 0.2, hip: -0.15, lift: 0.6, spine: 0.15, rSh: dunk ? -2.7 : -2.3, rEl: -0.4, rWr: dunk ? 0.9 : -0.8, lSh: -1.3, lEl: -0.9, lShZ: 0.3 },
    { t: 1, rootY: 0, knee: 0.7, hip: -0.45, lift: 0, spine: 0.25, rSh: -0.6, rEl: -1.0, rWr: 0, lSh: -0.5, lEl: -1.0, lShZ: 0.15 },
  ];
  const f = sampleKeyframes(frames, clamp(t, 0, 1));
  // Layups drive the off knee up; dunks gather both legs.
  const lLift = dunk ? f.lift * 0.5 : f.lift;
  const rLift = dunk ? f.lift * 0.5 : f.lift * 0.15;
  return {
    rootY: Math.max(0, f.rootY),
    rootZ: 0,
    travel: clamp(t / rt, 0, 1),
    joints: {
      spine: [f.spine, 0, 0],
      lHip: [f.hip - lLift * 1.0, 0, 0.06],
      rHip: [f.hip - rLift * 1.0, 0, -0.06],
      lKnee: [f.knee + lLift * 1.2, 0, 0],
      rKnee: [f.knee + rLift * 1.2, 0, 0],
      rShoulder: [f.rSh, 0, -0.1],
      rElbow: [f.rEl, 0, 0],
      rWrist: [f.rWr, 0, 0],
      lShoulder: [f.lSh, 0, f.lShZ],
      lElbow: [f.lEl, 0, 0],
      lWrist: [0.3, 0, 0],
    },
  };
}
