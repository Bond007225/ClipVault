import * as THREE from 'three';
import { rigDimensions, plantedHipHeight } from '../core/locomotion.js';
import { paintSkinCanvas } from './tattoos.js';
import { mulberry32 } from '../core/math.js';

// Builds a fully customized, posable character out of primitives. The whole
// mesh is rebuilt when the look changes (cheap), while poses only touch
// joint rotations every frame.

const JOINTS = ['spine', 'neck', 'lShoulder', 'lElbow', 'lWrist', 'rShoulder', 'rElbow', 'rWrist', 'lHip', 'lKnee', 'lAnkle', 'rHip', 'rKnee', 'rAnkle'];

const mat = (color, opts = {}) => new THREE.MeshStandardMaterial({ color, roughness: 0.65, metalness: 0, ...opts });

function capsule(radius, length, material) {
  const geo = new THREE.CapsuleGeometry(radius, Math.max(0.01, length - radius * 2), 6, 16);
  // Three's capsule spends almost all of v on the end caps, which squashes
  // tattoos into stripes. Remap v linearly along the limb instead.
  const pos = geo.attributes.position;
  const uv = geo.attributes.uv;
  for (let i = 0; i < pos.count; i++) uv.setY(i, (pos.getY(i) + length / 2) / length);
  const mesh = new THREE.Mesh(geo, material);
  mesh.position.y = -length / 2; // hangs down from its joint
  mesh.castShadow = true;
  return mesh;
}

/** Open tube hanging from a joint covering [from..to] fraction of a segment. */
function sleeve(radius, segLen, from, to, material, radiusBottom = radius) {
  const len = segLen * (to - from);
  const geo = new THREE.CylinderGeometry(radius, radiusBottom, len, 18, 1, true);
  const mesh = new THREE.Mesh(geo, material);
  mesh.position.y = -segLen * from - len / 2;
  mesh.castShadow = true;
  return mesh;
}

function canvasTexture(canvas) {
  const tex = new THREE.CanvasTexture(canvas);
  tex.colorSpace = THREE.SRGBColorSpace;
  tex.anisotropy = 4;
  return tex;
}

function jerseyCanvas(player) {
  const { primary, secondary } = player.outfit.jersey;
  const c = document.createElement('canvas');
  c.width = 1024;
  c.height = 512;
  const ctx = c.getContext('2d');
  ctx.fillStyle = primary;
  ctx.fillRect(0, 0, 1024, 512);
  ctx.fillStyle = secondary;
  ctx.fillRect(0, 0, 1024, 26); // collar trim
  ctx.fillRect(0, 486, 1024, 26); // hem trim
  ctx.textAlign = 'center';
  ctx.textBaseline = 'middle';
  const drawNumber = (x, y, size) => {
    ctx.font = `900 ${size}px "Arial Black", Impact, sans-serif`;
    ctx.lineWidth = 10;
    ctx.strokeStyle = secondary;
    ctx.fillStyle = '#ffffff';
    ctx.strokeText(String(player.number), x, y);
    ctx.fillText(String(player.number), x, y);
  };
  // u=0 is the front on a cylinder, so front is at x=0/1024 and back at 512.
  drawNumber(0, 250, 190);
  drawNumber(1024, 250, 190);
  drawNumber(512, 290, 210);
  ctx.font = '800 54px "Arial Black", Impact, sans-serif';
  ctx.fillStyle = secondary;
  ctx.fillText(player.name.toUpperCase().slice(0, 14), 512, 120);
  return c;
}

function shortsCanvas(color, stripe, outerU) {
  const c = document.createElement('canvas');
  c.width = 256;
  c.height = 128;
  const ctx = c.getContext('2d');
  ctx.fillStyle = color;
  ctx.fillRect(0, 0, 256, 128);
  ctx.fillStyle = stripe;
  ctx.fillRect(outerU * 256 - 10, 0, 20, 128);
  ctx.fillRect(0, 116, 256, 12);
  return c;
}

