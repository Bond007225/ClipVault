import * as THREE from 'three';
import { mulberry32 } from '../core/math.js';
import { BASELINE_Z, THREE_PT_RADIUS, CORNER_THREE_X, RIM } from '../core/shooting.js';

// Half court in feet. Rim centre is the origin on the floor plane; the court
// runs toward +Z. Lines follow NBA dimensions.

const PX = 20; // canvas pixels per foot
const COURT_W = 50;
const COURT_L = 47;
const HALF_LINE_Z = BASELINE_Z + COURT_L;

function floorCanvas(accent) {
  const c = document.createElement('canvas');
  c.width = COURT_W * PX;
  c.height = COURT_L * PX;
  const ctx = c.getContext('2d');
  const rnd = mulberry32(42);
  // Hardwood planks run baseline to half court.
  const plank = 0.25 * PX;
  for (let x = 0; x < c.width; x += plank) {
    const tone = 180 + rnd() * 30;
    ctx.fillStyle = `rgb(${tone + 30}, ${tone - 10}, ${tone - 70})`;
    ctx.fillRect(x, 0, plank, c.height);
    ctx.fillStyle = 'rgba(60,30,10,0.25)';
    ctx.fillRect(x, 0, 1, c.height);
  }
  const P = (x, z) => [(x + COURT_W / 2) * PX, (z - BASELINE_Z) * PX];

  ctx.fillStyle = accent;
  ctx.globalAlpha = 0.85;
  ctx.fillRect(...P(-8, BASELINE_Z), 16 * PX, 19 * PX); // painted key
  ctx.globalAlpha = 1;

  ctx.strokeStyle = '#ffffff';
  ctx.lineWidth = 0.17 * PX;
  ctx.strokeRect(...P(-8, BASELINE_Z), 16 * PX, 19 * PX);
  const ftZ = BASELINE_Z + 19;
  ctx.beginPath();
  ctx.arc(...P(0, ftZ), 6 * PX, 0, Math.PI * 2);
  ctx.stroke();
  // Restricted area.
  ctx.beginPath();
  ctx.arc(...P(0, 0), 4 * PX, 0, Math.PI);
  ctx.stroke();
  // Three point line.
  const cornerZ = Math.sqrt(THREE_PT_RADIUS ** 2 - CORNER_THREE_X ** 2);
  ctx.beginPath();
  ctx.moveTo(...P(-CORNER_THREE_X, BASELINE_Z));
  ctx.lineTo(...P(-CORNER_THREE_X, cornerZ));
  const a0 = Math.atan2(cornerZ, -CORNER_THREE_X);
  const a1 = Math.atan2(cornerZ, CORNER_THREE_X);
  ctx.arc(...P(0, 0), THREE_PT_RADIUS * PX, a0, a1, true);
  ctx.lineTo(...P(CORNER_THREE_X, BASELINE_Z));
  ctx.stroke();
  // Half court line and circle.
  ctx.beginPath();
  ctx.moveTo(...P(-25, HALF_LINE_Z));
  ctx.lineTo(...P(25, HALF_LINE_Z));
  ctx.stroke();
  ctx.beginPath();
  ctx.arc(...P(0, HALF_LINE_Z), 6 * PX, Math.PI, Math.PI * 2);
  ctx.stroke();
  ctx.strokeRect(2, 2, c.width - 4, c.height - 4);

  ctx.save();
  ctx.translate(...P(0, HALF_LINE_Z - 10));
  ctx.fillStyle = 'rgba(255,255,255,0.35)';
  ctx.font = `900 ${5 * PX}px "Arial Black", Impact, sans-serif`;
  ctx.textAlign = 'center';
  ctx.textBaseline = 'middle';
  ctx.fillText('COURTLIFE', 0, 0);
  ctx.restore();
  return c;
}

export function createCourt(scene, { accent = '#1d428a' } = {}) {
  scene.background = new THREE.Color('#0b0d12');
  scene.fog = new THREE.Fog('#0b0d12', 60, 140);

  const tex = new THREE.CanvasTexture(floorCanvas(accent));
  tex.colorSpace = THREE.SRGBColorSpace;
  tex.anisotropy = 8;
  const floor = new THREE.Mesh(new THREE.PlaneGeometry(COURT_W, COURT_L), new THREE.MeshStandardMaterial({ map: tex, roughness: 0.45 }));
  floor.rotation.x = -Math.PI / 2;
  floor.position.set(0, 0, BASELINE_Z + COURT_L / 2);
  floor.receiveShadow = true;
  scene.add(floor);

  const apron = new THREE.Mesh(new THREE.PlaneGeometry(120, 120), new THREE.MeshStandardMaterial({ color: '#15171d', roughness: 1 }));
  apron.rotation.x = -Math.PI / 2;
  apron.position.y = -0.01;
  apron.receiveShadow = true;
  scene.add(apron);

  scene.add(new THREE.HemisphereLight('#dfe8ff', '#30261c', 0.9));
  const key = new THREE.DirectionalLight('#ffffff', 2.2);
  key.position.set(15, 40, 25);
  key.castShadow = true;
  key.shadow.mapSize.set(2048, 2048);
  Object.assign(key.shadow.camera, { left: -30, right: 30, top: 30, bottom: -30, near: 1, far: 100 });
  scene.add(key);

  return { hoop: createHoop(scene) };
}

