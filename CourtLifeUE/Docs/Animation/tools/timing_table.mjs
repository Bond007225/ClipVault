#!/usr/bin/env node
// Generates CourtLifeUE/Docs/Animation/TIMING_REFERENCE.md from the web core
// (courtlife/src/core), which is kept in parity with Source/CourtLife/Core.
// Never hand-edit the numbers in TIMING_REFERENCE.md: re-run this instead.
//
//   node CourtLifeUE/Docs/Animation/tools/timing_table.mjs > CourtLifeUE/Docs/Animation/TIMING_REFERENCE.md
//
// Authoring constants (see NAMING.md / ANIM_BLUEPRINT.md):
//   FPS = 60, shot base master length = 1050 ms (63 frames), dribble move
//   authored length = core durationMs at 1.0x.

import { SHOT_BASES, SHOT_RELEASES, SHOT_SPEEDS, computeShotProfile } from '../../../../courtlife/src/core/jumpshot.js';
import { DRIBBLE_MOVES, buildComboTimeline, maxStepSpeed, DEFAULT_COMBOS, MIN_STEP_SPEED } from '../../../../courtlife/src/core/dribble.js';

const FPS = 60;
const SHOT_MASTER_MS = 1050; // durationMs = round(1050 / playRate)  =>  authored length must be 1050 ms
const NEUTRAL = { release1: 'smoothHold', release2: 'smoothHold', blend: 0 }; // tempo 1.00
const DRIBBLE_SPEEDS = [0.6, 1.0, 1.5];
const BALL_RADIUS_FT = 0.38; // ball keyframes with y == 0.38 are floor contacts

const f = (ms) => (ms * FPS) / 1000;
const fmtF = (frames) => (Number.isInteger(Math.round(frames * 1000) / 1000) ? String(Math.round(frames)) : frames.toFixed(2));
const n2 = (v) => v.toFixed(2);
const out = [];
const p = (s = '') => out.push(s);

// Ball Handle needed for a given step speed (inverse of maxStepSpeed).
function handleForSpeed(s) {
  if (s <= 1) return 0;
  for (let bh = 0; bh <= 99; bh++) if (maxStepSpeed(bh) + 1e-9 >= s) return bh;
  return Infinity;
}

p('# CourtLife Timing Reference');
p();
p('> **Generated file.** Produced by `Docs/Animation/tools/timing_table.mjs` from `courtlife/src/core/jumpshot.js` and `dribble.js`');
p('> (kept in parity with `Source/CourtLife/Core/CLJumpshot.cpp` / `CLDribble.cpp`). Do not hand-edit; re-run:');
p('>');
p('> `node CourtLifeUE/Docs/Animation/tools/timing_table.mjs > CourtLifeUE/Docs/Animation/TIMING_REFERENCE.md`');
p();
p(`Authoring rate is **${FPS} fps**. Frame numbers are 0-based from the first frame of the clip; fractional frames mean the notify sits between frames (Unreal notifies are time-based, so place them by **time in seconds**, not by frame).`);
p();

// ---------------------------------------------------------------- shots
p('## 1. Jumpshot bases');
p();
p(`Core rule: \`playRate = lerp(0.8, 1.25, (speed-1)/4) * releaseTempo\`, \`durationMs = round(1050 / playRate)\`, \`releaseT = clamp(base.releaseT + base.hitch*0.5, 0.5, 0.85)\`, \`releaseTimeMs = round(durationMs * releaseT)\`.`);
p(`So every base montage must be authored **exactly ${SHOT_MASTER_MS} ms = ${fmtF(f(SHOT_MASTER_MS))} frames @ ${FPS} fps** long; the montage then plays at \`FCLShotProfile::PlayRate\` and lasts exactly \`DurationMs\`.`);
p();
p('### 1a. Release notify placement (authored time, play rate 1.0)');
p();
p('| Base ID | code releaseT | hitch | effective releaseT | Release notify time (s) | Release notify frame @60 | Montage length |');
p('|---|---|---|---|---|---|---|');
for (const [id, b] of Object.entries(SHOT_BASES)) {
  const prof = computeShotProfile({ base: id, ...NEUTRAL, speed: 3 });
  const tMs = SHOT_MASTER_MS * prof.releaseT;
  p(`| \`${id}\` | ${b.releaseT} | ${b.hitch} | ${n2(prof.releaseT)} | ${(tMs / 1000).toFixed(4)} | ${fmtF(f(tMs))} | 1.0500 s / ${fmtF(f(SHOT_MASTER_MS))} f |`);
}
p();
p('### 1b. Duration and release time by shot speed (neutral release: `smoothHold`, tempo 1.00)');
p();
p('Each cell is `durationMs / releaseTimeMs`. These are the values the shot meter uses (`FCLShotProfile::DurationMs` / `ReleaseTimeMs`).');
p();
p(`| Base ID | ${SHOT_SPEEDS.map((s) => `Speed ${s}`).join(' | ')} |`);
p(`|---|${SHOT_SPEEDS.map(() => '---').join('|')}|`);
for (const id of Object.keys(SHOT_BASES)) {
  const cells = SHOT_SPEEDS.map((speed) => {
    const pr = computeShotProfile({ base: id, ...NEUTRAL, speed });
    return `${pr.durationMs} / ${pr.releaseTimeMs}`;
  });
  p(`| \`${id}\` | ${cells.join(' | ')} |`);
}
p();
p('Play rate per speed with the neutral release (same for every base):');
p();
p(`| | ${SHOT_SPEEDS.map((s) => `Speed ${s}`).join(' | ')} |`);
p(`|---|${SHOT_SPEEDS.map(() => '---').join('|')}|`);
{
  const rates = SHOT_SPEEDS.map((speed) => {
    const sm = (0.8 + (1.25 - 0.8) * ((speed - 1) / 4)) * SHOT_RELEASES.smoothHold.tempo;
    return sm.toFixed(4);
  });
  p(`| PlayRate | ${rates.join(' | ')} |`);
  const durs = SHOT_SPEEDS.map((speed) => computeShotProfile({ base: 'classic', ...NEUTRAL, speed }).durationMs);
  p(`| DurationMs | ${durs.join(' | ')} |`);
}
p();