function ballCanvas() {
  const c = document.createElement('canvas');
  c.width = 512;
  c.height = 256;
  const ctx = c.getContext('2d');
  ctx.fillStyle = '#d4651f';
  ctx.fillRect(0, 0, 512, 256);
  const rnd = mulberry32(9);
  for (let i = 0; i < 3000; i++) {
    ctx.fillStyle = `rgba(0,0,0,${rnd() * 0.12})`;
    ctx.fillRect(rnd() * 512, rnd() * 256, 2, 2);
  }
  ctx.strokeStyle = '#1a0d05';
  ctx.lineWidth = 5;
  ctx.beginPath();
  ctx.moveTo(0, 128);
  ctx.lineTo(512, 128);
  for (const x of [128, 384]) {
    ctx.moveTo(x, 0);
    ctx.lineTo(x, 256);
  }
  ctx.stroke();
  for (const x of [0, 256, 512]) {
    ctx.beginPath();
    ctx.ellipse(x, 128, 70, 128, 0, 0, Math.PI * 2);
    ctx.stroke();
  }
  return c;
}

export function createBall() {
  const ball = new THREE.Mesh(
    new THREE.SphereGeometry(0.39, 32, 16),
    new THREE.MeshStandardMaterial({ map: canvasTexture(ballCanvas()), roughness: 0.8 }),
  );
  ball.castShadow = true;
  return ball;
}

export class PlayerRig {
  constructor(player) {
    this.root = new THREE.Group();
    this.joints = {};
    this.disposables = [];
    this.build(player);
  }

  setPlayer(player) {
    this.dispose();
    this.root.clear();
    this.build(player);
  }

  dispose() {
    for (const d of this.disposables) d.dispose();
    this.disposables = [];
    this.root.traverse((o) => {
      if (o.isMesh) o.geometry.dispose();
    });
  }

  track(x) {
    this.disposables.push(x);
    return x;
  }

  skinMaterial(slot, lengthFt, radius) {
    const p = this.player;
    const tattoos = p.tattoos.filter((t) => t.slot === slot);
    if (!tattoos.length) return this.skin;
    const canvas = paintSkinCanvas({ skinTone: p.body.skinTone, tattoos, lengthFt, circumferenceFt: Math.PI * 2 * radius, number: p.number });
    const tex = this.track(canvasTexture(canvas));
    return this.track(mat('#ffffff', { map: tex }));
  }

