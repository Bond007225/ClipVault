import { clamp, invLerp, lerp } from './math.js';

// Shot meter + make probability. Greens are guaranteed buckets unless you
// are smothered, so timing your own custom jumper is the skill that matters.

export const RIM = { x: 0, y: 10, z: 0, radius: 0.75 };
export const THREE_PT_RADIUS = 23.75;
export const CORNER_THREE_X = 22;
export const BASELINE_Z = -5.25; // baseline sits 5.25ft behind the rim centre

export function isThree(x, z) {
  if (Math.abs(x) >= CORNER_THREE_X && z < BASELINE_Z + 14) return true;
  return Math.hypot(x, z) > THREE_PT_RADIUS;
}

/** Grade a release: heldMs is how long the shot button was held. */
export function gradeRelease(profile, heldMs) {
  const delta = heldMs - profile.releaseTimeMs;
  const half = profile.greenWindowMs / 2;
  let grade;
  if (Math.abs(delta) <= half) grade = 'green';
  else if (Math.abs(delta) <= half + 70) grade = delta < 0 ? 'slightly-early' : 'slightly-late';
  else grade = delta < 0 ? 'early' : 'late';
  return { grade, delta };
}

/** 0 (wide open) .. 1 (smothered) from defender distance and size. */
export function contestLevel(defenderDistFt, defenderHeightIn, shooterResist) {
  if (defenderDistFt == null) return 0;
  const closeness = invLerp(7, 1.5, defenderDistFt);
  const length = lerp(0.8, 1.2, invLerp(72, 86, defenderHeightIn));
  return clamp(closeness * length * (1 - shooterResist * 0.5), 0, 1);
}

export function makeProbability({ grade, rating, distanceFt, contest }) {
  const range = invLerp(8, 30, distanceFt); // 0 at the paint, 1 deep
  if (grade === 'green') return clamp(1 - Math.max(0, contest - 0.7) * 1.5, 0.5, 1);
  if (grade === 'early' || grade === 'late') return clamp(0.08 - contest * 0.05, 0.01, 0.1);
  const skill = invLerp(40, 99, rating);
  const base = lerp(0.3, 0.62, skill) - range * 0.2;
  return clamp(base - contest * 0.35, 0.03, 0.75);
}

/** Pick which rating governs a shot from where it was taken. */
export function shotRating(attrs, distanceFt, three) {
  if (three) return attrs.threePoint;
  if (distanceFt < 8) return attrs.closeShot;
  return attrs.midRange;
}
