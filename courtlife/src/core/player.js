import {
  POSITIONS, SKIN_TONES, HAIR_STYLES, FACIAL_HAIR, EYE_COLORS, JERSEY_STYLES, SHORTS_LENGTHS,
  SHOE_MODELS, SOCK_LENGTHS, SLEEVE_SIDES, TATTOO_SLOTS, TATTOO_DESIGNS, MAX_TATTOOS_PER_SLOT,
  MAX_SCRIPT_LENGTH, BODY_LIMITS,
} from './catalog.js';
import { legalizeAttributes } from './attributes.js';
import { normalizeJumpshot, DEFAULT_JUMPSHOT } from './jumpshot.js';
import { normalizeCombos, DEFAULT_COMBOS } from './dribble.js';
import { clamp } from './math.js';

export const SCHEMA_VERSION = 1;

const HEX = /^#[0-9a-f]{6}$/i;
const color = (v, fallback) => (typeof v === 'string' && HEX.test(v) ? v.toLowerCase() : fallback);
const pick = (v, options, fallback) => (Object.prototype.hasOwnProperty.call(options, v) ? v : fallback);
const num = (v, lo, hi, fallback) => (Number.isFinite(v) ? clamp(v, lo, hi) : fallback);
const bool = (v) => v === true;

export const newId = () => `p_${Date.now().toString(36)}_${Math.random().toString(36).slice(2, 7)}`;

export function createDefaultPlayer() {
  return normalizePlayer({
    name: 'Rookie',
    number: 0,
    position: 'PG',
    body: { heightIn: 75, weightLb: 190, wingspanIn: 79, build: 0.5, skinTone: SKIN_TONES[5] },
    face: { hairStyle: 'fade', hairColor: '#141414', facialHair: 'stubble', facialHairColor: '#141414', eyeColor: EYE_COLORS[0] },
    outfit: {
      jersey: { style: 'tank', primary: '#1d428a', secondary: '#ffc72c' },
      shorts: { length: 'standard', color: '#1d428a', stripe: '#ffc72c' },
      shoes: { model: 'low', primary: '#f2f2f2', accent: '#c8102e', sole: '#ffffff' },
      socks: { length: 'crew', color: '#ffffff' },
      accessories: {
        headband: { on: false, color: '#ffffff' },
        armSleeve: { side: 'none', color: '#111111' },
        legSleeve: { side: 'none', color: '#111111' },
        wristbands: { left: false, right: false, color: '#ffffff' },
      },
    },
    tattoos: [],
    jumpshot: DEFAULT_JUMPSHOT,
    combos: DEFAULT_COMBOS,
  });
}

function normalizeTattoos(list) {
  if (!Array.isArray(list)) return [];
  const perSlot = {};
  const out = [];
  for (const t of list) {
    const slot = pick(t?.slot, TATTOO_SLOTS, null);
    const design = pick(t?.design, TATTOO_DESIGNS, null);
    if (!slot || !design) continue;
    perSlot[slot] = (perSlot[slot] ?? 0) + 1;
    if (perSlot[slot] > MAX_TATTOOS_PER_SLOT) continue;
    out.push({
      slot,
      design,
      color: color(t.color, '#111111'),
      accent: color(t.accent, '#8b0000'),
      scale: num(t.scale, 0.4, 1.6, 1),
      offset: num(t.offset, 0, 1, 0.5), // position along the limb
      rotate: num(t.rotate, 0, 1, 0), // wrap around the limb
      text: typeof t.text === 'string' ? t.text.slice(0, MAX_SCRIPT_LENGTH) : '',
    });
  }
  return out;
}

/** Make any (possibly old, hand-edited or shared) player object safe to use. */
export function normalizePlayer(raw = {}) {
  const b = raw.body ?? {};
  const heightIn = Math.round(num(b.heightIn, ...BODY_LIMITS.heightIn, 75));
  const body = {
    heightIn,
    weightLb: Math.round(num(b.weightLb, ...BODY_LIMITS.weightLb, 190)),
    wingspanIn: Math.round(num(b.wingspanIn, heightIn + BODY_LIMITS.wingspanDelta[0], heightIn + BODY_LIMITS.wingspanDelta[1], heightIn + 3)),
    build: num(b.build, 0, 1, 0.5),
    skinTone: color(b.skinTone, SKIN_TONES[5]),
  };
  const f = raw.face ?? {};
  const o = raw.outfit ?? {};
  const acc = o.accessories ?? {};
  return {
    version: SCHEMA_VERSION,
    id: typeof raw.id === 'string' && raw.id ? raw.id : newId(),
    name: (typeof raw.name === 'string' && raw.name.trim() ? raw.name.trim() : 'Rookie').slice(0, 24),
    number: Math.round(num(raw.number, 0, 99, 0)),
    position: POSITIONS.includes(raw.position) ? raw.position : 'PG',
    body,
    face: {
      hairStyle: pick(f.hairStyle, HAIR_STYLES, 'fade'),
      hairColor: color(f.hairColor, '#141414'),
      facialHair: pick(f.facialHair, FACIAL_HAIR, 'none'),
      facialHairColor: color(f.facialHairColor, '#141414'),
      eyeColor: color(f.eyeColor, EYE_COLORS[0]),
    },
    outfit: {
      jersey: {
        style: pick(o.jersey?.style, JERSEY_STYLES, 'tank'),
        primary: color(o.jersey?.primary, '#1d428a'),
        secondary: color(o.jersey?.secondary, '#ffc72c'),
      },
      shorts: {
        length: pick(o.shorts?.length, SHORTS_LENGTHS, 'standard'),
        color: color(o.shorts?.color, '#1d428a'),
        stripe: color(o.shorts?.stripe, '#ffc72c'),
      },
      shoes: {
        model: pick(o.shoes?.model, SHOE_MODELS, 'low'),
        primary: color(o.shoes?.primary, '#f2f2f2'),
        accent: color(o.shoes?.accent, '#c8102e'),
        sole: color(o.shoes?.sole, '#ffffff'),
      },
      socks: { length: pick(o.socks?.length, SOCK_LENGTHS, 'crew'), color: color(o.socks?.color, '#ffffff') },
      accessories: {
        headband: { on: bool(acc.headband?.on), color: color(acc.headband?.color, '#ffffff') },
        armSleeve: { side: pick(acc.armSleeve?.side, SLEEVE_SIDES, 'none'), color: color(acc.armSleeve?.color, '#111111') },
        legSleeve: { side: pick(acc.legSleeve?.side, SLEEVE_SIDES, 'none'), color: color(acc.legSleeve?.color, '#111111') },
        wristbands: { left: bool(acc.wristbands?.left), right: bool(acc.wristbands?.right), color: color(acc.wristbands?.color, '#ffffff') },
      },
    },
    tattoos: normalizeTattoos(raw.tattoos),
    attributes: legalizeAttributes(raw.attributes ?? defaultAttributes(), body),
    jumpshot: normalizeJumpshot(raw.jumpshot),
    combos: normalizeCombos(raw.combos),
  };
}

function defaultAttributes() {
  return {
    closeShot: 70, drivingLayup: 75, drivingDunk: 60, midRange: 72, threePoint: 75, freeThrow: 75,
    ballHandle: 78, speedWithBall: 75, passAccuracy: 72, perimeterDefense: 65, steal: 62, block: 40,
    speed: 76, acceleration: 76, vertical: 70, strength: 50, stamina: 80,
  };
}
