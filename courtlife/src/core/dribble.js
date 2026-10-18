import { clamp, lerp, invLerp, sampleKeyframes } from './math.js';
import { KEY_BINDINGS } from './catalog.js';

// Dribble creator: players chain primitive moves into combos, set the speed
// of every step, and bind combos to keys. Ball Handle gates the speed you can
// push and which moves are unlocked.
//
// Ball frames are in "hand space": s=+1 is the side of the hand the move
// starts in, y is height in feet off the floor, z is forward. They get
// mirrored per hand. The character faces +Z, so its right side is -X.

export const DRIBBLE_MOVES = {
  crossover: {
    label: 'Crossover', durationMs: 380, minHandle: 25, switchesHand: true, burst: { x: -0.8, z: 0.4 }, effectiveness: 0.35, lean: 0.25,
    ball: [{ t: 0, s: 1, y: 2.3, z: 0.7 }, { t: 0.45, s: 0, y: 0.38, z: 0.9 }, { t: 1, s: -1, y: 2.3, z: 0.7 }],
  },
  killCross: {
    label: 'Kill Cross', durationMs: 300, minHandle: 75, switchesHand: true, burst: { x: -1.2, z: 0.6 }, effectiveness: 0.55, lean: 0.45,
    ball: [{ t: 0, s: 1, y: 1.6, z: 0.8 }, { t: 0.45, s: 0, y: 0.38, z: 1.0 }, { t: 1, s: -1, y: 1.6, z: 0.8 }],
  },
  betweenLegs: {
    label: 'Between the Legs', durationMs: 420, minHandle: 45, switchesHand: true, burst: { x: 0, z: -0.3 }, effectiveness: 0.3, lean: 0.2,
    ball: [{ t: 0, s: 1, y: 2.2, z: 0.6 }, { t: 0.5, s: 0, y: 0.38, z: 0.05 }, { t: 1, s: -1, y: 2.2, z: 0.6 }],
  },
  behindBack: {
    label: 'Behind the Back', durationMs: 460, minHandle: 55, switchesHand: true, burst: { x: -0.6, z: 0.3 }, effectiveness: 0.4, lean: 0.15,
    ball: [{ t: 0, s: 1, y: 2.2, z: 0.4 }, { t: 0.35, s: 0.8, y: 1.2, z: -0.7 }, { t: 0.6, s: -0.6, y: 0.38, z: -0.5 }, { t: 1, s: -1, y: 2.2, z: 0.5 }],
  },
  hesitation: {
    label: 'Hesitation', durationMs: 520, minHandle: 35, switchesHand: false, burst: { x: 0, z: 1.6 }, effectiveness: 0.45, lean: -0.15, rise: 0.25,
    ball: [{ t: 0, s: 1, y: 2.3, z: 0.7 }, { t: 0.3, s: 1, y: 2.9, z: 0.9 }, { t: 0.65, s: 1.1, y: 0.38, z: 1.1 }, { t: 1, s: 1, y: 2.3, z: 0.9 }],
  },
  inAndOut: {
    label: 'In & Out', durationMs: 400, minHandle: 40, switchesHand: false, burst: { x: 0.6, z: 0.5 }, effectiveness: 0.35, lean: 0.3,
    ball: [{ t: 0, s: 1, y: 2.3, z: 0.7 }, { t: 0.4, s: 0.2, y: 1.8, z: 0.9 }, { t: 0.7, s: 1.1, y: 0.38, z: 0.9 }, { t: 1, s: 1, y: 2.3, z: 0.7 }],
  },
  spin: {
    label: 'Spin Move', durationMs: 560, minHandle: 50, switchesHand: true, burst: { x: -1.4, z: 1.2 }, effectiveness: 0.45, lean: 0.1, spin: true,
    ball: [{ t: 0, s: 1, y: 2.0, z: 0.7 }, { t: 0.5, s: 1.1, y: 2.4, z: -0.2 }, { t: 1, s: -1, y: 2.0, z: 0.7 }],
  },
  stepBack: {
    label: 'Step Back', durationMs: 480, minHandle: 45, switchesHand: false, burst: { x: 0, z: -2.6 }, effectiveness: 0.5, lean: -0.3,
    ball: [{ t: 0, s: 1, y: 2.3, z: 0.7 }, { t: 0.4, s: 0.9, y: 0.38, z: 0.6 }, { t: 1, s: 0.6, y: 2.5, z: 0.6 }],
  },
  snatchBack: {
    label: 'Snatch Back', durationMs: 440, minHandle: 80, switchesHand: false, burst: { x: 0, z: -2.0 }, effectiveness: 0.6, lean: -0.35,
    ball: [{ t: 0, s: 1, y: 2.2, z: 1.0 }, { t: 0.35, s: 1, y: 0.38, z: 1.3 }, { t: 1, s: 0.9, y: 2.4, z: 0.3 }],
  },
  pound: {
    label: 'Pound Dribble', durationMs: 260, minHandle: 25, switchesHand: false, burst: { x: 0, z: 0 }, effectiveness: 0.05, lean: 0.1,
    ball: [{ t: 0, s: 1, y: 2.0, z: 0.7 }, { t: 0.5, s: 1, y: 0.38, z: 0.7 }, { t: 1, s: 1, y: 2.0, z: 0.7 }],
  },
};