  build(player) {
    this.player = player;
    const d = (this.dims = rigDimensions(player.body));
    const o = player.outfit;
    const acc = o.accessories;
    this.skin = this.track(mat(player.body.skinTone));
    const jerseyMat = this.track(mat('#ffffff', { map: this.track(canvasTexture(jerseyCanvas(player))) }));
    const jerseySolid = this.track(mat(o.jersey.primary));
    const shortsMat = this.track(mat(o.shorts.color));
    const sockMat = this.track(mat(o.socks.color));
    const armSleeveMat = this.track(mat(acc.armSleeve.color));
    const legSleeveMat = this.track(mat(acc.legSleeve.color));

    const hips = new THREE.Group();
    hips.position.y = d.hipHeight;
    this.root.add(hips);
    this.hips = hips;

    // Pelvis + shorts waist.
    const waist = Math.max(d.girth * 1.3, d.hipHalf + d.H * 0.05);
    const pelvis = new THREE.Mesh(new THREE.CylinderGeometry(waist, waist * 1.04, d.H * 0.12, 20), shortsMat);
    pelvis.position.y = -d.H * 0.03;
    pelvis.scale.z = 0.7;
    pelvis.castShadow = true;
    hips.add(pelvis);

    const spine = this.joint('spine', hips);
    const chestR = d.shoulderHalf * (0.8 + player.body.build * 0.06);
    const torsoGeo = new THREE.CylinderGeometry(chestR, waist * 0.98, d.torso, 24, 1, false);
    const torso = new THREE.Mesh(torsoGeo, [jerseyMat, jerseySolid, jerseySolid]);
    torso.position.y = d.torso / 2;
    torso.scale.z = 0.62 + d.girth * 0.25;
    torso.castShadow = true;
    spine.add(torso);

    const chest = new THREE.Group();
    chest.position.y = d.torso;
    spine.add(chest);

    this.buildHead(chest, d);

    const sleeveLen = { tank: 0, tee: 0.4, sleeved: 0.6 }[o.jersey.style];
    for (const side of ['l', 'r']) {
      const sx = side === 'l' ? 1 : -1;
      const sideName = side === 'l' ? 'left' : 'right';
      const armR = d.H * 0.026 * d.limb;
      const deltoid = new THREE.Mesh(new THREE.SphereGeometry(armR * 1.35, 16, 12), sleeveLen ? jerseySolid : this.skin);
      deltoid.position.set(sx * d.shoulderHalf, -armR * 0.6, 0);
      chest.add(deltoid);

      const shoulder = this.joint(`${side}Shoulder`, chest, sx * d.shoulderHalf, -armR * 0.6, 0);
      shoulder.add(capsule(armR, d.upperArm, this.skinMaterial(`${sideName}UpperArm`, d.upperArm, armR)));
      const hasArmSleeve = acc.armSleeve.side === sideName || acc.armSleeve.side === 'both';
      if (sleeveLen) shoulder.add(sleeve(armR * 1.25, d.upperArm, 0, sleeveLen, jerseySolid, armR * 1.15));
      if (hasArmSleeve) shoulder.add(sleeve(armR * 1.06, d.upperArm, sleeveLen ? sleeveLen - 0.05 : 0.15, 1, armSleeveMat));

      const elbow = this.joint(`${side}Elbow`, shoulder, 0, -d.upperArm, 0);
      const foreR = armR * 0.85;
      elbow.add(capsule(foreR, d.forearm, this.skinMaterial(`${sideName}Forearm`, d.forearm, foreR)));
      if (hasArmSleeve) elbow.add(sleeve(foreR * 1.08, d.forearm, 0, 0.82, armSleeveMat));
      if (acc.wristbands[sideName]) elbow.add(sleeve(foreR * 1.25, d.forearm, 0.72, 0.95, this.track(mat(acc.wristbands.color))));

      const wrist = this.joint(`${side}Wrist`, elbow, 0, -d.forearm, 0);
      const hand = new THREE.Mesh(new THREE.SphereGeometry(d.hand * 0.42, 14, 10), this.skinMaterial(`${sideName}Hand`, d.hand, d.hand * 0.42));
      hand.scale.set(0.75, 1.1, 0.45);
      hand.position.y = -d.hand * 0.45;
      hand.castShadow = true;
      wrist.add(hand);
      const palm = new THREE.Object3D();
      palm.position.set(0, -d.hand * 0.6, d.hand * 0.25);
      wrist.add(palm);
      this.joints[`${side}Palm`] = palm;

      this.buildLeg(hips, side, sx, sideName, d, { shortsMat, sockMat, legSleeveMat });
    }
  }

  buildLeg(hips, side, sx, sideName, d, { shortsMat, sockMat, legSleeveMat }) {
    const o = this.player.outfit;
    const acc = o.accessories;
    const thighR = d.H * 0.042 * d.limb;
    const shinR = thighR * 0.72;
    const hip = this.joint(`${side}Hip`, hips, sx * d.hipHalf, -d.H * 0.04, 0);
    hip.add(capsule(thighR, d.thigh, this.skin));
    const shortLen = { short: 0.45, standard: 0.8, long: 1.05 }[o.shorts.length];
    const shortsLegMat = this.track(mat('#ffffff', { map: this.track(canvasTexture(shortsCanvas(o.shorts.color, o.shorts.stripe, sx > 0 ? 0.25 : 0.75))) }));
    hip.add(sleeve(thighR * 1.45, d.thigh, -0.05, Math.min(1, shortLen), shortsLegMat, thighR * 1.55));
    const hasLegSleeve = acc.legSleeve.side === sideName || acc.legSleeve.side === 'both';
    if (hasLegSleeve) hip.add(sleeve(thighR * 1.05, d.thigh, Math.min(0.95, shortLen), 1, legSleeveMat));

    const knee = this.joint(`${side}Knee`, hip, 0, -d.thigh, 0);
    knee.add(capsule(shinR, d.shin, this.skinMaterial(`${sideName}Calf`, d.shin, shinR)));
    if (shortLen > 1) knee.add(sleeve(thighR * 1.45, d.shin, 0, shortLen - 1 + 0.08, shortsMat));
    const sockLen = { ankle: 0.12, crew: 0.38, high: 0.85 }[o.socks.length];
    knee.add(sleeve(shinR * 1.08, d.shin, 1 - sockLen, 1, sockMat, shinR * 1.06));
    if (hasLegSleeve) knee.add(sleeve(shinR * 1.06, d.shin, 0, 1 - sockLen, legSleeveMat));

    const ankle = this.joint(`${side}Ankle`, knee, 0, -d.shin, 0);
    this.buildShoe(ankle, d);
  }

