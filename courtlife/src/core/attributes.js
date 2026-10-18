import { ATTRIBUTES, ATTRIBUTE_MIN, ATTRIBUTE_MAX, BODY_LIMITS } from './catalog.js';
import { clamp, invLerp } from './math.js';

// Body shapes the build: each attribute cap = base + height/weight/wingspan
// influence. Small guards get handles, bigs get rim protection, and long
// wingspans trade shooting for defense - no pay-to-win, just tradeoffs.
const CAP_RULES = {
  closeShot: { base: 80, h: 19, w: 6, ws: 0 },
  drivingLayup: { base: 97, h: -12, w: -6, ws: 4 },
  drivingDunk: { base: 70, h: 25, w: 2, ws: 4 },
  midRange: { base: 99, h: -10, w: -4, ws: -4 },
  threePoint: { base: 99, h: -16, w: -6, ws: -6 },
  freeThrow: { base: 99, h: -6, w: 0, ws: -3 },
  ballHandle: { base: 99, h: -26, w: -6, ws: -2 },
  speedWithBall: { base: 99, h: -24, w: -10, ws: 0 },
  passAccuracy: { base: 99, h: -12, w: 0, ws: 0 },
  perimeterDefense: { base: 88, h: -6, w: -4, ws: 14 },
  steal: { base: 88, h: -10, w: -4, ws: 14 },
  block: { base: 62, h: 28, w: 4, ws: 12 },
  speed: { base: 99, h: -22, w: -12, ws: 0 },
  acceleration: { base: 99, h: -24, w: -10, ws: 0 },
  vertical: { base: 96, h: -10, w: -14, ws: 0 },
  strength: { base: 62, h: 14, w: 24, ws: 0 },
  stamina: { base: 99, h: -4, w: -8, ws: 0 },
};

/** Total points the player can spread across attributes. */
export const ATTRIBUTE_BUDGET = 1150;

const bodyFactors = (body) => ({
  h: invLerp(BODY_LIMITS.heightIn[0], BODY_LIMITS.heightIn[1], body.heightIn),
  w: invLerp(BODY_LIMITS.weightLb[0], BODY_LIMITS.weightLb[1], body.weightLb),
  ws: invLerp(BODY_LIMITS.wingspanDelta[0], BODY_LIMITS.wingspanDelta[1], body.wingspanIn - body.heightIn),
});

export function attributeCaps(body) {
  const f = bodyFactors(body);
  const caps = {};
  for (const key of Object.keys(ATTRIBUTES)) {
    const r = CAP_RULES[key];
    const cap = r.base + r.h * f.h + r.w * f.w + r.ws * f.ws;
    caps[key] = Math.round(clamp(cap, 60, ATTRIBUTE_MAX));
  }
  return caps;
}

export const pointsUsed = (attrs) =>
  Object.keys(ATTRIBUTES).reduce((sum, k) => sum + (attrs[k] ?? ATTRIBUTE_MIN), 0);

/**
 * Clamp every attribute to its body cap, then if over budget shave points
 * off the highest attributes first so the result is always legal.
 */
export function legalizeAttributes(attrs, body) {
  const caps = attributeCaps(body);
  const out = {};
  for (const key of Object.keys(ATTRIBUTES)) {
    const v = Number.isFinite(attrs?.[key]) ? Math.round(attrs[key]) : 60;
    out[key] = clamp(v, ATTRIBUTE_MIN, caps[key]);
  }
  let over = pointsUsed(out) - ATTRIBUTE_BUDGET;
  while (over > 0) {
    const top = Object.keys(out).reduce((a, b) => (out[a] >= out[b] ? a : b));
    if (out[top] <= ATTRIBUTE_MIN) break;
    out[top] -= 1;
    over -= 1;
  }
  return out;
}

/** Try to set one attribute; returns the value actually allowed. */
export function setAttribute(attrs, body, key, value) {
  const caps = attributeCaps(body);
  const others = pointsUsed(attrs) - (attrs[key] ?? ATTRIBUTE_MIN);
  const maxByBudget = ATTRIBUTE_BUDGET - others;
  return clamp(Math.round(value), ATTRIBUTE_MIN, Math.min(caps[key], maxByBudget));
}

const OVR_WEIGHTS = {
  PG: { ballHandle: 3, passAccuracy: 3, threePoint: 2, speedWithBall: 2, drivingLayup: 1, perimeterDefense: 1, speed: 1 },
  SG: { threePoint: 3, midRange: 2, ballHandle: 2, drivingLayup: 1, perimeterDefense: 1, speed: 1, steal: 1 },
  SF: { midRange: 2, threePoint: 2, drivingLayup: 2, drivingDunk: 1, perimeterDefense: 2, vertical: 1 },
  PF: { closeShot: 3, drivingDunk: 2, strength: 2, block: 2, midRange: 1, vertical: 1 },
  C: { closeShot: 3, block: 3, strength: 3, drivingDunk: 1, vertical: 1 },
};

export function overallRating(attrs, position) {
  const weights = OVR_WEIGHTS[position] ?? OVR_WEIGHTS.SF;
  let total = 0;
  let wsum = 0;
  for (const key of Object.keys(ATTRIBUTES)) {
    const w = weights[key] ?? 0.5;
    total += (attrs[key] ?? ATTRIBUTE_MIN) * w;
    wsum += w;
  }
  return Math.round(total / wsum);
}

/** Short archetype label derived from the top two attribute groups. */
export function archetype(attrs) {
  const groups = {};
  for (const [key, meta] of Object.entries(ATTRIBUTES)) {
    groups[meta.group] = groups[meta.group] ?? [];
    groups[meta.group].push(attrs[key] ?? ATTRIBUTE_MIN);
  }
  const avg = Object.entries(groups)
    .map(([g, vals]) => [g, vals.reduce((a, b) => a + b, 0) / vals.length])
    .sort((a, b) => b[1] - a[1]);
  const names = {
    Finishing: ['Slashing', 'Slasher'],
    Shooting: ['Sharpshooting', 'Sharpshooter'],
    Playmaking: ['Playmaking', 'Playmaker'],
    Defense: ['Lockdown', 'Defender'],
    Physicals: ['Athletic', 'Athlete'],
  };
  return `${names[avg[0][0]][0]} ${names[avg[1][0]][1]}`;
}
