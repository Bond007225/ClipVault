import * as THREE from 'three';
import { OrbitControls } from 'three/examples/jsm/controls/OrbitControls.js';
import { Stage } from '../render/stage.js';
import { PlayerRig, createBall } from '../render/rig.js';
import { createStudio } from '../render/court.js';
import { el, section, slider, select, choiceGrid, colorPicker, toggle, toast, TEAM_COLORS } from './controls.js';
import {
  POSITIONS, SKIN_TONES, HAIR_STYLES, FACIAL_HAIR, EYE_COLORS, JERSEY_STYLES, SHORTS_LENGTHS, SHOE_MODELS,
  SOCK_LENGTHS, SLEEVE_SIDES, TATTOO_SLOTS, TATTOO_DESIGNS, MAX_TATTOOS_PER_SLOT, MAX_SCRIPT_LENGTH, ATTRIBUTES,
  BODY_LIMITS, KEY_BINDINGS, formatHeight,
} from '../core/catalog.js';
import { normalizePlayer } from '../core/player.js';
import { attributeCaps, setAttribute, pointsUsed, ATTRIBUTE_BUDGET, overallRating, archetype } from '../core/attributes.js';
import { SHOT_BASES, SHOT_RELEASES, computeShotProfile, sampleShotPose } from '../core/jumpshot.js';
import { DRIBBLE_MOVES, MAX_COMBO_STEPS, MAX_COMBOS, maxStepSpeed, validateCombo, buildComboTimeline, sampleCombo, MIN_STEP_SPEED } from '../core/dribble.js';
import { idlePose, reachArm, dribbleBallHeight, plantedHipHeight, standTaller } from '../core/locomotion.js';
import { savePlayer, exportBuildCode } from '../core/storage.js';

const TABS = {
  body: 'Body',
  face: 'Face & Hair',
  outfit: 'Outfit',
  tattoos: 'Tattoos',
  attributes: 'Attributes',
  jumpshot: 'Jumpshot',
  dribble: 'Dribble Moves',
};

const HAIR_PRESETS = ['#0d0d0d', '#3b2314', '#6b4423', '#a0522d', '#d9b26f', '#f0e2b6', '#b0b0b0', '#c0392b', '#2e86de', '#8e44ad'];
const INK_PRESETS = ['#111111', '#1f2a44', '#5a0f0f', '#0f3d2e', '#7a5a00', '#4b0f5a'];