  buildShoe(ankle, d) {
    const s = this.player.outfit.shoes;
    // The ankle joint sits d.ankle above the floor when standing.
    const len = d.H * 0.16;
    const wid = len * 0.38;
    const soleH = len * 0.1;
    const upperH = d.ankle - soleH + len * 0.08;
    const floor = -d.ankle;
    const sole = new THREE.Mesh(new THREE.BoxGeometry(wid * 1.08, soleH, len * 1.04), this.track(mat(s.sole)));
    sole.position.set(0, floor + soleH / 2, len * 0.25);
    ankle.add(sole);
    const upper = new THREE.Mesh(new THREE.BoxGeometry(wid, upperH, len), this.track(mat(s.primary)));
    upper.position.set(0, floor + soleH + upperH / 2, len * 0.25);
    upper.castShadow = true;
    ankle.add(upper);
    const swoosh = new THREE.Mesh(new THREE.BoxGeometry(wid * 1.04, upperH * 0.25, len * 0.6), this.track(mat(s.accent)));
    swoosh.position.set(0, floor + soleH + upperH * 0.45, len * 0.22);
    swoosh.rotation.x = -0.15;
    ankle.add(swoosh);
    const collarH = { low: 0.12, mid: 0.3, high: 0.5 }[s.model] * len;
    const collar = new THREE.Mesh(new THREE.CylinderGeometry(wid * 0.52, wid * 0.55, collarH, 16), this.track(mat(s.primary)));
    collar.position.y = floor + soleH + upperH + collarH / 2 - len * 0.05;
    ankle.add(collar);
  }

  buildHead(chest, d) {
    const f = this.player.face;
    const neck = this.joint('neck', chest);
    const neckR = d.H * 0.03 * (0.9 + this.player.body.build * 0.25);
    const neckGeo = new THREE.CylinderGeometry(neckR, neckR * 1.1, d.neck * 2, 16);
    const neckMesh = new THREE.Mesh(neckGeo, this.skinMaterial('neck', d.neck * 2, neckR));
    neckMesh.position.y = d.neck * 0.3;
    neck.add(neckMesh);

    const r = d.head / 2;
    const head = new THREE.Group();
    head.position.y = d.neck * 0.9 + r;
    neck.add(head);
    this.headGroup = head;
    const skull = new THREE.Mesh(new THREE.SphereGeometry(r, 28, 20), this.skin);
    skull.scale.set(0.84, 1, 0.95);
    skull.castShadow = true;
    head.add(skull);

    // Face.
    const white = this.track(mat('#f4f1ea'));
    const iris = this.track(mat(f.eyeColor, { roughness: 0.3 }));
    for (const sx of [-1, 1]) {
      const eye = new THREE.Mesh(new THREE.SphereGeometry(r * 0.13, 12, 8), white);
      eye.position.set(sx * r * 0.32, r * 0.1, r * 0.82);
      eye.scale.z = 0.5;
      head.add(eye);
      const pupil = new THREE.Mesh(new THREE.SphereGeometry(r * 0.075, 10, 8), iris);
      pupil.position.set(sx * r * 0.32, r * 0.1, r * 0.88);
      head.add(pupil);
      const brow = new THREE.Mesh(new THREE.BoxGeometry(r * 0.3, r * 0.05, r * 0.06), this.track(mat(f.hairColor)));
      brow.position.set(sx * r * 0.32, r * 0.28, r * 0.85);
      head.add(brow);
      const ear = new THREE.Mesh(new THREE.SphereGeometry(r * 0.2, 10, 8), this.skin);
      ear.scale.set(0.4, 1, 0.7);
      ear.position.set(sx * r * 0.84, r * 0.02, 0);
      head.add(ear);
    }
    const nose = new THREE.Mesh(new THREE.ConeGeometry(r * 0.12, r * 0.3, 8), this.skin);
    nose.position.set(0, -r * 0.08, r * 0.95);
    nose.rotation.x = Math.PI / 2.4;
    head.add(nose);
    const mouth = new THREE.Mesh(new THREE.BoxGeometry(r * 0.35, r * 0.05, r * 0.05), this.track(mat('#4a2020')));
    mouth.position.set(0, -r * 0.42, r * 0.84);
    head.add(mouth);

    this.buildHair(head, r);
    this.buildFacialHair(head, r);

    if (this.player.outfit.accessories.headband.on) {
      const band = new THREE.Mesh(new THREE.TorusGeometry(r * 0.92, r * 0.09, 8, 28), this.track(mat(this.player.outfit.accessories.headband.color)));
      band.rotation.x = Math.PI / 2 - 0.15;
      band.scale.set(0.92, 1.05, 1);
      band.position.y = r * 0.45;
      head.add(band);
    }
  }

