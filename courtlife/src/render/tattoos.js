import { mulberry32 } from '../core/math.js';

// Paints tattoos onto skin textures. Each tattooable body part gets its own
// canvas mapped around the limb: x = around the limb (0 = front), y = down
// the limb from the joint. Drawing is done in "length pixels" with an x
// scale applied so designs keep their proportions on thin or thick limbs.

const SIZE = 512;

export function paintSkinCanvas({ skinTone, tattoos, lengthFt, circumferenceFt, number }) {
  const canvas = document.createElement('canvas');
  canvas.width = SIZE;
  canvas.height = SIZE;
  const ctx = canvas.getContext('2d');
  ctx.fillStyle = skinTone;
  ctx.fillRect(0, 0, SIZE, SIZE);
  if (!tattoos.length) return canvas;

  const pxPerFt = SIZE / lengthFt;
  const xScale = lengthFt / circumferenceFt; // squash x so 1ft around == 1ft along
  const width = SIZE / xScale; // canvas width in length-pixels

  tattoos.forEach((t, i) => {
    ctx.save();
    ctx.scale(xScale, 1);
    const size = 0.42 * t.scale * pxPerFt;
    const cy = 0.12 * SIZE + t.offset * 0.76 * SIZE;
    const cx = t.rotate * width;
    const draw = DESIGNS[t.design];
    // Draw three times so designs wrap seamlessly around the limb.
    for (const shift of [-width, 0, width]) {
      ctx.save();
      ctx.translate(cx + shift, cy);
      ctx.globalAlpha = 0.88;
      draw(ctx, size, t, { width, height: SIZE, cy, seed: i * 7919 + 1, number });
      ctx.restore();
    }
    ctx.restore();
  });
  return canvas;
}

function star(ctx, r) {
  ctx.beginPath();
  for (let i = 0; i < 10; i++) {
    const a = (i / 10) * Math.PI * 2 - Math.PI / 2;
    const rr = i % 2 ? r * 0.45 : r;
    ctx.lineTo(Math.cos(a) * rr, Math.sin(a) * rr);
  }
  ctx.closePath();
}

