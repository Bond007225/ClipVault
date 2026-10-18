import { el, toast } from './controls.js';
import { loadPlayers, deletePlayer, importBuildCode, savePlayer, MAX_SLOTS } from '../core/storage.js';
import { overallRating, archetype } from '../core/attributes.js';
import { formatHeight } from '../core/catalog.js';

export function openMenu(root, { onCreate, onEdit, onPlay }) {
  const players = loadPlayers();
  const rerender = () => openMenu(root, { onCreate, onEdit, onPlay });

  const importCode = () => {
    const code = window.prompt('Paste a CourtLife build code:');
    if (!code) return;
    try {
      savePlayer(importBuildCode(code));
      toast('Build imported', 'success');
      rerender();
    } catch (e) {
      toast(e.message, 'error');
    }
  };

  const cards = players.map((p) =>
    el('div', { class: 'player-card', style: { '--accent': p.outfit.jersey.primary, '--trim': p.outfit.jersey.secondary } },
      el('div', { class: 'ovr' }, overallRating(p.attributes, p.position)),
      el('div', { class: 'info' },
        el('h2', {}, p.name, el('span', { class: 'num' }, `#${p.number}`)),
        el('p', {}, `${p.position} · ${formatHeight(p.body.heightIn)} · ${p.body.weightLb} lbs`),
        el('p', { class: 'arch' }, archetype(p.attributes)),
      ),
      el('div', { class: 'actions' },
        el('button', { class: 'primary', onClick: () => onPlay(p) }, 'Play'),
        el('button', { class: 'secondary', onClick: () => onEdit(p) }, 'Edit'),
        el('button', { class: 'ghost danger', onClick: () => {
          if (!window.confirm(`Delete ${p.name}? This can't be undone.`)) return;
          deletePlayer(p.id);
          rerender();
        } }, 'Delete'),
      ),
    ),
  );

  root.replaceChildren(
    el('div', { class: 'screen menu' },
      el('header', { class: 'hero' },
        el('h1', {}, 'COURT', el('span', {}, 'LIFE')),
        el('p', {}, 'Your player. Your jumper. Your bag. Built your way.'),
      ),
      el('div', { class: 'menu-actions' },
        el('button', { class: 'primary big', disabled: players.length >= MAX_SLOTS, onClick: onCreate }, '+ Create MyPlayer'),
        el('button', { class: 'secondary big', onClick: importCode }, 'Import Build Code'),
      ),
      players.length
        ? el('div', { class: 'player-grid' }, ...cards)
        : el('p', { class: 'empty' }, 'No MyPlayers yet. Create one to get started.'),
    ),
  );
}
