import { clamp, lerp, sampleKeyframes, invLerp } from './math.js';

// Jumpshot creator: a base (lower body + set point) blended with two upper
// releases. Every number here feeds both the animation and the shot meter,
// so what you see is literally what you time.

export const SHOT_BASES = {
  classic: { label: 'Classic', setPoint: 0.7, dip: 0.35, jump: 1.0, legKick: 0, flare: 0.1, releaseT: 0.66, drift: 0, hitch: 0 },
  quickSet: { label: 'Quick Set', setPoint: 0.3, dip: 0.22, jump: 0.8, legKick: 0, flare: 0.05, releaseT: 0.58, drift: 0, hitch: 0 },
  highSet: { label: 'High Set', setPoint: 1.0, dip: 0.4, jump: 1.05, legKick: 0, flare: 0.05, releaseT: 0.7, drift: 0, hitch: 0 },
  sideSet: { label: 'Side Set', setPoint: 0.6, dip: 0.3, jump: 0.95, legKick: 0.1, flare: 0.55, releaseT: 0.64, drift: 0, hitch: 0 },
  oneMotion: { label: 'One Motion', setPoint: 0.55, dip: 0.5, jump: 0.9, legKick: 0, flare: 0.15, releaseT: 0.62, drift: 0.1, hitch: 0 },
  setShot: { label: 'Set Shot', setPoint: 0.5, dip: 0.3, jump: 0.15, legKick: 0, flare: 0.1, releaseT: 0.6, drift: 0, hitch: 0 },
  legKick: { label: 'Leg Kick', setPoint: 0.75, dip: 0.35, jump: 1.0, legKick: 0.9, flare: 0.15, releaseT: 0.68, drift: 0.3, hitch: 0 },
  hitch: { label: 'Hitch', setPoint: 0.85, dip: 0.35, jump: 1.0, legKick: 0.2, flare: 0.1, releaseT: 0.74, drift: 0, hitch: 0.12 },
};

export const SHOT_RELEASES = {
  quickFlick: { label: 'Quick Flick', extension: 0.8, snap: 1.0, follow: 0.3, height: 0.45, tempo: 1.15, guideOff: 0.3 },
  highArc: { label: 'High Arc', extension: 1.0, snap: 0.8, follow: 0.85, height: 1.0, tempo: 0.95, guideOff: 0.4 },
  push: { label: 'Push', extension: 0.7, snap: 0.4, follow: 0.4, height: 0.3, tempo: 1.0, guideOff: 0.2 },
  smoothHold: { label: 'Smooth Hold', extension: 1.0, snap: 0.9, follow: 1.0, height: 0.8, tempo: 1.0, guideOff: 0.5 },
  guideFlare: { label: 'Guide Hand Flare', extension: 0.9, snap: 0.9, follow: 0.6, height: 0.7, tempo: 1.02, guideOff: 1.0 },
  slingshot: { label: 'Slingshot', extension: 0.85, snap: 0.7, follow: 0.5, height: 0.55, tempo: 1.1, guideOff: 0.35 },
  wristy: { label: 'Wristy', extension: 0.75, snap: 1.0, follow: 0.7, height: 0.6, tempo: 1.08, guideOff: 0.25 },
};

export const SHOT_SPEEDS = [1, 2, 3, 4, 5];

export const DEFAULT_JUMPSHOT = { base: 'classic', release1: 'highArc', release2: 'quickFlick', blend: 30, speed: 3 };

export function normalizeJumpshot(js = {}) {
  return {
    base: SHOT_BASES[js.base] ? js.base : DEFAULT_JUMPSHOT.base,
    release1: SHOT_RELEASES[js.release1] ? js.release1 : DEFAULT_JUMPSHOT.release1,
    release2: SHOT_RELEASES[js.release2] ? js.release2 : DEFAULT_JUMPSHOT.release2,
    blend: clamp(Math.round(Number.isFinite(js.blend) ? js.blend : DEFAULT_JUMPSHOT.blend), 0, 100),
    speed: clamp(Math.round(Number.isFinite(js.speed) ? js.speed : DEFAULT_JUMPSHOT.speed), 1, 5),
  };
}

function blendedRelease(js) {
  const a = SHOT_RELEASES[js.release1];
  const b = SHOT_RELEASES[js.release2];
  const t = js.blend / 100;
  const out = {};
  for (const k of Object.keys(a)) if (typeof a[k] === 'number') out[k] = lerp(a[k], b[k], t);
  return out;
}

/**
 * Everything the game needs to know about a jumpshot.
 * @param {object} jumpshot   normalized jumpshot
 * @param {object} ctx        { threePoint, vertical, heightIn }
 */