// Sync check: authored 1050 ms montage at PlayRate vs the core's numbers.
{
  let worstDur = 0;
  let worstRel = 0;
  for (const id of Object.keys(SHOT_BASES))
    for (const r of Object.keys(SHOT_RELEASES))
      for (const speed of SHOT_SPEEDS) {
        const pr = computeShotProfile({ base: id, release1: r, release2: r, blend: 0, speed });
        const sm = (0.8 + (1.25 - 0.8) * ((speed - 1) / 4)) * SHOT_RELEASES[r].tempo;
        const wallDur = SHOT_MASTER_MS / sm;
        const wallRel = (SHOT_MASTER_MS * pr.releaseT) / sm;
        worstDur = Math.max(worstDur, Math.abs(wallDur - pr.durationMs));
        worstRel = Math.max(worstRel, Math.abs(wallRel - pr.releaseTimeMs));
      }
  p(`**Sync check** (all 8 bases x 7 releases x 5 speeds): a ${SHOT_MASTER_MS} ms montage played at PlayRate ends within **${worstDur.toFixed(2)} ms** of \`DurationMs\` and hits its Release notify within **${worstRel.toFixed(2)} ms** of \`ReleaseTimeMs\` (rounding only; under one 60 fps frame = 16.67 ms).`);
  p();
}

p('### 1c. Release tempo (each release used alone, blend 0, Speed 3)');
p();
p('Releases change the play rate of the whole shot through `tempo`. Blended releases lerp tempo by `ReleaseBlend`.');
p();
p('| Release ID | tempo | PlayRate @ Speed 3 | DurationMs @ Speed 3 | ReleaseTimeMs (`classic`) | Speed 1 → 5 duration range |');
p('|---|---|---|---|---|---|');
for (const [id, r] of Object.entries(SHOT_RELEASES)) {
  const pr = computeShotProfile({ base: 'classic', release1: id, release2: id, blend: 0, speed: 3 });
  const slow = computeShotProfile({ base: 'classic', release1: id, release2: id, blend: 0, speed: 1 });
  const fast = computeShotProfile({ base: 'classic', release1: id, release2: id, blend: 0, speed: 5 });
  p(`| \`${id}\` | ${r.tempo} | ${(1.025 * r.tempo).toFixed(4)} | ${pr.durationMs} | ${pr.releaseTimeMs} | ${slow.durationMs} → ${fast.durationMs} ms |`);
}
{
  let lo = Infinity;
  let hi = -Infinity;
  for (const id of Object.keys(SHOT_BASES))
    for (const r of Object.keys(SHOT_RELEASES))
      for (const speed of SHOT_SPEEDS) {
        const pr = computeShotProfile({ base: id, release1: r, release2: r, blend: 0, speed });
        lo = Math.min(lo, pr.releaseTimeMs);
        hi = Math.max(hi, pr.releaseTimeMs);
      }
  p();
  p(`Across every base, release and speed, ReleaseTimeMs spans **${lo}–${hi} ms** after the button press.`);
}
p();