const sideX = (hand) => (hand === 'R' ? -1 : 1);

export const MAX_COMBO_STEPS = 6;
export const MAX_COMBOS = KEY_BINDINGS.length;
export const MIN_STEP_SPEED = 0.6;

/** Fastest step speed a handler can pull off. 60 handle = 1.0x, 99 = 1.5x. */
export const maxStepSpeed = (ballHandle) => lerp(1.0, 1.5, invLerp(60, 99, ballHandle));

export const DEFAULT_COMBOS = [
  { name: 'Cross Step', key: '1', steps: [{ move: 'crossover', speed: 1 }, { move: 'stepBack', speed: 1 }] },
  { name: 'Hesi Go', key: '2', steps: [{ move: 'pound', speed: 1 }, { move: 'hesitation', speed: 1 }] },
  { name: 'Legs Behind', key: '3', steps: [{ move: 'betweenLegs', speed: 1 }, { move: 'behindBack', speed: 1 }] },
  { name: 'Spin', key: '4', steps: [{ move: 'spin', speed: 1 }] },
];

export function normalizeCombos(combos) {
  if (!Array.isArray(combos)) return structuredClone(DEFAULT_COMBOS);
  const usedKeys = new Set();
  const out = [];
  for (const c of combos.slice(0, MAX_COMBOS)) {
    const steps = (Array.isArray(c?.steps) ? c.steps : [])
      .filter((s) => DRIBBLE_MOVES[s?.move])
      .slice(0, MAX_COMBO_STEPS)
      .map((s) => ({ move: s.move, speed: clamp(Number(s.speed) || 1, MIN_STEP_SPEED, 1.5) }));
    if (!steps.length) continue;
    let key = KEY_BINDINGS.includes(c.key) && !usedKeys.has(c.key) ? c.key : KEY_BINDINGS.find((k) => !usedKeys.has(k));
    usedKeys.add(key);
    out.push({ name: String(c.name || 'Combo').slice(0, 20), key, steps });
  }
  return out;
}

/** Problems with a combo for a given Ball Handle rating (locked moves, too fast). */
export function validateCombo(combo, ballHandle) {
  const errors = [];
  const cap = maxStepSpeed(ballHandle);
  combo.steps.forEach((step, i) => {
    const move = DRIBBLE_MOVES[step.move];
    if (ballHandle < move.minHandle) errors.push(`Step ${i + 1}: ${move.label} needs ${move.minHandle} Ball Handle`);
    if (step.speed > cap + 1e-9) errors.push(`Step ${i + 1}: max speed is ${cap.toFixed(2)}x at your Ball Handle`);
  });
  return { ok: errors.length === 0, errors };
}

/**
 * Turn a combo into a playable timeline. Locked moves are dropped and speeds
 * are clamped, so the game never plays something the build can't do.
 */
export function buildComboTimeline(combo, ballHandle, startHand = 'R') {
  const cap = maxStepSpeed(ballHandle);
  const segments = [];
  let time = 0;
  let hand = startHand;
  let ox = 0;
  let oz = 0;
  let effectiveness = 0;
  for (const step of combo.steps) {
    const move = DRIBBLE_MOVES[step.move];
    if (!move || ballHandle < move.minHandle) continue;
    const speed = clamp(step.speed, MIN_STEP_SPEED, cap);
    const duration = move.durationMs / speed;
    const side = sideX(hand);
    segments.push({ moveKey: step.move, move, start: time, end: time + duration, hand, speed, origin: { x: ox, z: oz } });
    // Burst x is expressed relative to the starting hand: a right-hand cross goes left.
    ox += move.burst.x * side;
    oz += move.burst.z;
    time += duration;
    // Combos chain: each extra step adds less, faster steps add more.
    effectiveness += move.effectiveness * speed * (1 / (1 + segments.length * 0.35));
    if (move.switchesHand) hand = hand === 'R' ? 'L' : 'R';
  }
  return { segments, totalMs: time, endHand: hand, offset: { x: ox, z: oz }, effectiveness: clamp(effectiveness, 0, 1) };
}

/** Ball/body state at tMs into a combo timeline. */
export function sampleCombo(timeline, tMs) {
  const segs = timeline.segments;
  if (!segs.length) return null;
  const seg = segs.find((s) => tMs < s.end) ?? segs[segs.length - 1];
  const local = clamp((tMs - seg.start) / (seg.end - seg.start), 0, 1);
  const side = sideX(seg.hand);
  const b = sampleKeyframes(seg.move.ball, local);
  const burstK = Math.sin(local * Math.PI * 0.5);
  const handNow = seg.move.switchesHand && local > 0.5 ? (seg.hand === 'R' ? 'L' : 'R') : seg.hand;
  return {
    moveKey: seg.moveKey,
    hand: handNow,
    ball: { x: b.s * side * 0.85, y: b.y, z: b.z },
    lean: seg.move.lean * Math.sin(local * Math.PI),
    rise: (seg.move.rise ?? 0) * Math.sin(local * Math.PI),
    yaw: seg.move.spin ? -side * local * Math.PI * 2 : 0,
    offset: {
      x: seg.origin.x + seg.move.burst.x * side * burstK,
      z: seg.origin.z + seg.move.burst.z * burstK,
    },
    done: tMs >= timeline.totalMs,
  };
}
