import { clamp, lerp, invLerp } from '../core/math.js';

// On-ball defender brain. Pure functions over plain objects so it can be
// unit tested without a renderer.

export function createDefender(attrs, heightIn) {
  return {
    x: 0, z: 14, vx: 0, vz: 0,
    seenX: 0, seenZ: 20, // lagged read of the ball handler
    stumble: 0, // seconds left on the floor after getting crossed
    contest: 0, // seconds left in a contest jump
    attrs, heightIn,
  };
}

/** Where a good defender wants to stand: between the ball and the rim. */
export function guardSpot(handler, rim, distFt) {
  const dx = rim.x - handler.x;
  const dz = rim.z - handler.z;
  const len = Math.hypot(dx, dz) || 1;
  const d = Math.min(distFt, len * 0.6);
  return { x: handler.x + (dx / len) * d, z: handler.z + (dz / len) * d };
}

export function stepDefender(def, handler, rim, dt) {
  const a = def.attrs;
  if (def.stumble > 0) {
    def.stumble = Math.max(0, def.stumble - dt);
    def.vx *= 0.9;
    def.vz *= 0.9;
    def.x += def.vx * dt;
    def.z += def.vz * dt;
    return def;
  }
  def.contest = Math.max(0, def.contest - dt);
  // Reaction: better perimeter defenders read the handler sooner.
  const react = lerp(3.5, 9, invLerp(40, 99, a.perimeterDefense));
  const k = 1 - Math.exp(-react * dt);
  def.seenX += (handler.x - def.seenX) * k;
  def.seenZ += (handler.z - def.seenZ) * k;

  const distToRim = Math.hypot(handler.x - rim.x, handler.z - rim.z);
  const cushion = distToRim > 26 ? 6 : lerp(2.6, 4, invLerp(4, 24, distToRim));
  const spot = guardSpot({ x: def.seenX, z: def.seenZ }, rim, cushion);
  const maxSpeed = lerp(9, 14, invLerp(40, 99, a.speed));
  const accel = lerp(30, 60, invLerp(40, 99, a.acceleration));
  const dx = spot.x - def.x;
  const dz = spot.z - def.z;
  const dist = Math.hypot(dx, dz);
  const want = Math.min(maxSpeed, dist * 6);
  const tvx = dist > 0.01 ? (dx / dist) * want : 0;
  const tvz = dist > 0.01 ? (dz / dist) * want : 0;
  const dvx = tvx - def.vx;
  const dvz = tvz - def.vz;
  const dv = Math.hypot(dvx, dvz);
  const step = Math.min(dv, accel * dt);
  if (dv > 0) {
    def.vx += (dvx / dv) * step;
    def.vz += (dvz / dv) * step;
  }
  def.x += def.vx * dt;
  def.z += def.vz * dt;
  return def;
}

/**
 * Did a dribble combo shake the defender? Returns the stumble duration
 * (0 when they stayed in front). `roll` is injected for testability.
 */
export function ankleBreakCheck({ effectiveness, ballHandle, defense, distanceFt, roll }) {
  if (distanceFt > 7) return 0;
  const proximity = invLerp(7, 2.5, distanceFt);
  const skill = lerp(0.6, 1.35, invLerp(50, 99, ballHandle));
  const resist = lerp(0.1, 0.45, invLerp(40, 99, defense));
  const chance = clamp(effectiveness * skill * (0.5 + proximity * 0.5) - resist, 0.02, 0.85);
  return roll < chance ? lerp(0.9, 1.8, effectiveness) : 0;
}

export function startContest(def, shooter) {
  const d = Math.hypot(def.x - shooter.x, def.z - shooter.z);
  if (def.stumble > 0 || d > 8) return false;
  def.contest = 0.8;
  // Close out: lunge toward the shooter.
  const len = d || 1;
  def.vx = ((shooter.x - def.x) / len) * 8;
  def.vz = ((shooter.z - def.z) / len) * 8;
  return true;
}
