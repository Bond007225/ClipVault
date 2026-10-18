import * as THREE from 'three';
import { Stage } from '../render/stage.js';
import { PlayerRig, createBall } from '../render/rig.js';
import { createCourt } from '../render/court.js';
import { el } from '../ui/controls.js';
import { normalizePlayer } from '../core/player.js';
import { computeShotProfile, sampleShotPose } from '../core/jumpshot.js';
import { buildComboTimeline, sampleCombo } from '../core/dribble.js';
import { idlePose, runPose, reachArm, dribbleBallHeight, plantedHipHeight, standTaller } from '../core/locomotion.js';
import { RIM, gradeRelease, contestLevel, makeProbability, isThree, shotRating, BASELINE_Z } from '../core/shooting.js';
import { lerp, invLerp, clamp, smoothstep } from '../core/math.js';
import { chooseFinish, finishProfile, finishMakeProbability, finishRating, isBlocked, sampleFinishPose } from '../core/finishing.js';
import { createDefender, stepDefender, ankleBreakCheck, startContest } from './defender.js';

const GRAVITY = -32; // ft/s^2
const COURT = { minX: -24.3, maxX: 24.3, minZ: BASELINE_Z + 0.6, maxZ: 41 };

const GRADE_TEXT = {
  green: ['EXCELLENT', 'green'],
  'slightly-early': ['Slightly Early', 'yellow'],
  'slightly-late': ['Slightly Late', 'yellow'],
  early: ['Very Early', 'red'],
  late: ['Very Late', 'red'],
};

function opponent() {
  return normalizePlayer({
    name: 'Lockdown',
    number: 1,
    position: 'SF',
    body: { heightIn: 79, weightLb: 215, wingspanIn: 84, build: 0.6, skinTone: '#5a3218' },
    face: { hairStyle: 'braids', facialHair: 'goatee' },
    outfit: {
      jersey: { style: 'tank', primary: '#c8102e', secondary: '#111111' },
      shorts: { color: '#c8102e', stripe: '#111111' },
      shoes: { model: 'mid', primary: '#111111', accent: '#c8102e', sole: '#111111' },
      accessories: { armSleeve: { side: 'left', color: '#111111' } },
    },
    attributes: { perimeterDefense: 82, steal: 70, block: 60, speed: 78, acceleration: 78, vertical: 72 },
  });
}

