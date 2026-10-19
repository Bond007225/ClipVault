/*
 * Lockloop scene engine.
 *
 * Every scene and overlay is a pure function of the loop phase p in [0, 1).
 * All motion uses whole-number cycle counts per loop, so frame p=1 is
 * identical to p=0 and exported videos loop seamlessly. Scene state is stored
 * in relative units, so the small preview and the full-resolution export
 * render exactly the same picture.
 */
(function () {
  'use strict';

  const TAU = Math.PI * 2;
  const frac = (x) => x - Math.floor(x);

  function mulberry32(a) {
    return function () {
      a |= 0;
      a = (a + 0x6d2b79f5) | 0;
      let t = Math.imul(a ^ (a >>> 15), 1 | a);
      t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t;
      return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
    };
  }

  const randInt = (r, a, b) => a + Math.floor(r() * (b - a + 1));
  const sign = (r) => (r() < 0.5 ? -1 : 1);

  function hash3(a, b, c) {
    let h = Math.imul(a, 73856093) ^ Math.imul(b, 19349663) ^ Math.imul(c, 83492791);
    h = Math.imul(h ^ (h >>> 13), 0x5bd1e995);
    return (h ^ (h >>> 15)) >>> 0;
  }

  // ---------------------------------------------------------------- colors
  const rgbCache = new Map();
  function hexToRgb(hex) {
    let v = rgbCache.get(hex);
    if (v) return v;
    let h = hex.replace('#', '');
    if (h.length === 3) h = h.split('').map((c) => c + c).join('');
    const n = parseInt(h, 16);
    v = [(n >> 16) & 255, (n >> 8) & 255, n & 255];
    rgbCache.set(hex, v);
    return v;
  }
  function rgba(hex, a) {
    const [r, g, b] = hexToRgb(hex);
    return `rgba(${r},${g},${b},${a})`;
  }
  function mix(h1, h2, t) {
    const a = hexToRgb(h1);
    const b = hexToRgb(h2);
    return '#' + a.map((v, i) => Math.round(v + (b[i] - v) * t).toString(16).padStart(2, '0')).join('');
  }
  // t < 0 darkens toward black, t > 0 lightens toward white.
  const shade = (hex, t) => (t < 0 ? mix(hex, '#000000', -t) : mix(hex, '#ffffff', t));

  function glow(ctx, x, y, radius, color, alpha) {
    const g = ctx.createRadialGradient(x, y, 0, x, y, radius);
    g.addColorStop(0, rgba(color, alpha));
    g.addColorStop(0.35, rgba(color, alpha * 0.45));
    g.addColorStop(1, rgba(color, 0));
    ctx.fillStyle = g;
    ctx.fillRect(x - radius, y - radius, radius * 2, radius * 2);
  }

  // ---------------------------------------------------------------- scenes
  const SCENES = {
    liquid: {
      name: 'Liquid',
      init(r, o) {
        const n = 4 + Math.round(o.detail * 5);
        return {
          blobs: Array.from({ length: n }, (_, i) => ({
            cx: r(), cy: r(),
            ax: 0.12 + r() * 0.3, ay: 0.08 + r() * 0.22,
            fx: randInt(r, 1, 2), fy: randInt(r, 1, 2),
            px: r() * TAU, py: r() * TAU,
            rad: 0.45 + r() * 0.4, ci: i % 3,
          })),
        };
      },
      draw(ctx, w, h, p, o, s) {
        ctx.fillStyle = shade(o.colors[2], -0.55);
        ctx.fillRect(0, 0, w, h);
        const m = Math.max(w, h);
        for (const b of s.blobs) {
          const x = w * (b.cx + b.ax * Math.sin(TAU * b.fx * o.speed * p + b.px));
          const y = h * (b.cy + b.ay * Math.cos(TAU * b.fy * o.speed * p + b.py));
          const R = b.rad * m * 0.6;
          const c = o.colors[b.ci];
          const g = ctx.createRadialGradient(x, y, 0, x, y, R);
          g.addColorStop(0, rgba(c, 0.9));
          g.addColorStop(0.5, rgba(c, 0.35));
          g.addColorStop(1, rgba(c, 0));
          ctx.fillStyle = g;
          ctx.fillRect(0, 0, w, h);
        }
      },
    },

    aurora: {
      name: 'Aurora',
      init(r, o) {
        const stars = Array.from({ length: Math.round(80 + o.detail * 220) }, () => ({
          x: r(), y: r() * 0.75, s: 0.3 + r() * 1.2, k: randInt(r, 1, 3), ph: r() * TAU,
        }));
        const bands = Array.from({ length: 3 + Math.round(o.detail * 2) }, (_, i) => ({
          base: 0.3 + r() * 0.25, amp: 0.03 + r() * 0.05,
          f1: 0.4 + r() * 1.2, f2: 1.2 + r() * 2,
          k1: randInt(r, 1, 2) * sign(r), k2: randInt(r, 1, 2) * sign(r),
          ph: r() * TAU, thick: 0.12 + r() * 0.18, ci: i % 3,
        }));
        const ridge = Array.from({ length: 14 }, () => r());
        return { stars, bands, ridge };
      },
      draw(ctx, w, h, p, o, s) {
        const u = Math.min(w, h);
        const bg = ctx.createLinearGradient(0, 0, 0, h);
        bg.addColorStop(0, shade(o.colors[2], -0.92));
        bg.addColorStop(1, shade(o.colors[1], -0.8));
        ctx.fillStyle = bg;
        ctx.fillRect(0, 0, w, h);

        ctx.fillStyle = '#ffffff';
        for (const st of s.stars) {
          ctx.globalAlpha = 0.25 + 0.75 * (0.5 + 0.5 * Math.sin(TAU * st.k * p + st.ph));
          ctx.beginPath();
          ctx.arc(st.x * w, st.y * h, (st.s * u) / 500, 0, TAU);
          ctx.fill();
        }
        ctx.globalAlpha = 1;

        ctx.globalCompositeOperation = 'lighter';
        ctx.lineCap = 'round';
        const steps = 48;
        const layers = 14;
        for (const b of s.bands) {
          const pts = [];
          for (let i = 0; i <= steps; i++) {
            const xn = i / steps;
            const y = b.base
              + b.amp * Math.sin(TAU * xn * b.f1 + TAU * b.k1 * o.speed * p + b.ph)
              + b.amp * 0.6 * Math.sin(TAU * xn * b.f2 + TAU * b.k2 * o.speed * p + b.ph * 1.7);
            pts.push([xn * w * 1.1 - w * 0.05, y * h]);
          }
          const step = (b.thick * h) / layers;
          ctx.lineWidth = step * 1.6;
          for (let j = 0; j < layers; j++) {
            const t = j / layers;
            ctx.strokeStyle = rgba(mix(o.colors[b.ci], o.colors[(b.ci + 1) % 3], t), 0.16 * Math.pow(1 - t, 1.4));
            ctx.beginPath();
            for (let i = 0; i < pts.length; i++) {
              const [x, y] = pts[i];
              if (i === 0) ctx.moveTo(x, y - j * step);
              else ctx.lineTo(x, y - j * step);
            }
            ctx.stroke();
          }
        }
        ctx.globalCompositeOperation = 'source-over';

        // Mountain silhouette keeps the bottom calm behind the dock area.
        ctx.fillStyle = shade(o.colors[2], -0.95);
        ctx.beginPath();
        ctx.moveTo(0, h);
        s.ridge.forEach((v, i) => ctx.lineTo((i / (s.ridge.length - 1)) * w, h * (0.8 + v * 0.08)));
        ctx.lineTo(w, h);
        ctx.closePath();
        ctx.fill();
      },
    },

    warp: {
      name: 'Warp',
      init(r, o) {
        return {
          stars: Array.from({ length: Math.round(150 + o.detail * 450) }, () => ({
            a: r() * TAU, z: r(), ci: randInt(r, 0, 2), k: randInt(r, 1, 2), sz: 0.5 + r(),
          })),
        };
      },
      draw(ctx, w, h, p, o, s) {
        const u = Math.min(w, h);
        const cx = w / 2;
        const cy = h * 0.45;
        const bg = ctx.createRadialGradient(cx, cy, 0, cx, cy, Math.max(w, h) * 0.7);
        bg.addColorStop(0, shade(o.colors[2], -0.6));
        bg.addColorStop(1, '#000000');
        ctx.fillStyle = bg;
        ctx.fillRect(0, 0, w, h);
        const maxR = Math.hypot(w, h) * 0.6;
        ctx.lineCap = 'round';
        for (const st of s.stars) {
          const t = frac(st.z + st.k * o.speed * p);
          const t0 = Math.max(0, t - 0.06);
          const r1 = maxR * t * t * t;
          const r0 = maxR * t0 * t0 * t0;
          const dx = Math.cos(st.a);
          const dy = Math.sin(st.a);
          ctx.strokeStyle = rgba(shade(o.colors[st.ci], 0.35), Math.min(1, t * 2.2));
          ctx.lineWidth = st.sz * u * 0.006 * t + u * 0.001;
          ctx.beginPath();
          ctx.moveTo(cx + dx * r0, cy + dy * r0);
          ctx.lineTo(cx + dx * r1, cy + dy * r1);
          ctx.stroke();
        }
        glow(ctx, cx, cy, u * 0.35, o.colors[0], 0.35 + 0.1 * Math.sin(TAU * p));
      },
    },

    bokeh: {
      name: 'Bokeh',
      init(r, o) {
        return {
          dots: Array.from({ length: Math.round(18 + o.detail * 50) }, (_, i) => ({
            x: r(), y: r(), rad: 0.02 + r() * r() * 0.1, ci: i % 3,
            k: randInt(r, 1, 2), wob: 0.01 + r() * 0.04, kw: randInt(r, 1, 3),
            ph: r() * TAU, a: 0.2 + r() * 0.45,
          })),
        };
      },
      draw(ctx, w, h, p, o, s) {
        const bg = ctx.createLinearGradient(0, 0, w, h);
        bg.addColorStop(0, shade(o.colors[0], -0.78));
        bg.addColorStop(1, shade(o.colors[2], -0.85));
        ctx.fillStyle = bg;
        ctx.fillRect(0, 0, w, h);
        ctx.globalCompositeOperation = 'lighter';
        for (const d of s.dots) {
          const y = (1.15 - 1.3 * frac(d.y + d.k * o.speed * p)) * h;
          const x = (d.x + d.wob * Math.sin(TAU * d.kw * o.speed * p + d.ph)) * w;
          const R = d.rad * w;
          const c = o.colors[d.ci];
          const g = ctx.createRadialGradient(x, y, 0, x, y, R);
          g.addColorStop(0, rgba(c, d.a * 0.8));
          g.addColorStop(0.8, rgba(c, d.a));
          g.addColorStop(1, rgba(c, 0));
          ctx.fillStyle = g;
          ctx.beginPath();
          ctx.arc(x, y, R, 0, TAU);
          ctx.fill();
        }
        ctx.globalCompositeOperation = 'source-over';
      },
    },

    waves: {
      name: 'Waves',
      init(r, o) {
        const n = 4 + Math.round(o.detail * 3);
        return {
          layers: Array.from({ length: n }, (_, i) => ({
            base: 0.56 + (i / n) * 0.4,
            A: 0.01 + r() * 0.018, f: 0.8 + r() * 1.6, k: randInt(r, 1, 2) * (i % 2 ? 1 : -1),
            A2: 0.004 + r() * 0.01, f2: 2 + r() * 3, k2: randInt(r, 1, 3) * sign(r),
            ph: r() * TAU,
          })),
        };
      },
      draw(ctx, w, h, p, o, s) {
        const sky = ctx.createLinearGradient(0, 0, 0, h * 0.62);
        sky.addColorStop(0, shade(o.colors[2], -0.35));
        sky.addColorStop(0.65, o.colors[1]);
        sky.addColorStop(1, shade(o.colors[0], 0.2));
        ctx.fillStyle = sky;
        ctx.fillRect(0, 0, w, h);

        const sx = w * 0.5;
        const sy = h * 0.5;
        glow(ctx, sx, sy, w * 0.7, shade(o.colors[0], 0.3), 0.45 + 0.08 * Math.sin(TAU * p));
        ctx.fillStyle = shade(o.colors[0], 0.55);
        ctx.beginPath();
        ctx.arc(sx, sy, w * 0.13, 0, TAU);
        ctx.fill();

        const n = s.layers.length;
        const steps = 60;
        s.layers.forEach((L, i) => {
          ctx.fillStyle = mix(shade(o.colors[1], -0.25), shade(o.colors[2], -0.88), i / (n - 1));
          ctx.beginPath();
          ctx.moveTo(0, h);
          for (let k = 0; k <= steps; k++) {
            const xn = k / steps;
            const y = L.base
              + L.A * Math.sin(TAU * xn * L.f + TAU * L.k * o.speed * p + L.ph)
              + L.A2 * Math.sin(TAU * xn * L.f2 + TAU * L.k2 * o.speed * p);
            ctx.lineTo(xn * w, y * h);
          }
          ctx.lineTo(w, h);
          ctx.closePath();
          ctx.fill();
        });
      },
    },

    matrix: {
      name: 'Code Rain',
      init(r, o) {
        const cols = 16 + Math.round(o.detail * 20);
        return {
          cols: Array.from({ length: cols }, () => ({
            y: r(), len: randInt(r, 8, 26), k: randInt(r, 1, 3), seed: Math.floor(r() * 1e6),
          })),
        };
      },
      draw(ctx, w, h, p, o, s) {
        const GLYPHS = 'アイウエオカキクケコサシスセソタチツテトナニヌネノ0123456789ABCDEFZ<>*+=';
        ctx.fillStyle = shade(o.colors[2], -0.94);
        ctx.fillRect(0, 0, w, h);
        const fs = w / s.cols.length;
        const rows = Math.ceil(h / fs);
        ctx.font = `${Math.round(fs * 0.9)}px "SF Mono", Menlo, Consolas, monospace`;
        ctx.textAlign = 'center';
        ctx.textBaseline = 'top';
        const tick = Math.floor(p * 48);
        s.cols.forEach((c, ci) => {
          const span = rows + c.len;
          const head = Math.floor(frac(c.y + c.k * o.speed * p) * span);
          for (let j = 0; j < c.len; j++) {
            const row = head - j;
            if (row < 0 || row >= rows) continue;
            const g = GLYPHS[hash3(c.seed, row, j === 0 ? tick : tick >> 2) % GLYPHS.length];
            const t = j / c.len;
            ctx.fillStyle = j === 0 ? shade(o.colors[0], 0.8) : rgba(mix(o.colors[0], o.colors[1], t), Math.pow(1 - t, 1.2));
            ctx.fillText(g, (ci + 0.5) * fs, row * fs);
          }
        });
      },
    },

    orbit: {
      name: 'Orbits',
      init(r, o) {
        const n = 5 + Math.round(o.detail * 5);
        return {
          rings: Array.from({ length: n }, (_, i) => ({
            r: 0.07 + (i + 1) * (0.4 / n), k: randInt(r, 1, 2) * sign(r), ph: r() * TAU,
            dots: randInt(r, 1, 3), dashed: r() < 0.5, ci: i % 3, lw: 0.5 + r() * 2,
          })),
        };
      },
      draw(ctx, w, h, p, o, s) {
        const cx = w / 2;
        const cy = h * 0.58;
        const bg = ctx.createRadialGradient(cx, cy, 0, cx, cy, Math.max(w, h) * 0.75);
        bg.addColorStop(0, shade(o.colors[2], -0.55));
        bg.addColorStop(1, shade(o.colors[0], -0.94));
        ctx.fillStyle = bg;
        ctx.fillRect(0, 0, w, h);
        for (const ring of s.rings) {
          const R = ring.r * w * 1.15;
          const ang = TAU * ring.k * o.speed * p + ring.ph;
          const c = o.colors[ring.ci];
          ctx.save();
          ctx.translate(cx, cy);
          ctx.rotate(ang);
          ctx.strokeStyle = rgba(c, 0.3);
          ctx.lineWidth = (ring.lw * w) / 600;
          ctx.setLineDash(ring.dashed ? [w * 0.008, w * 0.018] : []);
          ctx.beginPath();
          ctx.arc(0, 0, R, 0, TAU);
          ctx.stroke();
          ctx.setLineDash([]);
          ctx.globalCompositeOperation = 'lighter';
          for (let d = 0; d < ring.dots; d++) {
            const a = (d * TAU) / ring.dots;
            const x = Math.cos(a) * R;
            const y = Math.sin(a) * R;
            glow(ctx, x, y, w * 0.05, c, 0.7);
            ctx.fillStyle = shade(c, 0.7);
            ctx.beginPath();
            ctx.arc(x, y, w * 0.007, 0, TAU);
            ctx.fill();
          }
          ctx.globalCompositeOperation = 'source-over';
          ctx.restore();
        }
        ctx.globalCompositeOperation = 'lighter';
        glow(ctx, cx, cy, w * 0.12 * (1 + 0.15 * Math.sin(TAU * 2 * p)), o.colors[0], 0.9);
        ctx.globalCompositeOperation = 'source-over';
      },
    },

    photo: {
      name: 'My Photo',
      init() {
        return {};
      },
      draw(ctx, w, h, p, o) {
        const img = o.photo;
        if (!img) {
          const g = ctx.createLinearGradient(0, 0, w, h);
          g.addColorStop(0, shade(o.colors[0], -0.5));
          g.addColorStop(1, shade(o.colors[2], -0.7));
          ctx.fillStyle = g;
          ctx.fillRect(0, 0, w, h);
          ctx.fillStyle = 'rgba(255,255,255,0.75)';
          ctx.font = `600 ${Math.round(w * 0.05)}px system-ui, sans-serif`;
          ctx.textAlign = 'center';
          ctx.textBaseline = 'middle';
          ctx.fillText('Upload a photo', w / 2, h * 0.62);
          return;
        }
        let z = 1;
        let dx = 0;
        let dy = 0;
        let rot = 0;
        const sp = o.speed;
        switch (o.photoMotion) {
          case 'zoom':
            z = 1.04 + 0.08 * (0.5 - 0.5 * Math.cos(TAU * sp * p));
            break;
          case 'pan':
            z = 1.18;
            dx = 0.06 * Math.sin(TAU * sp * p);
            dy = 0.025 * Math.sin(TAU * 2 * sp * p);
            break;
          case 'sway':
            z = 1.12;
            rot = 0.018 * Math.sin(TAU * sp * p);
            break;
          case 'breathe':
            z = 1.04 + 0.025 * Math.sin(TAU * 2 * sp * p);
            break;
          default:
            break;
        }
        const iw = img.naturalWidth || img.width;
        const ih = img.naturalHeight || img.height;
        const scale = Math.max(w / iw, h / ih) * z;
        const dw = iw * scale;
        const dh = ih * scale;
        ctx.fillStyle = '#000';
        ctx.fillRect(0, 0, w, h);
        ctx.save();
        ctx.translate(w / 2 + dx * w, h / 2 + dy * h);
        ctx.rotate(rot);
        ctx.drawImage(img, -dw / 2, -dh / 2, dw, dh);
        ctx.restore();
      },
    },
  };

  // -------------------------------------------------------------- overlays
  const OVERLAYS = {
    none: { name: 'None', init: () => ({}), draw() {} },

    snow: {
      name: 'Snow',
      init(r, o) {
        return {
          flakes: Array.from({ length: Math.round(40 + o.overlayAmount * 260) }, () => ({
            x: r(), y: r(), r: 0.5 + r() * r() * 2.8, k: randInt(r, 1, 2),
            sw: 0.005 + r() * 0.02, kw: randInt(r, 1, 2), ph: r() * TAU, a: 0.45 + r() * 0.55,
          })),
        };
      },
      draw(ctx, w, h, p, o, s) {
        const u = Math.min(w, h) / 400;
        ctx.fillStyle = '#ffffff';
        for (const f of s.flakes) {
          const y = (frac(f.y + f.k * o.speed * p) * 1.1 - 0.05) * h;
          const x = (f.x + f.sw * Math.sin(TAU * f.kw * o.speed * p + f.ph)) * w;
          ctx.globalAlpha = f.a;
          ctx.beginPath();
          ctx.arc(x, y, f.r * u, 0, TAU);
          ctx.fill();
        }
        ctx.globalAlpha = 1;
      },
    },

    rain: {
      name: 'Rain',
      init(r, o) {
        return {
          drops: Array.from({ length: Math.round(60 + o.overlayAmount * 300) }, () => ({
            x: r() * 1.2, y: r(), len: 0.02 + r() * 0.04, k: randInt(r, 2, 4), a: 0.12 + r() * 0.3,
          })),
        };
      },
      draw(ctx, w, h, p, o, s) {
        const u = Math.min(w, h) / 400;
        ctx.strokeStyle = mix('#ffffff', o.colors[1], 0.25);
        ctx.lineWidth = 0.8 * u;
        ctx.lineCap = 'round';
        for (const d of s.drops) {
          const t = frac(d.y + d.k * o.speed * p);
          const y = (t * 1.2 - 0.1) * h;
          const x = (d.x - t * 0.15) * w;
          ctx.globalAlpha = d.a;
          ctx.beginPath();
          ctx.moveTo(x, y);
          ctx.lineTo(x - d.len * 0.15 * h, y + d.len * h);
          ctx.stroke();
        }
        ctx.globalAlpha = 1;
      },
    },

    sparkles: {
      name: 'Sparkles',
      init(r, o) {
        return {
          stars: Array.from({ length: Math.round(15 + o.overlayAmount * 60) }, () => ({
            x: r(), y: r(), size: 0.01 + r() * 0.025, k: randInt(r, 1, 3), ph: r() * TAU, ci: randInt(r, 0, 2),
          })),
        };
      },
      draw(ctx, w, h, p, o, s) {
        ctx.globalCompositeOperation = 'lighter';
        for (const st of s.stars) {
          const v = Math.max(0, Math.sin(TAU * st.k * p + st.ph));
          const a = v * v * v;
          if (a < 0.01) continue;
          const x = st.x * w;
          const y = st.y * h;
          const R = st.size * w * (0.6 + 0.4 * a);
          const c = shade(o.colors[st.ci], 0.5);
          glow(ctx, x, y, R * 1.6, c, a * 0.6);
          ctx.fillStyle = rgba('#ffffff', a);
          ctx.beginPath();
          ctx.moveTo(x, y - R);
          ctx.quadraticCurveTo(x, y, x + R, y);
          ctx.quadraticCurveTo(x, y, x, y + R);
          ctx.quadraticCurveTo(x, y, x - R, y);
          ctx.quadraticCurveTo(x, y, x, y - R);
          ctx.fill();
        }
        ctx.globalCompositeOperation = 'source-over';
      },
    },

    fireflies: {
      name: 'Fireflies',
      init(r, o) {
        return {
          flies: Array.from({ length: Math.round(10 + o.overlayAmount * 40) }, () => ({
            x: r(), y: 0.15 + r() * 0.8, ax: 0.02 + r() * 0.06, ay: 0.02 + r() * 0.05,
            kx: randInt(r, 1, 2), ky: randInt(r, 1, 2), kb: randInt(r, 1, 3),
            px: r() * TAU, py: r() * TAU, pb: r() * TAU, ci: randInt(r, 0, 2),
          })),
        };
      },
      draw(ctx, w, h, p, o, s) {
        ctx.globalCompositeOperation = 'lighter';
        for (const f of s.flies) {
          const x = (f.x + f.ax * Math.sin(TAU * f.kx * o.speed * p + f.px)) * w;
          const y = (f.y + f.ay * Math.sin(TAU * f.ky * o.speed * p + f.py)) * h;
          const b = 0.3 + 0.7 * (0.5 + 0.5 * Math.sin(TAU * f.kb * p + f.pb));
          glow(ctx, x, y, w * 0.035, shade(o.colors[f.ci], 0.4), b * 0.8);
        }
        ctx.globalCompositeOperation = 'source-over';
      },
    },
  };

  function drawVignette(ctx, w, h) {
    const g = ctx.createRadialGradient(w / 2, h / 2, Math.min(w, h) * 0.35, w / 2, h / 2, Math.hypot(w, h) * 0.55);
    g.addColorStop(0, 'rgba(0,0,0,0)');
    g.addColorStop(1, 'rgba(0,0,0,0.5)');
    ctx.fillStyle = g;
    ctx.fillRect(0, 0, w, h);
    // Slight darkening up top keeps the lock screen clock readable.
    const t = ctx.createLinearGradient(0, 0, 0, h * 0.3);
    t.addColorStop(0, 'rgba(0,0,0,0.28)');
    t.addColorStop(1, 'rgba(0,0,0,0)');
    ctx.fillStyle = t;
    ctx.fillRect(0, 0, w, h * 0.3);
  }

  // A renderer caches per-scene state; the cache key covers every option that
  // changes the generated layout, so identical options always give identical
  // pixels no matter which renderer instance draws them.
  function createRenderer() {
    let sceneKey = '';
    let sceneState = null;
    let overlayKey = '';
    let overlayState = null;

    return {
      draw(ctx, w, h, p, o) {
        const scene = SCENES[o.scene] || SCENES.liquid;
        const overlay = OVERLAYS[o.overlay] || OVERLAYS.none;
        const sk = `${o.scene}|${o.seed}|${o.detail}`;
        if (sk !== sceneKey) {
          sceneState = scene.init(mulberry32(o.seed), o);
          sceneKey = sk;
        }
        const ok = `${o.overlay}|${o.seed}|${o.overlayAmount}`;
        if (ok !== overlayKey) {
          overlayState = overlay.init(mulberry32(o.seed ^ 0x9e3779b9), o);
          overlayKey = ok;
        }
        ctx.save();
        ctx.globalAlpha = 1;
        ctx.globalCompositeOperation = 'source-over';
        scene.draw(ctx, w, h, p, o, sceneState);
        overlay.draw(ctx, w, h, p, o, overlayState);
        if (o.vignette) drawVignette(ctx, w, h);
        ctx.restore();
      },
    };
  }

  const PALETTES = {
    aurora: { name: 'Aurora', colors: ['#00ffa3', '#00b3ff', '#8a2be2'] },
    sunset: { name: 'Sunset', colors: ['#ff6b6b', '#feca57', '#5f27cd'] },
    neon: { name: 'Neon', colors: ['#ff00e5', '#00f0ff', '#7000ff'] },
    ocean: { name: 'Ocean', colors: ['#7ef9ff', '#1e90ff', '#0b2a6b'] },
    forest: { name: 'Forest', colors: ['#c6f36b', '#2ecc71', '#134e5e'] },
    candy: { name: 'Candy', colors: ['#ff9ac1', '#ffd6a5', '#a18cd1'] },
    ember: { name: 'Ember', colors: ['#ff4e00', '#ffb300', '#7a1300'] },
    mono: { name: 'Mono', colors: ['#ffffff', '#9aa5b1', '#3a4250'] },
  };

  window.LockScenes = { SCENES, OVERLAYS, PALETTES, createRenderer };
})();