export function openCreator(root, startPlayer, { onExit, onPlay }) {
  let player = normalizePlayer(structuredClone(startPlayer));
  let tab = 'body';
  let dirty = false;
  let selectedCombo = 0;
  let previewStart = performance.now();

  const viewport = el('div', { class: 'viewport' });
  const panel = el('div', { class: 'panel-body' });
  const tabBar = el('nav', { class: 'tabs' });
  const badge = el('div', { class: 'badge' });
  const statsBox = el('div', { class: 'preview-stats' });

  const nameInput = el('input', { class: 'name-input', value: player.name, maxLength: 24, placeholder: 'Player name' });
  nameInput.addEventListener('input', () => update((p) => (p.name = nameInput.value), { rebuild: true }));

  const screen = el('div', { class: 'screen creator' },
    el('aside', { class: 'panel' },
      el('header', { class: 'panel-head' },
        el('button', { class: 'ghost', onClick: exit }, '‹ Back'),
        nameInput,
        badge,
      ),
      tabBar,
      panel,
      el('footer', { class: 'panel-foot' },
        el('button', { class: 'ghost', onClick: share }, 'Share Build Code'),
        el('button', { class: 'secondary', onClick: save }, 'Save'),
        el('button', { class: 'primary', onClick: play }, 'Hit the Court ›'),
      ),
    ),
    el('div', { class: 'stage-wrap' }, viewport, statsBox, el('div', { class: 'hint' }, 'Drag to rotate · Scroll to zoom')),
  );
  root.replaceChildren(screen);

  // --- 3D preview -----------------------------------------------------------
  const stage = new Stage(viewport, { fov: 32 });
  createStudio(stage.scene);
  const rig = new PlayerRig(player);
  stage.scene.add(rig.root);
  const ball = createBall();
  stage.scene.add(ball);
  const controls = new OrbitControls(stage.camera, stage.renderer.domElement);
  controls.enableDamping = true;
  controls.enablePan = false;
  controls.minDistance = 2;
  controls.maxDistance = 18;
  stage.camera.position.set(3.5, 5.5, 11);

  let rebuildQueued = false;
  function queueRebuild() {
    if (rebuildQueued) return;
    rebuildQueued = true;
    requestAnimationFrame(() => {
      rebuildQueued = false;
      rig.setPlayer(player);
    });
  }

  function focusCamera() {
    const H = player.body.heightIn / 12;
    const view = { face: [0.92, 3.2], jumpshot: [0.75, H * 2.4 + 3] }[tab] ?? [0.55, H * 1.7 + 2];
    const target = new THREE.Vector3(0, H * view[0], 0);
    controls.target.copy(target);
    const dist = view[1];
    const dir = stage.camera.position.clone().sub(controls.target).setY(0).normalize();
    if (!Number.isFinite(dir.x)) dir.set(0.3, 0, 1).normalize();
    stage.camera.position.copy(target).addScaledVector(dir, dist).setY(target.y + (tab === 'face' ? 0.2 : 1.2));
  }

  const tmp = new THREE.Vector3();
  stage.onFrame = (dt, time) => {
    controls.update();
    const now = performance.now();
    rig.root.position.set(0, 0, 0);
    rig.root.rotation.y = 0;
    if (tab === 'jumpshot') {
      const prof = shotProfile();
      const cycle = prof.durationMs + 700;
      const t = ((now - previewStart) % cycle) / prof.durationMs;
      rig.applyPose(sampleShotPose(prof, Math.min(1, t)));
      rig.root.updateMatrixWorld(true);
      if (t < prof.releaseT) {
        rig.palmWorld('R', ball.position);
        ball.position.y += 0.25;
        ball.position.z += 0.15;
      } else {
        // Ball flies off toward an imaginary rim in front of the player.
        const k = (t - prof.releaseT) * prof.durationMs / 1000;
        ball.position.set(-0.3, prof.releaseHeightFt + k * 14 - 16 * k * k, 0.6 + k * 12);
      }
      ball.visible = ball.position.y > -1;
      return;
    }
    ball.visible = tab === 'dribble' || tab === 'attributes';
    const combo = player.combos[selectedCombo];
    if (tab === 'dribble' && combo) {
      const tl = buildComboTimeline(combo, player.attributes.ballHandle);
      const cycle = tl.totalMs + 500;
      const tm = (now - previewStart) % cycle;
      const s = sampleCombo(tl, Math.min(tm, tl.totalMs));
      if (s) {
        applyDribble(s.ball, s.hand, s.lean, s.rise, time);
        rig.root.rotation.y = s.yaw;
        rig.root.position.set(s.offset.x * 0.5, 0, s.offset.z * 0.5);
        tmp.set(s.ball.x, s.ball.y, s.ball.z).applyEuler(rig.root.rotation).add(rig.root.position);
        ball.position.copy(tmp);
        return;
      }
    }
    if (ball.visible) {
      const y = dribbleBallHeight(time, 1.6, 2.2);
      applyDribble({ x: -0.85, y, z: 0.7 }, 'R', 0, 0, time);
      ball.position.set(-0.85, y, 0.7);
    } else {
      rig.applyPose(idlePose(time));
    }
  };

  function applyDribble(ballPos, hand, lean, rise, time) {
    const pose = idlePose(time);
    standTaller(pose, rise);
    pose.joints.spine = [0.22 + lean, 0, 0];
    const target = { x: ballPos.x, y: Math.max(ballPos.y, 1.4) - plantedHipHeight(rig.dims, pose) + 0.3, z: ballPos.z };
    const arm = reachArm(rig.dims, hand, target);
    const p = hand === 'R' ? 'r' : 'l';
    pose.joints[`${p}Shoulder`] = arm.shoulder;
    pose.joints[`${p}Elbow`] = arm.elbow;
    rig.applyPose(pose);
  }

  const shotProfile = () =>
    computeShotProfile(player.jumpshot, { threePoint: player.attributes.threePoint, vertical: player.attributes.vertical, heightIn: player.body.heightIn });

  // --- State ------------------------------------------------------------------
  function update(mutator, { rebuild = false, rerender = false } = {}) {
    const next = structuredClone(player);
    mutator(next);
    player = normalizePlayer(next);
    dirty = true;
    if (rebuild) queueRebuild();
    refreshHeader();
    if (rerender) renderPanel();
  }

  function refreshHeader() {
    badge.replaceChildren(
      el('strong', {}, overallRating(player.attributes, player.position)),
      el('span', {}, `${player.position} · ${formatHeight(player.body.heightIn)} · ${archetype(player.attributes)}`),
    );
    if (tab === 'jumpshot') {
      const p = shotProfile();
      statsBox.replaceChildren(
        stat('Release', `${p.releaseTimeMs}ms`),
        stat('Green Window', `${p.greenWindowMs}ms`),
        stat('Release Height', `${p.releaseHeightFt.toFixed(1)}ft`),
        stat('Contest Resist', `${Math.round(p.contestResist * 100)}`),
        stat('Rhythm', `${Math.round(p.rhythm * 100)}%`),
      );
      statsBox.hidden = false;
    } else if (tab === 'dribble' && player.combos[selectedCombo]) {
      const tl = buildComboTimeline(player.combos[selectedCombo], player.attributes.ballHandle);
      statsBox.replaceChildren(
        stat('Combo Time', `${Math.round(tl.totalMs)}ms`),
        stat('Ankle Breaker', `${Math.round(tl.effectiveness * 100)}`),
        stat('Max Speed', `${maxStepSpeed(player.attributes.ballHandle).toFixed(2)}x`),
      );
      statsBox.hidden = false;
    } else statsBox.hidden = true;
  }
  const stat = (k, v) => el('div', { class: 'stat' }, el('span', {}, k), el('strong', {}, v));

  function renderTabs() {
    tabBar.replaceChildren(
      ...Object.entries(TABS).map(([k, v]) =>
        el('button', {
          class: k === tab ? 'active' : '',
          onClick: () => {
            tab = k;
            previewStart = performance.now();
            renderTabs();
            renderPanel();
            focusCamera();
          },
        }, v),
      ),
    );
  }

  function renderPanel() {
    panel.replaceChildren(...PANELS[tab]());
    refreshHeader();
  }

  // --- Panels -----------------------------------------------------------------
  const PANELS = {
    body: () => [
      section('Identity',
        select({ label: 'Position', options: Object.fromEntries(POSITIONS.map((p) => [p, p])), value: player.position, onChange: (v) => update((p) => (p.position = v)) }),
        slider({ label: 'Jersey #', min: 0, max: 99, value: player.number, onInput: (v) => update((p) => (p.number = v)), onChange: () => queueRebuild() }),
      ),
      section('Frame',
        slider({
          label: 'Height', min: BODY_LIMITS.heightIn[0], max: BODY_LIMITS.heightIn[1], value: player.body.heightIn, format: formatHeight,
          onInput: (v) => update((p) => {
            const delta = p.body.wingspanIn - p.body.heightIn;
            p.body.heightIn = v;
            p.body.wingspanIn = v + delta;
          }, { rebuild: true }),
          onChange: () => renderPanel(),
        }),
        slider({ label: 'Weight', min: BODY_LIMITS.weightLb[0], max: BODY_LIMITS.weightLb[1], value: player.body.weightLb, format: (v) => `${v} lbs`, onInput: (v) => update((p) => (p.body.weightLb = v), { rebuild: true }) }),
        slider({
          label: 'Wingspan', min: player.body.heightIn + BODY_LIMITS.wingspanDelta[0], max: player.body.heightIn + BODY_LIMITS.wingspanDelta[1],
          value: player.body.wingspanIn, format: formatHeight, onInput: (v) => update((p) => (p.body.wingspanIn = v), { rebuild: true }),
        }),
        slider({ label: 'Muscle', min: 0, max: 100, value: Math.round(player.body.build * 100), format: (v) => (v < 33 ? 'Lean' : v < 66 ? 'Athletic' : 'Muscular'), onInput: (v) => update((p) => (p.body.build = v / 100), { rebuild: true }) }),
        el('p', { class: 'note' }, 'Your frame sets your attribute caps. Taller = better finishing and defense inside, lower handles and speed.'),
      ),
      section('Skin Tone',
        el('div', { class: 'swatches big' }, ...SKIN_TONES.map((c) => el('button', { class: `swatch${c === player.body.skinTone ? ' active' : ''}`, style: { background: c }, onClick: () => update((p) => (p.body.skinTone = c), { rebuild: true, rerender: true }) }))),
        colorPicker({ label: 'Custom', value: player.body.skinTone, onInput: (c) => update((p) => (p.body.skinTone = c), { rebuild: true }) }),
      ),
    ],

    face: () => [
      section('Hair', choiceGrid({ options: HAIR_STYLES, value: player.face.hairStyle, onChange: (v) => update((p) => (p.face.hairStyle = v), { rebuild: true }) }),
        colorPicker({ label: 'Hair Color', value: player.face.hairColor, presets: HAIR_PRESETS, onInput: (c) => update((p) => (p.face.hairColor = c), { rebuild: true }) })),
      section('Facial Hair', choiceGrid({ options: FACIAL_HAIR, value: player.face.facialHair, onChange: (v) => update((p) => (p.face.facialHair = v), { rebuild: true }) }),
        colorPicker({ label: 'Beard Color', value: player.face.facialHairColor, presets: HAIR_PRESETS, onInput: (c) => update((p) => (p.face.facialHairColor = c), { rebuild: true }) })),
      section('Eyes', colorPicker({ label: 'Eye Color', value: player.face.eyeColor, presets: EYE_COLORS, onInput: (c) => update((p) => (p.face.eyeColor = c), { rebuild: true }) })),
    ],

    outfit: () => {
      const o = player.outfit;
      const a = o.accessories;
      const set = (fn) => (v) => update((p) => fn(p.outfit, v), { rebuild: true });
      return [
        section('Jersey',
          choiceGrid({ options: JERSEY_STYLES, value: o.jersey.style, onChange: set((x, v) => (x.jersey.style = v)) }),
          colorPicker({ label: 'Primary', value: o.jersey.primary, presets: TEAM_COLORS, onInput: set((x, v) => (x.jersey.primary = v)) }),
          colorPicker({ label: 'Trim', value: o.jersey.secondary, presets: TEAM_COLORS, onInput: set((x, v) => (x.jersey.secondary = v)) }),
        ),
        section('Shorts',
          choiceGrid({ options: SHORTS_LENGTHS, value: o.shorts.length, onChange: set((x, v) => (x.shorts.length = v)) }),
          colorPicker({ label: 'Color', value: o.shorts.color, presets: TEAM_COLORS, onInput: set((x, v) => (x.shorts.color = v)) }),
          colorPicker({ label: 'Stripe', value: o.shorts.stripe, presets: TEAM_COLORS, onInput: set((x, v) => (x.shorts.stripe = v)) }),
        ),
        section('Shoes',
          choiceGrid({ options: SHOE_MODELS, value: o.shoes.model, onChange: set((x, v) => (x.shoes.model = v)) }),
          colorPicker({ label: 'Upper', value: o.shoes.primary, presets: TEAM_COLORS, onInput: set((x, v) => (x.shoes.primary = v)) }),
          colorPicker({ label: 'Accent', value: o.shoes.accent, presets: TEAM_COLORS, onInput: set((x, v) => (x.shoes.accent = v)) }),
          colorPicker({ label: 'Sole', value: o.shoes.sole, presets: ['#ffffff', '#000000', '#c49a6c', '#e8e1c8'], onInput: set((x, v) => (x.shoes.sole = v)) }),
        ),
        section('Socks',
          choiceGrid({ options: SOCK_LENGTHS, value: o.socks.length, onChange: set((x, v) => (x.socks.length = v)) }),
          colorPicker({ label: 'Color', value: o.socks.color, presets: ['#ffffff', '#000000', ...TEAM_COLORS.slice(0, 4)], onInput: set((x, v) => (x.socks.color = v)) }),
        ),
        section('Accessories',
          toggle({ label: 'Headband', value: a.headband.on, onChange: set((x, v) => (x.accessories.headband.on = v)) }),
          colorPicker({ label: 'Headband Color', value: a.headband.color, presets: TEAM_COLORS, onInput: set((x, v) => (x.accessories.headband.color = v)) }),
          select({ label: 'Arm Sleeve', options: SLEEVE_SIDES, value: a.armSleeve.side, onChange: set((x, v) => (x.accessories.armSleeve.side = v)) }),
          colorPicker({ label: 'Arm Sleeve Color', value: a.armSleeve.color, presets: TEAM_COLORS, onInput: set((x, v) => (x.accessories.armSleeve.color = v)) }),
          select({ label: 'Leg Sleeve', options: SLEEVE_SIDES, value: a.legSleeve.side, onChange: set((x, v) => (x.accessories.legSleeve.side = v)) }),
          colorPicker({ label: 'Leg Sleeve Color', value: a.legSleeve.color, presets: TEAM_COLORS, onInput: set((x, v) => (x.accessories.legSleeve.color = v)) }),
          toggle({ label: 'Left Wristband', value: a.wristbands.left, onChange: set((x, v) => (x.accessories.wristbands.left = v)) }),
          toggle({ label: 'Right Wristband', value: a.wristbands.right, onChange: set((x, v) => (x.accessories.wristbands.right = v)) }),
          colorPicker({ label: 'Wristband Color', value: a.wristbands.color, presets: TEAM_COLORS, onInput: set((x, v) => (x.accessories.wristbands.color = v)) }),
        ),
      ];
    },

    tattoos: () => {
      const list = el('div', { class: 'tattoo-list' });
      player.tattoos.forEach((t, i) => {
        const setT = (fn, opts = { rebuild: true }) => (v) => update((p) => fn(p.tattoos[i], v), opts);
        list.append(
          el('div', { class: 'card' },
            el('div', { class: 'card-head' },
              el('strong', {}, `${TATTOO_DESIGNS[t.design]} · ${TATTOO_SLOTS[t.slot]}`),
              el('button', { class: 'ghost danger', onClick: () => update((p) => p.tattoos.splice(i, 1), { rebuild: true, rerender: true }) }, 'Remove'),
            ),
            select({ label: 'Placement', options: TATTOO_SLOTS, value: t.slot, onChange: (v) => {
              if (player.tattoos.filter((x, j) => j !== i && x.slot === v).length >= MAX_TATTOOS_PER_SLOT) {
                toast(`Max ${MAX_TATTOOS_PER_SLOT} tattoos per spot`, 'error');
                return renderPanel();
              }
              update((p) => (p.tattoos[i].slot = v), { rebuild: true, rerender: true });
            } }),
            select({ label: 'Design', options: TATTOO_DESIGNS, value: t.design, onChange: setT((x, v) => (x.design = v), { rebuild: true, rerender: true }) }),
            ['script', 'number'].includes(t.design)
              ? el('label', { class: 'row' }, el('span', { class: 'label' }, 'Text'),
                el('input', { value: t.text, maxLength: MAX_SCRIPT_LENGTH, placeholder: t.design === 'number' ? String(player.number) : 'Your words', onInput: (e) => update((p) => (p.tattoos[i].text = e.target.value), { rebuild: true }) }))
              : null,
            colorPicker({ label: 'Ink', value: t.color, presets: INK_PRESETS, onInput: setT((x, v) => (x.color = v)) }),
            colorPicker({ label: 'Accent', value: t.accent, presets: ['#8b0000', '#d4af37', '#1e90ff', '#228b22', '#ff69b4'], onInput: setT((x, v) => (x.accent = v)) }),
            slider({ label: 'Size', min: 40, max: 160, value: Math.round(t.scale * 100), format: (v) => `${v}%`, onInput: setT((x, v) => (x.scale = v / 100)) }),
            slider({ label: 'Up / Down', min: 0, max: 100, value: Math.round(t.offset * 100), onInput: setT((x, v) => (x.offset = v / 100)) }),
            slider({ label: 'Rotate Around', min: 0, max: 100, value: Math.round(t.rotate * 100), onInput: setT((x, v) => (x.rotate = v / 100)) }),
          ),
        );
      });
      const freeSlot = Object.keys(TATTOO_SLOTS).find((s) => player.tattoos.filter((t) => t.slot === s).length < MAX_TATTOOS_PER_SLOT);
      return [
        section('Ink Shop',
          el('p', { class: 'note' }, `Stack up to ${MAX_TATTOOS_PER_SLOT} pieces per spot. Write your own script, pick colors, and move or scale every piece. Sleeves cover tattoos, just like real life.`),
          el('button', {
            class: 'primary wide', disabled: !freeSlot,
            onClick: () => update((p) => p.tattoos.push({ slot: freeSlot, design: 'tribal', color: '#111111' }), { rebuild: true, rerender: true }),
          }, '+ Add Tattoo'),
        ),
        list,
      ];
    },

    attributes: () => {
      const caps = attributeCaps(player.body);
      const remaining = el('strong', {}, ATTRIBUTE_BUDGET - pointsUsed(player.attributes));
      const groups = {};
      for (const [key, meta] of Object.entries(ATTRIBUTES)) {
        groups[meta.group] = groups[meta.group] ?? [];
        groups[meta.group].push(
          slider({
            label: meta.label, min: 25, max: 99, value: player.attributes[key], format: (v) => `${v} / ${caps[key]}`,
            onInput: (v) => {
              const allowed = setAttribute(player.attributes, player.body, key, v);
              update((p) => (p.attributes[key] = allowed));
              remaining.textContent = ATTRIBUTE_BUDGET - pointsUsed(player.attributes);
              return allowed;
            },
          }),
        );
      }
      return [
        el('div', { class: 'budget' }, el('span', {}, 'Points left'), remaining),
        ...Object.entries(groups).map(([g, rows]) => section(g, ...rows)),
      ];
    },

    jumpshot: () => {
      const js = player.jumpshot;
      const set = (fn) => (v) => {
        update((p) => fn(p.jumpshot, v));
        previewStart = performance.now();
      };
      return [
        section('Jumpshot Creator',
          el('p', { class: 'note' }, 'Pick a base, blend two releases, and set your speed. The preview is exactly the animation and timing you will shoot with in game. The green window grows with your shooting ratings and shrinks when you blend releases that don\'t share a rhythm.'),
        ),
        section('Base', choiceGrid({ options: mapLabels(SHOT_BASES), value: js.base, onChange: set((x, v) => (x.base = v)) })),
        section('Release 1', choiceGrid({ options: mapLabels(SHOT_RELEASES), value: js.release1, onChange: set((x, v) => (x.release1 = v)) })),
        section('Release 2', choiceGrid({ options: mapLabels(SHOT_RELEASES), value: js.release2, onChange: set((x, v) => (x.release2 = v)) })),
        section('Tuning',
          slider({ label: 'Blend', min: 0, max: 100, value: js.blend, format: (v) => `${100 - v}% / ${v}%`, onInput: set((x, v) => (x.blend = v)) }),
          slider({ label: 'Release Speed', min: 1, max: 5, value: js.speed, format: (v) => ['Very Slow', 'Slow', 'Normal', 'Quick', 'Very Quick'][v - 1], onInput: set((x, v) => (x.speed = v)) }),
        ),
      ];
    },

    dribble: () => {
      const handle = player.attributes.ballHandle;
      const cap = maxStepSpeed(handle);
      const usedKeys = new Set(player.combos.map((c) => c.key));
      const cards = player.combos.map((combo, ci) => {
        const check = validateCombo(combo, handle);
        const setC = (fn, opts = {}) => update((p) => fn(p.combos[ci]), opts);
        const steps = combo.steps.map((step, si) =>
          el('div', { class: 'step' },
            el('span', { class: 'step-n' }, si + 1),
            el('select', { onChange: (e) => setC((c) => (c.steps[si].move = e.target.value), { rerender: true }) },
              ...Object.entries(DRIBBLE_MOVES).map(([k, m]) => el('option', { value: k, selected: k === step.move, disabled: handle < m.minHandle }, handle < m.minHandle ? `🔒 ${m.label} (${m.minHandle})` : m.label))),
            slider({ label: 'Speed', min: MIN_STEP_SPEED, max: 1.5, step: 0.05, value: step.speed, format: (v) => `${v.toFixed(2)}x`,
              onInput: (v) => {
                const allowed = Math.min(v, Math.floor(cap * 20) / 20);
                setC((c) => (c.steps[si].speed = allowed));
                previewStart = performance.now();
                return allowed;
              } }),
            el('button', { class: 'ghost danger icon', title: 'Remove step', disabled: combo.steps.length <= 1, onClick: () => setC((c) => c.steps.splice(si, 1), { rerender: true }) }, '✕'),
          ),
        );
        return el('div', { class: `card${ci === selectedCombo ? ' selected' : ''}`, onClick: (e) => {
          if (ci !== selectedCombo && !e.target.closest('select,input,button')) {
            selectedCombo = ci;
            previewStart = performance.now();
            renderPanel();
          }
        } },
          el('div', { class: 'card-head' },
            el('input', { class: 'combo-name', value: combo.name, maxLength: 20, onInput: (e) => setC((c) => (c.name = e.target.value)) }),
            el('select', { class: 'key-select', title: 'Key binding', onChange: (e) => setC((c) => (c.key = e.target.value), { rerender: true }) },
              ...KEY_BINDINGS.map((k) => el('option', { value: k, selected: k === combo.key, disabled: k !== combo.key && usedKeys.has(k) }, `Key ${k}`))),
            el('button', { class: 'ghost', onClick: () => { selectedCombo = ci; previewStart = performance.now(); renderPanel(); } }, '▶'),
            el('button', { class: 'ghost danger', onClick: () => {
              update((p) => p.combos.splice(ci, 1), { rerender: false });
              selectedCombo = Math.max(0, Math.min(selectedCombo, player.combos.length - 1));
              renderPanel();
            } }, 'Delete'),
          ),
          ...steps,
          combo.steps.length < MAX_COMBO_STEPS
            ? el('button', { class: 'ghost wide', onClick: () => setC((c) => c.steps.push({ move: 'crossover', speed: 1 }), { rerender: true }) }, '+ Add Move')
            : null,
          check.ok ? null : el('ul', { class: 'errors' }, ...check.errors.map((e) => el('li', {}, e))),
        );
      });
      return [
        section('Dribble Creator',
          el('p', { class: 'note' }, `Chain up to ${MAX_COMBO_STEPS} moves, set the speed of each one, and bind the combo to a key. Your Ball Handle (${handle}) caps step speed at ${cap.toFixed(2)}x and unlocks elite moves. Click a combo to preview it.`),
          player.combos.length < MAX_COMBOS
            ? el('button', { class: 'primary wide', onClick: () => {
              update((p) => p.combos.push({ name: `Combo ${p.combos.length + 1}`, key: KEY_BINDINGS.find((k) => !usedKeys.has(k)), steps: [{ move: 'crossover', speed: 1 }] }));
              selectedCombo = player.combos.length - 1;
              renderPanel();
            } }, '+ New Combo')
            : null,
        ),
        ...cards,
      ];
    },
  };

  const mapLabels = (obj) => Object.fromEntries(Object.entries(obj).map(([k, v]) => [k, v.label]));

  // --- Actions ----------------------------------------------------------------
  function save() {
    try {
      player = savePlayer(player);
      dirty = false;
      toast('MyPlayer saved', 'success');
      return true;
    } catch (e) {
      toast(e.message, 'error');
      return false;
    }
  }

  async function share() {
    const code = exportBuildCode(player);
    try {
      await navigator.clipboard.writeText(code);
      toast('Build code copied — share it with the squad');
    } catch {
      window.prompt('Copy your build code:', code);
    }
  }

  function play() {
    if (!save()) return;
    teardown();
    onPlay(player);
  }

  function exit() {
    if (dirty && !window.confirm('Leave without saving your changes?')) return;
    teardown();
    onExit();
  }

  function teardown() {
    controls.dispose();
    rig.dispose();
    stage.dispose();
  }

  renderTabs();
  renderPanel();
  focusCamera();

  return { teardown };
}