export function openGame(root, startPlayer, { onExit }) {
  const me = normalizePlayer(startPlayer);
  const opp = opponent();
  const attrs = me.attributes;
  const profile = computeShotProfile(me.jumpshot, { threePoint: attrs.threePoint, vertical: attrs.vertical, heightIn: me.body.heightIn });
  const comboByKey = Object.fromEntries(me.combos.map((c) => [c.key.toLowerCase(), c]));

  // --- DOM / HUD --------------------------------------------------------------
  const viewport = el('div', { class: 'viewport' });
  const scoreEl = el('div', { class: 'score' });
  const feed = el('div', { class: 'feed' });
  const meterFill = el('div', { class: 'meter-fill' });
  const meterGreen = el('div', { class: 'meter-green' });
  const meter = el('div', { class: 'meter', hidden: true }, meterGreen, meterFill);
  const comboList = el('div', { class: 'combo-hud' },
    ...me.combos.map((c) => el('div', {}, el('kbd', {}, c.key), c.name)),
  );
  const help = el('div', { class: 'help' },
    el('div', {}, el('kbd', {}, 'WASD'), ' move  ', el('kbd', {}, 'Shift'), ' sprint  ', el('kbd', {}, 'Space'), ' hold & release to shoot (near the rim: layup / dunk)'),
    el('div', {}, el('kbd', {}, 'T'), ' toggle defender  ', el('kbd', {}, 'Esc'), ' back to MyPlayer'),
  );
  root.replaceChildren(
    el('div', { class: 'screen game' }, viewport,
      el('div', { class: 'hud' },
        el('div', { class: 'hud-top' }, el('button', { class: 'ghost', onClick: exit }, '‹ Exit'), scoreEl),
        meter, feed, comboList, help,
      ),
    ),
  );

  // --- Scene --------------------------------------------------------------------
  const stage = new Stage(viewport, { fov: 50 });
  const { hoop } = createCourt(stage.scene, { accent: me.outfit.jersey.primary });
  const rig = new PlayerRig(me);
  const defRig = new PlayerRig(opp);
  stage.scene.add(rig.root, defRig.root);
  const ball = createBall();
  stage.scene.add(ball);

  // --- State --------------------------------------------------------------------
  const p = { x: 0, z: 26, vx: 0, vz: 0, yaw: Math.PI, hand: 'R', state: 'dribble', runPhase: 0, comboT: 0, combo: null, comboOrigin: null, shotT: 0, released: false };
  const def = createDefender(opp.attributes, opp.body.heightIn);
  def.x = 0;
  def.z = 20;
  let defenderOn = true;
  const b = { mode: 'held', pos: new THREE.Vector3(), vel: new THREE.Vector3(), t: 0, made: false, hitRim: false, value: 2, settle: 0 };
  const stats = { pts: 0, fgm: 0, fga: 0, tpm: 0, tpa: 0, greens: 0, ankles: 0, dunks: 0 };
  const keys = new Set();

  function onKeyDown(e) {
    const k = e.key.toLowerCase();
    if (e.repeat) return;
    if (k === 'escape') return exit();
    if (k === ' ') {
      e.preventDefault();
      startShot();
      return;
    }
    if (k === 't') {
      defenderOn = !defenderOn;
      defRig.root.visible = defenderOn;
      say(defenderOn ? 'Defender ON' : 'Shootaround mode');
      return;
    }
    if (comboByKey[k] && p.state === 'dribble') startCombo(comboByKey[k]);
    keys.add(k);
  }
  function onKeyUp(e) {
    const k = e.key.toLowerCase();
    if (k === ' ') {
      if (p.state === 'shooting' && !p.released) releaseShot();
    }
    keys.delete(k);
  }
  const onBlur = () => keys.clear();
  window.addEventListener('keydown', onKeyDown);
  window.addEventListener('keyup', onKeyUp);
  window.addEventListener('blur', onBlur);

  // --- Feedback -------------------------------------------------------------------
  function say(text, kind = '') {
    const item = el('div', { class: `feed-item ${kind}` }, text);
    feed.prepend(item);
    setTimeout(() => item.classList.add('fade'), 2200);
    setTimeout(() => item.remove(), 2800);
    while (feed.children.length > 4) feed.lastChild.remove();
  }

  function renderScore() {
    const pct = (m, a) => (a ? `${Math.round((m / a) * 100)}%` : '-');
    scoreEl.replaceChildren(
      el('div', { class: 'pts' }, el('strong', {}, stats.pts), el('span', {}, 'PTS')),
      el('div', {}, el('strong', {}, `${stats.fgm}/${stats.fga}`), el('span', {}, `FG ${pct(stats.fgm, stats.fga)}`)),
      el('div', {}, el('strong', {}, `${stats.tpm}/${stats.tpa}`), el('span', {}, `3PT ${pct(stats.tpm, stats.tpa)}`)),
      el('div', {}, el('strong', {}, stats.greens), el('span', {}, 'GREENS')),
      el('div', {}, el('strong', {}, stats.ankles), el('span', {}, 'ANKLES')),
      el('div', {}, el('strong', {}, stats.dunks), el('span', {}, 'DUNKS')),
    );
  }
  renderScore();

  // --- Actions ----------------------------------------------------------------------
  function startCombo(combo) {
    const tl = buildComboTimeline(combo, attrs.ballHandle, p.hand);
    if (!tl.segments.length) return say(`${combo.name}: moves locked`, 'red');
    p.state = 'combo';
    p.combo = tl;
    p.comboName = combo.name;
    p.comboT = 0;
    p.comboOrigin = { x: p.x, z: p.z, yaw: p.yaw };
  }

  function finishCombo() {
    const tl = p.combo;
    p.hand = tl.endHand;
    p.state = 'dribble';
    p.combo = null;
    if (!defenderOn) return;
    const d = Math.hypot(def.x - p.x, def.z - p.z);
    const stumble = ankleBreakCheck({ effectiveness: tl.effectiveness, ballHandle: attrs.ballHandle, defense: opp.attributes.perimeterDefense, distanceFt: d, roll: Math.random() });
    if (stumble > 0 && def.stumble <= 0) {
      def.stumble = stumble;
      const away = Math.atan2(def.x - p.x, def.z - p.z);
      def.vx = Math.sin(away) * 6;
      def.vz = Math.cos(away) * 6;
      stats.ankles++;
      renderScore();
      say('ANKLES BROKEN!', 'green big');
    }
  }

  function startShot() {
    if (p.state !== 'dribble' && p.state !== 'combo') return;
    const dist = Math.hypot(p.x - RIM.x, p.z - RIM.z);
    const finish = chooseFinish({ distanceFt: dist, speedFtPerSec: Math.hypot(p.vx, p.vz), attrs, heightIn: me.body.heightIn });
    if (p.state === 'combo') p.hand = p.combo.endHand;
    if (finish) return startFinish(finish, dist);
    p.state = 'shooting';
    p.shotT = 0;
    p.released = false;
    p.vx = 0;
    p.vz = 0;
    p.yaw = Math.atan2(RIM.x - p.x, RIM.z - p.z);
    meter.hidden = false;
    const max = profile.releaseTimeMs * 1.5;
    meterGreen.style.bottom = `${((profile.releaseTimeMs - profile.greenWindowMs / 2) / max) * 100}%`;
    meterGreen.style.height = `${(profile.greenWindowMs / max) * 100}%`;
    meter.className = 'meter';
    if (defenderOn) startContest(def, p);
  }

  // Layups and dunks: no meter yet. The finish carries the ball to the rim and
  // resolves at the profile's release time (a timed finish meter can hook in later).
  function startFinish(type, dist) {
    const rating = finishRating(attrs, type, dist);
    const fp = finishProfile(type, { rating, vertical: attrs.vertical, heightIn: me.body.heightIn, distanceFt: dist });
    // Take off toward a spot just in front of the rim, on the line we attacked from.
    const stop = type === 'dunk' ? 1.4 : 2.2;
    const len = dist || 1;
    const to = dist > stop
      ? { x: RIM.x + ((p.x - RIM.x) / len) * stop, z: RIM.z + ((p.z - RIM.z) / len) * stop }
      : { x: p.x, z: p.z };
    p.state = 'finishing';
    p.finish = { type, profile: fp, rating, dist, t: 0, resolved: false, from: { x: p.x, z: p.z }, to };
    p.vx = 0;
    p.vz = 0;
    p.yaw = Math.atan2(RIM.x - p.x, RIM.z - p.z);
    if (defenderOn) startContest(def, p);
  }

  function resolveFinish() {
    const f = p.finish;
    f.resolved = true;
    const fp = f.profile;
    const defDist = defenderOn && def.stumble <= 0 ? Math.hypot(def.x - p.x, def.z - p.z) : null;
    const contest = contestLevel(defDist, opp.body.heightIn, fp.contestResist);
    const chance = finishMakeProbability({ type: f.type, rating: f.rating, contest, distanceFt: f.dist });
    const made = Math.random() < chance;
    const blocked = isBlocked(made, contest);
    const name = f.type === 'dunk' ? 'Dunk' : 'Layup';
    say(`${name} · ${Math.round(chance * 100)}% · ${contest > 0.6 ? 'Smothered' : contest > 0.3 ? 'Contested' : 'Open'}`, made ? 'green' : 'yellow');

    rig.root.updateMatrixWorld(true);
    rig.palmWorld('R', b.pos);
    b.t = 0;
    b.made = made;
    b.value = 2;
    b.three = false;
    b.finish = f.type;
    stats.fga++;
    renderScore();
    if (blocked) {
      // Swatted: send it away from the rim, back toward the floor.
      const away = Math.atan2(p.x - RIM.x, p.z - RIM.z) + (Math.random() - 0.5) * 1.2;
      b.mode = 'loose';
      b.settle = 0;
      b.vel.set(Math.sin(away) * 14, 3 + Math.random() * 3, Math.cos(away) * 14);
      say('BLOCKED!', 'red big');
      return;
    }
    const target = new THREE.Vector3(RIM.x, RIM.y + (f.type === 'dunk' ? 0.4 : 0.15), RIM.z);
    if (!made) {
      const a = Math.random() * Math.PI * 2;
      target.x += Math.cos(a) * RIM.radius * 0.95;
      target.z += Math.sin(a) * RIM.radius * 0.95;
      target.y = RIM.y + 0.1;
    }
    // Dunks are thrown straight through; layups get a soft little arc.
    const T = f.type === 'dunk' ? 0.14 : 0.45;
    b.mode = 'flight';
    b.flightT = T;
    b.vel.set((target.x - b.pos.x) / T, (target.y - b.pos.y - 0.5 * GRAVITY * T * T) / T, (target.z - b.pos.z) / T);
  }

  function releaseShot() {
    p.released = true;
    const heldMs = p.shotT * 1000;
    const { grade } = gradeRelease(profile, heldMs);
    const dist = Math.hypot(p.x - RIM.x, p.z - RIM.z);
    const three = isThree(p.x, p.z);
    const defDist = defenderOn && def.stumble <= 0 ? Math.hypot(def.x - p.x, def.z - p.z) : null;
    const contest = contestLevel(defDist, opp.body.heightIn, profile.contestResist);
    const chance = makeProbability({ grade, rating: shotRating(attrs, dist, three), distanceFt: dist, contest });
    const made = Math.random() < chance;
    const [label, color] = GRADE_TEXT[grade];
    meter.className = `meter ${color}`;
    setTimeout(() => (meter.hidden = true), 700);
    say(`${label} · ${Math.round(chance * 100)}% · ${contest > 0.6 ? 'Smothered' : contest > 0.3 ? 'Contested' : 'Open'}`, color);
    if (grade === 'green') stats.greens++;

    rig.root.updateMatrixWorld(true);
    rig.palmWorld('R', b.pos);
    b.pos.y += 0.2;
    b.mode = 'flight';
    b.t = 0;
    b.made = made;
    b.value = three ? 3 : 2;
    b.three = three;
    b.finish = null;
    // Misses aim at a point on the rim, makes at the centre (a touch high).
    const target = new THREE.Vector3(RIM.x, RIM.y + 0.15, RIM.z);
    if (!made) {
      const a = Math.random() * Math.PI * 2;
      target.x += Math.cos(a) * RIM.radius * 0.95;
      target.z += Math.sin(a) * RIM.radius * 0.95;
      target.y = RIM.y + 0.1;
    }
    const T = 0.75 + dist * 0.028;
    b.flightT = T;
    b.vel.set((target.x - b.pos.x) / T, (target.y - b.pos.y - 0.5 * GRAVITY * T * T) / T, (target.z - b.pos.z) / T);
    stats.fga++;
    if (three) stats.tpa++;
    renderScore();
  }

  function scoreBasket() {
    stats.pts += b.value;
    stats.fgm++;
    if (b.three) stats.tpm++;
    if (b.finish === 'dunk') stats.dunks++;
    renderScore();
    if (b.finish === 'dunk') say('DUNK! +2', 'green big');
    else if (b.finish === 'layup') say('Layup +2', 'green');
    else say(b.value === 3 ? 'SPLASH! +3' : 'BUCKET +2', 'green');
    hoop.net.scale.set(1, 1.25, 1);
  }

  function giveBall() {
    b.mode = 'held';
    p.state = 'dribble';
  }

  // --- Simulation -----------------------------------------------------------------------
  const camPos = new THREE.Vector3(0, 9, 40);
  const camLook = new THREE.Vector3();
  const tmpV = new THREE.Vector3();

  function inputVector() {
    // Camera sits behind the player looking at the rim, so "up" means toward the rim.
    const toRim = Math.atan2(RIM.x - p.x, RIM.z - p.z);
    let f = 0;
    let s = 0;
    if (keys.has('w') || keys.has('arrowup')) f += 1;
    if (keys.has('s') || keys.has('arrowdown')) f -= 1;
    if (keys.has('a') || keys.has('arrowleft')) s -= 1;
    if (keys.has('d') || keys.has('arrowright')) s += 1;
    const len = Math.hypot(f, s);
    if (!len) return { x: 0, z: 0 };
    f /= len;
    s /= len;
    // Right of the camera view is -X when facing +Z.
    return {
      x: Math.sin(toRim) * f - Math.cos(toRim) * s,
      z: Math.cos(toRim) * f + Math.sin(toRim) * s,
    };
  }

  function stepPlayer(dt, time) {
    if (p.state === 'combo') {
      p.comboT += dt * 1000;
      const s = sampleCombo(p.combo, Math.min(p.comboT, p.combo.totalMs));
      const o = p.comboOrigin;
      const cos = Math.cos(o.yaw);
      const sin = Math.sin(o.yaw);
      p.x = o.x + s.offset.x * cos + s.offset.z * sin;
      p.z = o.z - s.offset.x * sin + s.offset.z * cos;
      p.yaw = o.yaw + s.yaw;
      p.sample = s;
      if (s.done) finishCombo();
    } else if (p.state === 'shooting') {
      p.shotT += dt;
      if (!p.released && p.shotT * 1000 >= profile.durationMs * 0.95) releaseShot();
      if (p.shotT * 1000 >= profile.durationMs) p.state = b.mode === 'held' ? 'dribble' : 'noball';
    } else if (p.state === 'finishing') {
      const f = p.finish;
      f.t += dt * 1000;
      const pose = sampleFinishPose(f.profile, f.t / f.profile.durationMs);
      const k = smoothstep(pose.travel);
      p.x = lerp(f.from.x, f.to.x, k);
      p.z = lerp(f.from.z, f.to.z, k);
      p.finishPose = pose;
      if (!f.resolved && f.t >= f.profile.releaseTimeMs) resolveFinish();
      if (f.t >= f.profile.durationMs) p.state = b.mode === 'held' ? 'dribble' : 'noball';
    } else {
      const inp = inputVector();
      const sprint = keys.has('shift');
      const top = lerp(8, 14, invLerp(40, 99, attrs.speedWithBall)) * (sprint ? 1.35 : 1);
      const accel = lerp(25, 55, invLerp(40, 99, attrs.acceleration));
      const k = 1 - Math.exp(-accel / top * dt);
      p.vx += (inp.x * top - p.vx) * k;
      p.vz += (inp.z * top - p.vz) * k;
      p.x += p.vx * dt;
      p.z += p.vz * dt;
      const speed = Math.hypot(p.vx, p.vz);
      p.runPhase += dt * (4 + speed * 0.9);
      // With the ball you square up to the rim; without it, face where you run.
      const want = p.state === 'dribble' || speed < 1 ? Math.atan2(RIM.x - p.x, RIM.z - p.z) : Math.atan2(p.vx, p.vz);
      let dy = want - p.yaw;
      dy = Math.atan2(Math.sin(dy), Math.cos(dy));
      p.yaw += dy * Math.min(1, dt * 10);
      p.speed = speed;
    }
    p.x = clamp(p.x, COURT.minX, COURT.maxX);
    p.z = clamp(p.z, COURT.minZ, COURT.maxZ);
    // The defender holds their ground unless they're on the floor.
    if (defenderOn && def.stumble <= 0 && p.state !== 'finishing') {
      const dx = p.x - def.x;
      const dz = p.z - def.z;
      const d = Math.hypot(dx, dz);
      if (d < 2 && d > 0.001) {
        p.x = def.x + (dx / d) * 2;
        p.z = def.z + (dz / d) * 2;
      }
    }
    animatePlayer(time);
  }

  function holdBall(localBall, hand, pose) {
    const target = { x: localBall.x, y: Math.max(localBall.y, 1.4) - plantedHipHeight(rig.dims, pose) + 0.3, z: localBall.z };
    const arm = reachArm(rig.dims, hand, target);
    const side = hand === 'R' ? 'r' : 'l';
    pose.joints[`${side}Shoulder`] = arm.shoulder;
    pose.joints[`${side}Elbow`] = arm.elbow;
  }

  function animatePlayer(time) {
    rig.root.position.set(p.x, 0, p.z);
    rig.root.rotation.y = p.yaw;
    let localBall = null;
    if (p.state === 'combo') {
      const s = p.sample;
      const pose = idlePose(time);
      standTaller(pose, s.rise);
      pose.joints.spine = [0.25 + s.lean, 0, 0];
      holdBall(s.ball, s.hand, pose);
      rig.applyPose(pose);
      localBall = s.ball;
    } else if (p.state === 'shooting') {
      rig.applyPose(sampleShotPose(profile, p.shotT * 1000 / profile.durationMs));
    } else if (p.state === 'finishing') {
      rig.applyPose(p.finishPose);
    } else {
      const moving = (p.speed ?? 0) > 1.2;
      const pose = moving ? runPose(p.runPhase, invLerp(4, 16, p.speed)) : idlePose(time);
      if (p.state === 'dribble') {
        const side = p.hand === 'R' ? -1 : 1;
        localBall = { x: side * 0.85, y: dribbleBallHeight(time, moving ? 2.2 : 1.6, moving ? 2.6 : 2.2), z: moving ? 1.1 : 0.7 };
        holdBall(localBall, p.hand, pose);
      }
      rig.applyPose(pose);
    }
    if (b.mode === 'held') {
      if (p.state === 'shooting' || p.state === 'finishing') {
        rig.root.updateMatrixWorld(true);
        rig.palmWorld('R', ball.position);
        ball.position.y += 0.2;
      } else if (localBall) {
        tmpV.set(localBall.x, localBall.y, localBall.z).applyAxisAngle(THREE.Object3D.DEFAULT_UP, p.yaw);
        ball.position.set(p.x + tmpV.x, tmpV.y, p.z + tmpV.z);
      }
    }
  }

  function stepBall(dt) {
    if (b.mode === 'held') return;
    b.t += dt;
    const prevY = b.pos.y;
    b.vel.y += GRAVITY * dt;
    b.pos.addScaledVector(b.vel, dt);
    if (b.mode === 'flight' && b.t >= b.flightT) {
      if (b.made) {
        b.mode = 'through';
        b.pos.set(RIM.x, RIM.y, RIM.z);
        b.vel.set(0, -6, 0);
        scoreBasket();
      } else {
        b.mode = 'loose';
        // Clank: kick away from the rim centre and up.
        const out = new THREE.Vector3(b.pos.x - RIM.x, 0, b.pos.z - RIM.z).normalize();
        b.vel.set(out.x * (6 + Math.random() * 6), 6 + Math.random() * 6, out.z * (6 + Math.random() * 6) + 2);
        say(b.finish === 'dunk' ? 'Rimmed out!' : b.finish === 'layup' ? 'Missed layup' : 'Off the rim', 'red');
      }
      b.settle = 0;
    }
    // Backboard.
    if (b.pos.z < -1.25 + 0.39 && b.vel.z < 0 && Math.abs(b.pos.x) < 3 && b.pos.y > 9.5 && b.pos.y < 13) {
      b.vel.z *= -0.6;
      b.pos.z = -1.25 + 0.39;
    }
    if (b.pos.y < 0.39 && b.vel.y < 0) {
      b.pos.y = 0.39;
      b.vel.y *= -0.62;
      b.vel.x *= 0.85;
      b.vel.z *= 0.85;
      if (prevY > 0.39 && Math.abs(b.vel.y) < 1.5) b.vel.y = 0;
    }
    if (b.mode !== 'flight') {
      b.settle += dt;
      const d = Math.hypot(b.pos.x - p.x, b.pos.z - p.z);
      if (p.state !== 'shooting' && p.state !== 'finishing' && ((d < 3 && b.pos.y < 6) || b.settle > (b.mode === 'through' ? 1.6 : 3.5))) giveBall();
    }
    ball.position.copy(b.pos);
  }

  function animateDefender(time) {
    defRig.root.position.set(def.x, 0, def.z);
    defRig.root.rotation.y = Math.atan2(p.x - def.x, p.z - def.z);
    const speed = Math.hypot(def.vx, def.vz);
    let pose;
    if (def.stumble > 0) {
      pose = idlePose(time);
      pose.joints.lHip = [-1.3, 0, 0.3];
      pose.joints.rHip = [-1.0, 0, -0.3];
      pose.joints.spine = [-0.5, 0, 0.2];
      pose.joints.lShoulder = [-1.2, 0, 1.0];
      pose.joints.rShoulder = [-1.2, 0, -1.0];
      pose.joints.lKnee = [1.6, 0, 0];
      pose.joints.rKnee = [1.2, 0, 0];
    } else if (def.contest > 0) {
      const jump = Math.sin((1 - def.contest / 0.8) * Math.PI) * lerp(1, 2.4, invLerp(40, 99, opp.attributes.vertical));
      pose = idlePose(time);
      pose.rootY = jump;
      pose.joints.lShoulder = [-2.9, 0, 0.2];
      pose.joints.rShoulder = [-2.9, 0, -0.2];
      pose.joints.lElbow = [-0.2, 0, 0];
      pose.joints.rElbow = [-0.2, 0, 0];
      pose.joints.lKnee = [0.2, 0, 0];
      pose.joints.rKnee = [0.2, 0, 0];
    } else {
      pose = speed > 2 ? runPose(time * (4 + speed), 0.3) : idlePose(time);
      // Low, wide defensive stance.
      pose.joints.lHip = [-0.7, 0, 0.35];
      pose.joints.rHip = [-0.7, 0, -0.35];
      pose.joints.lKnee = [1.0, 0, 0];
      pose.joints.rKnee = [1.0, 0, 0];
      pose.joints.lShoulder = [-0.6, 0, 0.9];
      pose.joints.rShoulder = [-0.6, 0, -0.9];
      pose.joints.lElbow = [-0.6, 0, 0];
      pose.joints.rElbow = [-0.6, 0, 0];
    }
    defRig.applyPose(pose);
  }

  function stepCamera(dt) {
    const toRimX = RIM.x - p.x;
    const toRimZ = RIM.z - p.z;
    const len = Math.hypot(toRimX, toRimZ) || 1;
    const back = 17;
    tmpV.set(p.x - (toRimX / len) * back, 10.5, p.z - (toRimZ / len) * back);
    tmpV.z = Math.min(tmpV.z, 56);
    const k = 1 - Math.exp(-4 * dt);
    camPos.lerp(tmpV, k);
    const look = new THREE.Vector3(lerp(p.x, RIM.x, 0.4), 5, lerp(p.z, RIM.z, 0.4));
    camLook.lerp(look, k);
    stage.camera.position.copy(camPos);
    stage.camera.lookAt(camLook);
  }

  stage.onFrame = (dt, time) => {
    stepPlayer(dt, time);
    if (defenderOn) {
      stepDefender(def, p, RIM, dt);
      def.x = clamp(def.x, COURT.minX, COURT.maxX);
      def.z = clamp(def.z, COURT.minZ, COURT.maxZ);
      animateDefender(time);
    }
    stepBall(dt);
    hoop.net.scale.y += (1 - hoop.net.scale.y) * Math.min(1, dt * 6);
    if (p.state === 'shooting' && !p.released) {
      const max = profile.releaseTimeMs * 1.5;
      meterFill.style.height = `${clamp((p.shotT * 1000) / max, 0, 1) * 100}%`;
    }
    stepCamera(dt);
  };
  camPos.set(0, 9, 39);
  say('Welcome to the court. Hold Space to shoot.');

  function exit() {
    window.removeEventListener('keydown', onKeyDown);
    window.removeEventListener('keyup', onKeyUp);
    window.removeEventListener('blur', onBlur);
    rig.dispose();
    defRig.dispose();
    stage.dispose();
    onExit();
  }

  return { exit };
}