  buildHair(head, r) {
    const style = this.player.face.hairStyle;
    if (style === 'bald') return;
    const hm = this.track(mat(this.player.face.hairColor, { roughness: 0.9 }));
    const cap = (scale, thetaLen, y = 0) => {
      const m = new THREE.Mesh(new THREE.SphereGeometry(r, 24, 16, 0, Math.PI * 2, 0, thetaLen), hm);
      m.scale.set(0.84 * scale, scale, 0.95 * scale);
      m.position.y = y;
      m.rotation.x = -0.45; // tilt back so the hairline sits above the brow
      head.add(m);
      return m;
    };
    const rnd = mulberry32(style.length * 131);
    switch (style) {
      case 'buzz':
      case 'waves':
        cap(1.03, Math.PI * 0.5);
        break;
      case 'fade':
        cap(1.02, Math.PI * 0.52);
        cap(1.08, Math.PI * 0.34, r * 0.04);
        break;
      case 'hightop': {
        cap(1.04, Math.PI * 0.5);
        const top = new THREE.Mesh(new THREE.CylinderGeometry(r * 0.78, r * 0.72, r * 0.9, 20), hm);
        top.position.y = r * 1.1;
        head.add(top);
        break;
      }
      case 'afro': {
        const fro = new THREE.Mesh(new THREE.SphereGeometry(r * 1.45, 24, 18), hm);
        fro.position.set(0, r * 0.45, -r * 0.15);
        fro.scale.set(1, 0.92, 0.95);
        head.add(fro);
        break;
      }
      case 'twists':
        cap(1.06, Math.PI * 0.5);
        for (let i = 0; i < 40; i++) {
          const a = rnd() * Math.PI * 2;
          const phi = rnd() * Math.PI * 0.42;
          const t = new THREE.Mesh(new THREE.ConeGeometry(r * 0.09, r * 0.5, 6), hm);
          const n = new THREE.Vector3(Math.sin(phi) * Math.cos(a) * 0.84, Math.cos(phi), Math.sin(phi) * Math.sin(a) * 0.95);
          t.position.copy(n).multiplyScalar(r * 1.1);
          t.quaternion.setFromUnitVectors(new THREE.Vector3(0, 1, 0), n.normalize());
          head.add(t);
        }
        break;
      case 'braids':
        cap(1.02, Math.PI * 0.5);
        for (let i = -3; i <= 3; i++) {
          const row = new THREE.Mesh(new THREE.TorusGeometry(r * 1.03, r * 0.045, 6, 24, Math.PI * 0.95), hm);
          row.rotation.set(0, Math.PI / 2, 0);
          row.position.x = i * r * 0.11;
          row.scale.set(1, 1, 0.84);
          row.rotation.z = 0.05;
          head.add(row);
        }
        break;
      case 'dreads':
        cap(1.05, Math.PI * 0.5);
        for (let i = 0; i < 26; i++) {
          const a = Math.PI * 0.15 + (i / 25) * Math.PI * 1.7; // skip the face
          const len = r * (1.2 + rnd() * 0.8);
          const dread = new THREE.Mesh(new THREE.CylinderGeometry(r * 0.06, r * 0.05, len, 6), hm);
          dread.position.set(Math.sin(a + Math.PI) * r * 0.85, r * 0.2 - len / 2, Math.cos(a + Math.PI) * r * 0.9);
          dread.rotation.z = Math.sin(a + Math.PI) * 0.18;
          dread.rotation.x = -Math.cos(a + Math.PI) * 0.18;
          head.add(dread);
        }
        break;
      case 'mohawk': {
        cap(1.01, Math.PI * 0.5);
        const strip = new THREE.Mesh(new THREE.BoxGeometry(r * 0.32, r * 0.5, r * 1.8), hm);
        strip.position.y = r * 0.95;
        head.add(strip);
        break;
      }
      case 'manbun': {
        cap(1.05, Math.PI * 0.5);
        const bun = new THREE.Mesh(new THREE.SphereGeometry(r * 0.38, 16, 12), hm);
        bun.position.set(0, r * 0.75, -r * 0.7);
        head.add(bun);
        break;
      }
    }
  }