export function computeShotProfile(jumpshot, ctx = {}) {
  const js = normalizeJumpshot(jumpshot);
  const base = SHOT_BASES[js.base];
  const rel = blendedRelease(js);
  const rating = ctx.threePoint ?? 75;
  const vertical = ctx.vertical ?? 70;
  const heightIn = ctx.heightIn ?? 78;

  const speedMult = lerp(0.8, 1.25, (js.speed - 1) / 4) * rel.tempo;
  const durationMs = Math.round(1050 / speedMult);
  const releaseT = clamp(base.releaseT + base.hitch * 0.5, 0.5, 0.85);
  const releaseTimeMs = Math.round(durationMs * releaseT);

  // Rhythm: blending two releases with very different tempos is harder to time.
  const tempoClash = Math.abs(SHOT_RELEASES[js.release1].tempo - SHOT_RELEASES[js.release2].tempo);
  const blendMix = Math.min(js.blend, 100 - js.blend) / 50; // 0 at ends, 1 at 50/50
  const rhythm = 1 - tempoClash * blendMix * 1.5;

  const ratingWindow = lerp(18, 52, invLerp(50, 99, rating));
  const speedAdjust = (3 - js.speed) * 2.5; // faster shots = slightly tighter window
  const greenWindowMs = Math.round(clamp((ratingWindow + speedAdjust) * rhythm, 10, 70));

  const jumpFt = base.jump * lerp(0.6, 1.6, invLerp(25, 99, vertical));
  const releaseHeightFt =
    (heightIn / 12) * 1.18 + base.setPoint * 0.35 + rel.height * 0.45 + rel.extension * 0.2 + jumpFt;

  // How hard the release is to contest: high + quick = tough to block.
  const contestResist = clamp(
    invLerp(7.5, 12, releaseHeightFt) * 0.6 + invLerp(500, 320, releaseTimeMs) * 0.4,
    0,
    1,
  );

  return { ...js, base, release: rel, durationMs, releaseT, releaseTimeMs, greenWindowMs, jumpFt, releaseHeightFt, contestResist, rhythm };
}

/**
 * Pose at normalized time t (0..1) through the shot. Joint angles are Euler
 * radians in the rig's local space; rootY/rootZ are feet of hip offset.
 */
export function sampleShotPose(profile, t) {
  const b = profile.base;
  const r = profile.release;
  const rt = profile.releaseT;
  const setT = rt - 0.16 - b.hitch;
  const holdT = setT + b.hitch;
  const setArm = -(1.7 + b.setPoint * 1.1);
  const frames = [
    { t: 0, rootY: 0, rootZ: 0, knee: 0.35, hip: -0.25, spine: 0.12, rSh: -0.7, rShZ: 0, rEl: -1.7, rWr: 0.2, lSh: -0.7, lShZ: 0.1, lEl: -1.6, kick: 0 },
    { t: 0.22, rootY: -b.dip * 0.9, rootZ: 0, knee: 0.6 + b.dip * 1.2, hip: -0.4 - b.dip, spine: 0.25, rSh: -0.9, rShZ: b.flare * 0.4, rEl: -1.9, rWr: 0.5, lSh: -0.9, lShZ: 0.15, lEl: -1.7, kick: 0 },
    { t: setT, rootY: profile.jumpFt * 0.55, rootZ: -b.drift * 0.3, knee: 0.15, hip: -0.05, spine: 0.0, rSh: setArm, rShZ: b.flare * 0.7, rEl: -(1.95 - b.setPoint * 0.35), rWr: 0.9, lSh: setArm + 0.15, lShZ: 0.35, lEl: -1.6, kick: b.legKick * 0.4 },
    { t: holdT, rootY: profile.jumpFt * 0.8, rootZ: -b.drift * 0.45, knee: 0.1, hip: -0.02, spine: -0.02, rSh: setArm - 0.05, rShZ: b.flare * 0.7, rEl: -(1.9 - b.setPoint * 0.35), rWr: 0.9, lSh: setArm + 0.1, lShZ: 0.35, lEl: -1.55, kick: b.legKick * 0.6 },
    { t: rt, rootY: profile.jumpFt, rootZ: -b.drift * 0.7, knee: 0.08, hip: 0, spine: -0.05, rSh: -2.55 - r.height * 0.4, rShZ: b.flare * 0.3, rEl: -0.15 - (1 - r.extension) * 0.9, rWr: -0.9 * r.snap, lSh: -2.1 - r.guideOff * 0.25, lShZ: 0.35 + r.guideOff * 0.6, lEl: -0.9 + r.guideOff * 0.4, kick: b.legKick },
    { t: Math.min(0.98, rt + 0.1 + r.follow * 0.08), rootY: profile.jumpFt * 0.55, rootZ: -b.drift, knee: 0.15, hip: -0.05, spine: -0.05, rSh: -2.5 - r.height * 0.4, rShZ: b.flare * 0.3, rEl: -0.15 - (1 - r.extension) * 0.9, rWr: -1.2 * r.snap, lSh: -1.9, lShZ: 0.4 + r.guideOff * 0.5, lEl: -0.8, kick: b.legKick * 0.7 },
    { t: 1, rootY: 0, rootZ: -b.drift, knee: 0.4, hip: -0.2, spine: 0.08, rSh: -1.2 + r.follow * -0.8, rShZ: 0, rEl: -0.6, rWr: -0.6, lSh: -0.6, lShZ: 0.15, lEl: -0.8, kick: 0 },
  ];
  const f = sampleKeyframes(frames, clamp(t, 0, 1));
  return {
    rootY: Math.max(-0.6, f.rootY),
    rootZ: f.rootZ,
    joints: {
      spine: [f.spine, 0, 0],
      lHip: [f.hip, 0, 0],
      rHip: [f.hip - f.kick * 0.6, 0, -f.kick * 0.25],
      lKnee: [f.knee, 0, 0],
      rKnee: [f.knee + f.kick * 0.9, 0, 0],
      rShoulder: [f.rSh, 0, -f.rShZ],
      rElbow: [f.rEl, 0, 0],
      rWrist: [f.rWr, 0, 0],
      lShoulder: [f.lSh, 0, f.lShZ],
      lElbow: [f.lEl, 0, 0],
      lWrist: [0.3, 0, 0],
    },
  };
}

