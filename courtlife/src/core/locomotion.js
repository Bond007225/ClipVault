import { clamp } from './math.js';

// Skeleton proportions and the procedural poses for standing, running and
// reaching for the ball. Units are feet; the character faces +Z with its
// right side at -X.

export function rigDimensions(body) {
  const H = body.heightIn / 12;
  const wingspan = body.wingspanIn / 12;
  const shoulderHalf = H * 0.12 * (0.9 + body.build * 0.2);
  const arm = Math.max(H * 0.36, (wingspan - shoulderHalf * 2) / 2);
  return {
    H,
    hipHeight: H * 0.53,
    ankle: H * 0.04, // ankle joint height off the floor when standing
    hipHalf: H * 0.055,
    thigh: H * 0.245,
    shin: H * 0.245,
    torso: H * 0.29,
    neck: H * 0.04,
    head: H * 0.125,
    shoulderHalf,
    upperArm: arm * 0.45,
    forearm: arm * 0.38,
    hand: arm * 0.17,
    girth: (0.32 + (body.weightLb - 160) / 130 * 0.18) * (H / 6.5), // torso radius
    limb: 0.85 + body.build * 0.35, // limb thickness multiplier
  };
}

/**
 * Hip height for a pose with both feet planted (the lowest foot touches the
 * floor). Positive rootY lifts the body off the floor for jumps; crouching
 * comes from bending the legs, never from sinking through the floor.
 */
export function plantedHipHeight(dims, pose) {
  const j = pose.joints ?? {};
  let reach = 0;
  for (const side of ['l', 'r']) {
    const hip = j[`${side}Hip`]?.[0] ?? 0;
    const knee = j[`${side}Knee`]?.[0] ?? 0;
    reach = Math.max(reach, dims.thigh * Math.cos(hip) + dims.shin * Math.cos(hip + knee));
  }
  return reach + dims.ankle + Math.max(0, pose.rootY ?? 0);
}

/** Shoulder and elbow eulers so the hand lands near `target` (hip-relative). */
export function reachArm(dims, side, target) {
  const sx = side === 'R' ? -dims.shoulderHalf : dims.shoulderHalf;
  const sy = dims.torso;
  const dx = target.x - sx;
  const dy = target.y - sy;
  const dz = target.z;
  const len = Math.hypot(dx, dy, dz);
  const reach = dims.upperArm + dims.forearm + dims.hand * 0.5;
  const bend = Math.acos(clamp(len / reach, 0, 1)); // 0 when fully extended
  const pitch = -Math.atan2(dz, -dy) - bend;
  const roll = Math.atan2(dx, Math.hypot(dy, dz));
  return { shoulder: [pitch, 0, roll], elbow: [-bend * 2, 0, 0] };
}

/** Athletic stance with a subtle breathing bob. */
export function idlePose(timeSec) {
  const bob = Math.sin(timeSec * 2.2) * 0.04;
  return {
    rootY: 0,
    rootZ: 0,
    joints: {
      spine: [0.22, 0, 0],
      lHip: [-0.45 - bob, 0, 0.08],
      rHip: [-0.45 - bob, 0, -0.08],
      lKnee: [0.75 + bob * 2, 0, 0],
      rKnee: [0.75 + bob * 2, 0, 0],
      lShoulder: [-0.3, 0, 0.25],
      lElbow: [-0.9, 0, 0],
      rShoulder: [-0.3, 0, -0.25],
      rElbow: [-0.9, 0, 0],
    },
  };
}

/** Run cycle; phase in radians, intensity 0 (walk) .. 1 (sprint). */
export function runPose(phase, intensity) {
  const amp = 0.45 + intensity * 0.5;
  const s = Math.sin(phase);
  const c = Math.cos(phase);
  return {
    rootY: Math.abs(c) * 0.12 * amp,
    rootZ: 0,
    joints: {
      spine: [0.25 + intensity * 0.15, 0, 0],
      lHip: [-0.3 - s * amp, 0, 0],
      rHip: [-0.3 + s * amp, 0, 0],
      lKnee: [0.5 + Math.max(0, c) * amp * 1.4, 0, 0],
      rKnee: [0.5 + Math.max(0, -c) * amp * 1.4, 0, 0],
      lShoulder: [s * amp * 0.9, 0, 0.15],
      lElbow: [-1.3, 0, 0],
      rShoulder: [-s * amp * 0.9, 0, -0.15],
      rElbow: [-1.3, 0, 0],
    },
  };
}

/** Ball height for a plain stationary/running dribble. */
export function dribbleBallHeight(timeSec, rate, topY) {
  const p = (timeSec * rate) % 1;
  // Fast drop, slower rise feels like a real pound off the floor.
  const k = p < 0.45 ? 1 - p / 0.45 : (p - 0.45) / 0.55;
  return 0.38 + (topY - 0.38) * (1 - (1 - k) * (1 - k));
}

/** Straighten the legs by `amount` (0..~0.4), e.g. the rise of a hesitation. */
export function standTaller(pose, amount) {
  for (const side of ['l', 'r']) {
    pose.joints[`${side}Hip`][0] += amount * 1.2;
    pose.joints[`${side}Knee`][0] -= amount * 2;
  }
  return pose;
}