const DESIGNS = {
  tribal(ctx, s, t) {
    ctx.fillStyle = t.color;
    for (const dir of [-1, 1]) {
      ctx.beginPath();
      ctx.moveTo(0, -s * 0.6);
      ctx.bezierCurveTo(dir * s * 0.7, -s * 0.4, dir * s * 0.2, s * 0.1, dir * s * 0.9, s * 0.6);
      ctx.bezierCurveTo(dir * s * 0.1, s * 0.3, dir * s * 0.35, -s * 0.1, 0, -s * 0.1);
      ctx.fill();
    }
    ctx.beginPath();
    ctx.moveTo(-s * 0.15, -s * 0.1);
    ctx.lineTo(0, s * 0.7);
    ctx.lineTo(s * 0.15, -s * 0.1);
    ctx.fill();
  },
  band(ctx, s, t, { width }) {
    // A band wraps the whole limb, ignoring rotation.
    ctx.strokeStyle = t.color;
    ctx.lineWidth = s * 0.08;
    ctx.beginPath();
    for (let x = -width; x <= width; x += s * 0.25) {
      ctx.lineTo(x, Math.sin(x / (s * 0.12)) * s * 0.08);
    }
    ctx.stroke();
    ctx.beginPath();
    for (let x = -width; x <= width; x += s * 0.25) {
      ctx.lineTo(x, -Math.sin(x / (s * 0.12)) * s * 0.08);
    }
    ctx.stroke();
    for (let x = -width; x <= width; x += s * 0.5) {
      ctx.beginPath();
      ctx.moveTo(x - s * 0.08, -s * 0.12);
      ctx.lineTo(x + s * 0.08, s * 0.12);
      ctx.stroke();
    }
  },
  rose(ctx, s, t) {
    ctx.strokeStyle = t.color;
    ctx.lineWidth = s * 0.05;
    ctx.fillStyle = '#2f5d2f';
    ctx.beginPath();
    ctx.moveTo(0, s * 0.1);
    ctx.quadraticCurveTo(s * 0.1, s * 0.5, 0, s * 0.85);
    ctx.stroke();
    for (const dir of [-1, 1]) {
      ctx.beginPath();
      ctx.ellipse(dir * s * 0.18, s * 0.5, s * 0.16, s * 0.07, dir * 0.6, 0, Math.PI * 2);
      ctx.fill();
      ctx.stroke();
    }
    ctx.fillStyle = t.accent;
    for (let i = 0; i < 6; i++) {
      const a = (i / 6) * Math.PI * 2;
      ctx.beginPath();
      ctx.arc(Math.cos(a) * s * 0.17, -s * 0.15 + Math.sin(a) * s * 0.14, s * 0.2, 0, Math.PI * 2);
      ctx.fill();
      ctx.stroke();
    }
    ctx.beginPath();
    ctx.arc(0, -s * 0.15, s * 0.12, 0, Math.PI * 1.6);
    ctx.stroke();
  },
  script(ctx, s, t) {
    const text = t.text || 'Hooper';
    ctx.fillStyle = t.color;
    ctx.textAlign = 'center';
    ctx.textBaseline = 'middle';
    const px = Math.max(12, (s * 1.8) / Math.max(4, text.length) * 1.5);
    ctx.font = `italic 700 ${px}px "Brush Script MT", "Segoe Script", cursive`;
    ctx.fillText(text, 0, 0);
  },
  stars(ctx, s, t, { seed }) {
    const rnd = mulberry32(seed);
    ctx.fillStyle = t.color;
    ctx.strokeStyle = t.color;
    ctx.lineWidth = s * 0.03;
    for (let i = 0; i < 5; i++) {
      ctx.save();
      ctx.translate((rnd() - 0.5) * s * 1.2, (rnd() - 0.5) * s * 1.4);
      star(ctx, s * (0.12 + rnd() * 0.16));
      if (i % 2) ctx.fill();
      else ctx.stroke();
      ctx.restore();
    }
  },
  crown(ctx, s, t) {
    ctx.fillStyle = t.accent;
    ctx.strokeStyle = t.color;
    ctx.lineWidth = s * 0.06;
    ctx.beginPath();
    ctx.moveTo(-s * 0.55, s * 0.3);
    ctx.lineTo(-s * 0.6, -s * 0.3);
    ctx.lineTo(-s * 0.3, 0);
    ctx.lineTo(0, -s * 0.45);
    ctx.lineTo(s * 0.3, 0);
    ctx.lineTo(s * 0.6, -s * 0.3);
    ctx.lineTo(s * 0.55, s * 0.3);
    ctx.closePath();
    ctx.fill();
    ctx.stroke();
    ctx.fillStyle = t.color;
    for (const x of [-0.6, 0, 0.6]) {
      ctx.beginPath();
      ctx.arc(x * s, x === 0 ? -s * 0.5 : -s * 0.35, s * 0.07, 0, Math.PI * 2);
      ctx.fill();
    }
  },
  geometric(ctx, s, t, { width, height, cy }) {
    // A sleeve: tiles the whole limb, centred vertically on the offset.
    ctx.translate(0, -cy);
    ctx.strokeStyle = t.color;
    ctx.lineWidth = s * 0.035;
    const step = s * 0.5;
    for (let y = 0; y < height; y += step) {
      for (let x = -width; x < width; x += step) {
        ctx.beginPath();
        ctx.moveTo(x, y + step);
        ctx.lineTo(x + step / 2, y);
        ctx.lineTo(x + step, y + step);
        ctx.stroke();
        if (((x / step) | 0) % 2 === 0) {
          ctx.beginPath();
          ctx.arc(x + step / 2, y + step * 0.65, step * 0.12, 0, Math.PI * 2);
          ctx.stroke();
        }
      }
    }
  },
  flames(ctx, s, t) {
    const grad = ctx.createLinearGradient(0, s * 0.6, 0, -s * 0.7);
    grad.addColorStop(0, t.accent);
    grad.addColorStop(1, t.color);
    ctx.fillStyle = grad;
    for (let i = -2; i <= 2; i++) {
      ctx.beginPath();
      ctx.moveTo(i * s * 0.22 - s * 0.14, s * 0.6);
      ctx.quadraticCurveTo(i * s * 0.22 - s * 0.2, 0, i * s * 0.22 + s * 0.05, -s * (0.5 + (2 - Math.abs(i)) * 0.12));
      ctx.quadraticCurveTo(i * s * 0.22 + s * 0.05, 0, i * s * 0.22 + s * 0.14, s * 0.6);
      ctx.fill();
    }
  },
  number(ctx, s, t, { number }) {
    ctx.fillStyle = t.color;
    ctx.textAlign = 'center';
    ctx.textBaseline = 'middle';
    ctx.font = `900 ${s * 1.1}px "Arial Black", Impact, sans-serif`;
    ctx.fillText(t.text || String(number ?? 0), 0, 0);
  },
  clock(ctx, s, t) {
    ctx.strokeStyle = t.color;
    ctx.lineWidth = s * 0.06;
    ctx.beginPath();
    ctx.arc(0, 0, s * 0.5, 0, Math.PI * 2);
    ctx.stroke();
    for (let i = 0; i < 12; i++) {
      const a = (i / 12) * Math.PI * 2;
      ctx.beginPath();
      ctx.moveTo(Math.cos(a) * s * 0.4, Math.sin(a) * s * 0.4);
      ctx.lineTo(Math.cos(a) * s * 0.47, Math.sin(a) * s * 0.47);
      ctx.stroke();
    }
    ctx.beginPath();
    ctx.moveTo(0, 0);
    ctx.lineTo(0, -s * 0.32);
    ctx.moveTo(0, 0);
    ctx.lineTo(s * 0.22, s * 0.1);
    ctx.stroke();
  },
  praying(ctx, s, t) {
    ctx.fillStyle = t.color;
    ctx.fillRect(-s * 0.08, -s * 0.6, s * 0.16, s * 1.2);
    ctx.fillRect(-s * 0.38, -s * 0.3, s * 0.76, s * 0.16);
    ctx.strokeStyle = t.accent;
    ctx.lineWidth = s * 0.03;
    ctx.beginPath();
    ctx.arc(0, -s * 0.22, s * 0.3, 0, Math.PI * 2);
    ctx.stroke();
  },
  waves(ctx, s, t) {
    ctx.strokeStyle = t.color;
    ctx.lineWidth = s * 0.05;
    for (let row = -2; row <= 2; row++) {
      ctx.beginPath();
      for (let x = -s * 0.7; x <= s * 0.7; x += s * 0.05) {
        ctx.lineTo(x, row * s * 0.2 + Math.sin(x / (s * 0.12) + row) * s * 0.06);
      }
      ctx.stroke();
    }
  },
};
