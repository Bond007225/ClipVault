export const clamp = (v, lo, hi) => Math.min(hi, Math.max(lo, v));
export const lerp = (a, b, t) => a + (b - a) * t;
export const invLerp = (a, b, v) => (a === b ? 0 : clamp((v - a) / (b - a), 0, 1));
export const smoothstep = (t) => {
  const x = clamp(t, 0, 1);
  return x * x * (3 - 2 * x);
};

/** Interpolate between keyframes [{t, ...numericFields}] sorted by t. */
export function sampleKeyframes(frames, t) {
  if (t <= frames[0].t) return { ...frames[0] };
  const last = frames[frames.length - 1];
  if (t >= last.t) return { ...last };
  let i = 0;
  while (frames[i + 1].t < t) i++;
  const a = frames[i];
  const b = frames[i + 1];
  const k = smoothstep((t - a.t) / (b.t - a.t));
  const out = { t };
  for (const key of Object.keys(a)) {
    if (key === 't') continue;
    out[key] = typeof a[key] === 'number' ? lerp(a[key], b[key] ?? a[key], k) : a[key];
  }
  return out;
}

/** Deterministic PRNG so tattoos/hair render identically every load. */
export function mulberry32(seed) {
  let s = seed >>> 0;
  return () => {
    s = (s + 0x6d2b79f5) >>> 0;
    let r = Math.imul(s ^ (s >>> 15), 1 | s);
    r = (r + Math.imul(r ^ (r >>> 7), 61 | r)) ^ r;
    return ((r ^ (r >>> 14)) >>> 0) / 4294967296;
  };
}