// ---------------------------------------------------------------- dribble
p('## 2. Dribble moves');
p();
p(`Core rule: \`segmentMs = durationMs / speed\`, speed clamped to [${MIN_STEP_SPEED}, maxStepSpeed(BallHandle)], \`maxStepSpeed = lerp(1.0, 1.5, invLerp(60, 99, BallHandle))\`. \`UCLDribbleComponent\` plays each montage at \`PlayLength / segmentMs\`, so author at natural speed; if you author the clip at exactly \`durationMs\` the play rate equals the step speed.`);
p();
p(`| Move ID | Min Ball Handle | durationMs (1.0x) | Frames @60 | ${DRIBBLE_SPEEDS.map((s) => `${s.toFixed(1)}x ms`).join(' | ')} |`);
p(`|---|---|---|---|${DRIBBLE_SPEEDS.map(() => '---').join('|')}|`);
for (const [id, m] of Object.entries(DRIBBLE_MOVES)) {
  const cells = DRIBBLE_SPEEDS.map((s) => {
    const tl = buildComboTimeline({ steps: [{ move: id, speed: s }] }, 99, 'R');
    return tl.totalMs.toFixed(1);
  });
  p(`| \`${id}\` | ${m.minHandle} | ${m.durationMs} | ${fmtF(f(m.durationMs))} | ${cells.join(' | ')} |`);
}
p();
p(`Ball Handle needed to set a step to each speed: ${DRIBBLE_SPEEDS.map((s) => `${s.toFixed(1)}x → ${handleForSpeed(s) || 'any'}`).join(', ')} (plus the move's own minimum).`);
p();

p('### 2a. Contact frames, hand switch and displacement (authored at 1.0x, right-hand start)');
p();
p('Floor contacts come from the core ball keyframes (`ball.y == 0.38 ft`, the ball radius). Hand switch is where `SampleCombo` flips `hand` (local t > 0.5). Burst is the total displacement in ft; the core eases it in with `sin(t·π/2)`. Lean/rise peak at local t = 0.5 (`sin(t·π)`).');
p();
p('| Move ID | Floor contact t | Contact ms / frame @60 | Hand switch ms / frame @60 | Burst R-start (x, z) ft | Burst L-start (x, z) ft | Peak lean | Peak rise | Yaw |');
p('|---|---|---|---|---|---|---|---|---|');
for (const [id, m] of Object.entries(DRIBBLE_MOVES)) {
  const contacts = m.ball.filter((k) => Math.abs(k.y - BALL_RADIUS_FT) < 1e-6);
  const ct = contacts.map((k) => k.t).join(', ') || '—';
  const cms = contacts.map((k) => `${(k.t * m.durationMs).toFixed(0)} / ${fmtF(f(k.t * m.durationMs))}`).join(', ') || '—';
  const sw = m.switchesHand ? `${(0.5 * m.durationMs).toFixed(0)} / ${fmtF(f(0.5 * m.durationMs))}` : 'no switch';
  // Core: right side is -x; sideX(R) = -1, sideX(L) = +1; offset.x += burst.x * side.
  const rx = m.burst.x * -1 || 0;
  const lx = m.burst.x * 1 || 0;
  const yaw = m.spin ? '360° (R start: turns left, counter-clockwise from above; L start: clockwise)' : '0';
  p(`| \`${id}\` | ${ct} | ${cms} | ${sw} | (${n2(rx)}, ${n2(m.burst.z)}) | (${n2(lx)}, ${n2(m.burst.z)}) | ${n2(m.lean)} | ${n2(m.rise ?? 0)} | ${yaw} |`);
}
p();
p('Axis convention for the burst columns: core local space, player faces +z, **+x is the player\'s left** (the core puts the right side at -x). A right-hand crossover therefore moves +0.80 ft to the left and 0.40 ft forward. In Unreal mesh space (+X forward, +Y right) that is X = +z·30.48 uu, Y = -x·30.48 uu.');
p();

p('### 2b. Default combos (Ball Handle 99, right-hand start)');
p();
p('| Combo | Segments (move @ start–end ms, hand) | Total ms | End hand | End offset (x, z) ft |');
p('|---|---|---|---|---|');
for (const c of DEFAULT_COMBOS) {
  const tl = buildComboTimeline(c, 99, 'R');
  const segs = tl.segments.map((s) => `${s.moveKey} @ ${s.start.toFixed(0)}–${s.end.toFixed(0)} (${s.hand})`).join('; ');
  p(`| ${c.name} | ${segs} | ${tl.totalMs.toFixed(0)} | ${tl.endHand} | (${n2(tl.offset.x)}, ${n2(tl.offset.z)}) |`);
}
p();

process.stdout.write(out.join('\n') + '\n');
