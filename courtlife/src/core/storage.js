import { normalizePlayer, newId } from './player.js';

const KEY = 'courtlife.players.v1';
export const MAX_SLOTS = 10;

// Storage access is wrapped because private windows can throw on access.
function readRaw(store) {
  try {
    const parsed = JSON.parse(store.getItem(KEY) ?? '[]');
    return Array.isArray(parsed) ? parsed : [];
  } catch {
    return [];
  }
}

export function loadPlayers(store = globalThis.localStorage) {
  if (!store) return [];
  return readRaw(store).map((p) => normalizePlayer(p));
}

export function savePlayer(player, store = globalThis.localStorage) {
  const clean = normalizePlayer(player);
  if (!store) return clean;
  const list = readRaw(store);
  const i = list.findIndex((p) => p.id === clean.id);
  if (i >= 0) list[i] = clean;
  else if (list.length < MAX_SLOTS) list.push(clean);
  else throw new Error(`You can only keep ${MAX_SLOTS} MyPlayers. Delete one first.`);
  try {
    store.setItem(KEY, JSON.stringify(list));
  } catch {
    throw new Error('Could not save: browser storage is unavailable or full.');
  }
  return clean;
}

export function deletePlayer(id, store = globalThis.localStorage) {
  if (!store) return;
  const list = readRaw(store).filter((p) => p.id !== id);
  try {
    store.setItem(KEY, JSON.stringify(list));
  } catch {
    /* nothing to recover */
  }
}

// Build codes let the community share full MyPlayers (looks, jumper, combos).
const toBase64 = (s) => btoa(String.fromCharCode(...new TextEncoder().encode(s)));
const fromBase64 = (s) => new TextDecoder().decode(Uint8Array.from(atob(s), (c) => c.charCodeAt(0)));

export function exportBuildCode(player) {
  const { id, ...rest } = normalizePlayer(player);
  return `CL1.${toBase64(JSON.stringify(rest))}`;
}

export function importBuildCode(code) {
  const trimmed = String(code ?? '').trim();
  if (!trimmed.startsWith('CL1.')) throw new Error('That is not a CourtLife build code.');
  let data;
  try {
    data = JSON.parse(fromBase64(trimmed.slice(4)));
  } catch {
    throw new Error('Build code is damaged or incomplete.');
  }
  return normalizePlayer({ ...data, id: newId() });
}