function createHoop(scene) {
  const g = new THREE.Group();
  const steel = new THREE.MeshStandardMaterial({ color: '#30343c', metalness: 0.6, roughness: 0.4 });
  const pole = new THREE.Mesh(new THREE.BoxGeometry(0.8, 13, 0.8), steel);
  pole.position.set(0, 6.5, BASELINE_Z - 4);
  pole.castShadow = true;
  g.add(pole);
  const arm = new THREE.Mesh(new THREE.BoxGeometry(0.5, 0.5, 4), steel);
  arm.position.set(0, 11.5, BASELINE_Z - 2);
  g.add(arm);
  const pad = new THREE.Mesh(new THREE.BoxGeometry(2, 6, 1.4), new THREE.MeshStandardMaterial({ color: '#1d428a' }));
  pad.position.set(0, 3, BASELINE_Z - 4);
  g.add(pad);

  const board = new THREE.Mesh(
    new THREE.BoxGeometry(6, 3.5, 0.1),
    new THREE.MeshPhysicalMaterial({ color: '#ffffff', transparent: true, opacity: 0.25, roughness: 0.05, transmission: 0.6 }),
  );
  board.position.set(0, 11.25, -1.25);
  g.add(board);
  const frame = new THREE.LineSegments(new THREE.EdgesGeometry(new THREE.BoxGeometry(6, 3.5, 0.1)), new THREE.LineBasicMaterial({ color: '#ffffff' }));
  frame.position.copy(board.position);
  g.add(frame);
  const square = new THREE.LineSegments(new THREE.EdgesGeometry(new THREE.PlaneGeometry(2, 1.5)), new THREE.LineBasicMaterial({ color: '#ffffff' }));
  square.position.set(0, 10.75, -1.18);
  g.add(square);

  const rim = new THREE.Mesh(new THREE.TorusGeometry(RIM.radius, 0.035, 8, 32), new THREE.MeshStandardMaterial({ color: '#e0471b', metalness: 0.5, roughness: 0.4 }));
  rim.rotation.x = Math.PI / 2;
  rim.position.set(RIM.x, RIM.y, RIM.z);
  g.add(rim);

  const net = new THREE.Mesh(
    new THREE.CylinderGeometry(RIM.radius, RIM.radius * 0.6, 1.5, 12, 4, true),
    new THREE.MeshBasicMaterial({ color: '#ffffff', wireframe: true, transparent: true, opacity: 0.8 }),
  );
  net.position.set(RIM.x, RIM.y - 0.75, RIM.z);
  g.add(net);
  scene.add(g);
  return { group: g, net, rim };
}

/** Clean photo-studio backdrop for the MyPlayer creator. */
export function createStudio(scene) {
  scene.background = new THREE.Color('#101318');
  const floor = new THREE.Mesh(new THREE.CircleGeometry(6, 48), new THREE.MeshStandardMaterial({ color: '#1b2029', roughness: 0.6 }));
  floor.rotation.x = -Math.PI / 2;
  floor.receiveShadow = true;
  scene.add(floor);
  const ring = new THREE.Mesh(new THREE.RingGeometry(2.4, 2.5, 64), new THREE.MeshBasicMaterial({ color: '#ffb000' }));
  ring.rotation.x = -Math.PI / 2;
  ring.position.y = 0.005;
  scene.add(ring);
  scene.add(new THREE.HemisphereLight('#ffffff', '#202020', 1.1));
  const key = new THREE.DirectionalLight('#ffffff', 2.4);
  key.position.set(4, 10, 6);
  key.castShadow = true;
  key.shadow.mapSize.set(1024, 1024);
  Object.assign(key.shadow.camera, { left: -5, right: 5, top: 9, bottom: -1 });
  scene.add(key);
  const rimLight = new THREE.DirectionalLight('#7fb2ff', 1.4);
  rimLight.position.set(-6, 6, -6);
  scene.add(rimLight);
}
