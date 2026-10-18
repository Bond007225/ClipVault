import './styles.css';
import { openMenu } from './ui/menu.js';
import { openCreator } from './ui/creator.js';
import { openGame } from './game/game.js';
import { createDefaultPlayer } from './core/player.js';

const root = document.getElementById('app');

function menu() {
  openMenu(root, {
    onCreate: () => creator(createDefaultPlayer()),
    onEdit: (p) => creator(p),
    onPlay: (p) => game(p),
  });
}

function creator(player) {
  openCreator(root, player, { onExit: menu, onPlay: game });
}

function game(player) {
  openGame(root, player, { onExit: () => creator(player) });
}

menu();