  buildFacialHair(head, r) {
    const style = this.player.face.facialHair;
    if (style === 'none') return;
    const opacity = style === 'stubble' ? 0.45 : 1;
    const fm = this.track(mat(this.player.face.facialHairColor, { roughness: 1, transparent: opacity < 1, opacity }));
    const shell = (scale, thetaStart, thetaLen, phiStart = Math.PI * 0.05, phiLen = Math.PI * 0.9) => {
      const m = new THREE.Mesh(new THREE.SphereGeometry(r, 24, 12, phiStart, phiLen, thetaStart, thetaLen), fm);
      m.scale.set(0.84 * scale, scale, 0.95 * scale);
      head.add(m);
      return m;
    };
    switch (style) {
      case 'stubble':
        shell(1.01, Math.PI * 0.55, Math.PI * 0.35);
        break;
      case 'goatee': {
        const g = new THREE.Mesh(new THREE.BoxGeometry(r * 0.3, r * 0.35, r * 0.15), fm);
        g.position.set(0, -r * 0.7, r * 0.7);
        head.add(g);
        const mus = new THREE.Mesh(new THREE.BoxGeometry(r * 0.42, r * 0.08, r * 0.1), fm);
        mus.position.set(0, -r * 0.32, r * 0.88);
        head.add(mus);
        break;
      }
      case 'chinstrap':
        shell(1.02, Math.PI * 0.68, Math.PI * 0.14);
        break;
      case 'full':
        shell(1.06, Math.PI * 0.55, Math.PI * 0.4);
        break;
      case 'harden': {
        const b = shell(1.12, Math.PI * 0.52, Math.PI * 0.48);
        b.scale.y *= 1.25;
        b.position.y = -r * 0.08;
        break;
      }
    }
  }

  joint(name, parent, x = 0, y = 0, z = 0) {
    const g = new THREE.Group();
    g.position.set(x, y, z);
    parent.add(g);
    this.joints[name] = g;
    return g;
  }

  /** Apply a pose produced by core/jumpshot, core/dribble or core/locomotion. */
  applyPose(pose) {
    const d = this.dims;
    const j = pose.joints ?? {};
    for (const name of JOINTS) this.joints[name]?.rotation.set(0, 0, 0);
    for (const [name, e] of Object.entries(j)) this.joints[name]?.rotation.set(e[0], e[1], e[2]);
    // Keep feet flat unless the pose says otherwise.
    for (const side of ['l', 'r']) {
      if (j[`${side}Ankle`]) continue;
      this.joints[`${side}Ankle`].rotation.x = -((j[`${side}Hip`]?.[0] ?? 0) + (j[`${side}Knee`]?.[0] ?? 0));
    }
    this.hips.position.set(0, plantedHipHeight(d, pose), pose.rootZ ?? 0);
  }

  palmWorld(side, target = new THREE.Vector3()) {
    return this.joints[`${side === 'R' ? 'r' : 'l'}Palm`].getWorldPosition(target);
  }
}
