(function () {
  'use strict';

  const { SCENES, OVERLAYS, PALETTES, createRenderer } = window.LockScenes;
  const FPS = 30;
  const STORAGE_KEY = 'lockloop.settings.v1';

  // Native lock screen resolutions (portrait, physical pixels).
  const DEVICES = [
    { id: 'iphone16promax', name: 'iPhone 16 Pro Max', platform: 'ios', w: 1320, h: 2868 },
    { id: 'iphone16pro', name: 'iPhone 16 Pro', platform: 'ios', w: 1206, h: 2622 },
    { id: 'iphone16plus', name: 'iPhone 16 Plus / 15 Pro Max', platform: 'ios', w: 1290, h: 2796 },
    { id: 'iphone16', name: 'iPhone 16 / 15 / 15 Pro', platform: 'ios', w: 1179, h: 2556 },
    { id: 'iphone14', name: 'iPhone 14 / 13 / 12', platform: 'ios', w: 1170, h: 2532 },
    { id: 'iphonese', name: 'iPhone SE', platform: 'ios', w: 750, h: 1334 },
    { id: 's25ultra', name: 'Galaxy S25 Ultra', platform: 'android', w: 1440, h: 3120 },
    { id: 's25', name: 'Galaxy S25 / S24', platform: 'android', w: 1080, h: 2340 },
    { id: 'pixel9pro', name: 'Pixel 9 Pro', platform: 'android', w: 1280, h: 2856 },
    { id: 'pixel9', name: 'Pixel 9', platform: 'android', w: 1080, h: 2424 },
    { id: 'android', name: 'Other Android (1080 × 2400)', platform: 'android', w: 1080, h: 2400 },
  ];

  const defaults = {
    device: guessDevice(),
    scene: 'liquid',
    palette: 'aurora',
    colors: PALETTES.aurora.colors.slice(),
    speed: 1,
    detail: 0.5,
    overlay: 'none',
    overlayAmount: 0.5,
    vignette: true,
    duration: 5,
    quality: 1,
    seed: 20251019,
    photoMotion: 'zoom',
    showLock: true,
  };

  const state = Object.assign({}, defaults, loadSettings(), { photo: null });

  const $ = (id) => document.getElementById(id);
  const els = {
    phone: $('phone'), preview: $('preview'), lockUi: $('lockUi'), lockTime: $('lockTime'), lockDate: $('lockDate'),
    showLock: $('showLock'), shuffle: $('shuffle'), deviceMeta: $('deviceMeta'), device: $('device'),
    scenes: $('scenes'), photoGroup: $('photoGroup'), photoInput: $('photoInput'), photoMotion: $('photoMotion'),
    palettes: $('palettes'), c: [$('c0'), $('c1'), $('c2')], speed: $('speed'), speedOut: $('speedOut'),
    detail: $('detail'), overlay: $('overlay'), overlayAmount: $('overlayAmount'), duration: $('duration'),
    quality: $('quality'), vignette: $('vignette'), exportVideo: $('exportVideo'), exportStill: $('exportStill'),
    dialog: $('exportDialog'), dialogTitle: $('dialogTitle'), dialogNote: $('dialogNote'), progressWrap: $('progressWrap'),
    progressBar: $('progressBar'), resultVideo: $('resultVideo'), resultActions: $('resultActions'),
    downloadLink: $('downloadLink'), shareBtn: $('shareBtn'), closeDialog: $('closeDialog'),
  };

  function guessDevice() {
    return /android/i.test(navigator.userAgent) ? 'android' : 'iphone16';
  }

  function loadSettings() {
    try {
      const saved = JSON.parse(localStorage.getItem(STORAGE_KEY) || '{}');
      return saved && typeof saved === 'object' ? saved : {};
    } catch (e) {
      return {};
    }
  }

  function saveSettings() {
    try {
      const { photo, ...rest } = state;
      localStorage.setItem(STORAGE_KEY, JSON.stringify(rest));
    } catch (e) {
      /* storage unavailable: settings just won't persist */
    }
  }

  const currentDevice = () => DEVICES.find((d) => d.id === state.device) || DEVICES[3];

  function renderOptions() {
    return {
      scene: state.scene,
      colors: state.colors,
      speed: state.speed,
      detail: state.detail,
      overlay: state.overlay,
      overlayAmount: state.overlayAmount,
      vignette: state.vignette,
      seed: state.seed,
      photo: state.photo,
      photoMotion: state.photoMotion,
    };
  }

  // ------------------------------------------------------------ build UI
  function buildDeviceSelect() {
    const groups = { ios: 'iPhone', android: 'Android' };
    for (const [platform, label] of Object.entries(groups)) {
      const og = document.createElement('optgroup');
      og.label = label;
      DEVICES.filter((d) => d.platform === platform).forEach((d) => {
        og.appendChild(new Option(d.name, d.id));
      });
      els.device.appendChild(og);
    }
  }

  const thumbRenderer = createRenderer();
  function buildSceneChips() {
    els.scenes.innerHTML = '';
    for (const [id, scene] of Object.entries(SCENES)) {
      const b = document.createElement('button');
      b.type = 'button';
      b.className = 'chip';
      b.setAttribute('role', 'radio');
      b.dataset.scene = id;
      const c = document.createElement('canvas');
      c.width = 120;
      c.height = 160;
      const label = document.createElement('span');
      label.textContent = scene.name;
      b.append(c, label);
      b.addEventListener('click', () => update({ scene: id }));
      els.scenes.appendChild(b);
    }
  }

  function paintSceneThumbs() {
    els.scenes.querySelectorAll('.chip').forEach((chip) => {
      const c = chip.querySelector('canvas');
      const o = Object.assign(renderOptions(), { scene: chip.dataset.scene, overlay: 'none', vignette: false });
      thumbRenderer.draw(c.getContext('2d'), c.width, c.height, 0.15, o);
    });
  }

  function buildPalettes() {
    for (const [id, pal] of Object.entries(PALETTES)) {
      const b = document.createElement('button');
      b.type = 'button';
      b.className = 'swatch';
      b.title = pal.name;
      b.setAttribute('aria-label', pal.name);
      b.setAttribute('role', 'radio');
      b.dataset.palette = id;
      b.style.background = `conic-gradient(${pal.colors[0]} 0 33%, ${pal.colors[1]} 0 66%, ${pal.colors[2]} 0)`;
      b.addEventListener('click', () => update({ palette: id, colors: pal.colors.slice() }));
      els.palettes.appendChild(b);
    }
  }

  function buildOverlaySelect() {
    for (const [id, ov] of Object.entries(OVERLAYS)) els.overlay.appendChild(new Option(ov.name, id));
  }

  // --------------------------------------------------------------- state
  function update(patch) {
    Object.assign(state, patch);
    syncUI();
    saveSettings();
  }

  function syncUI() {
    const dev = currentDevice();
    els.device.value = dev.id;
    els.phone.style.aspectRatio = `${dev.w} / ${dev.h}`;
    els.lockUi.className = `lock-ui ${dev.platform}`;
    els.lockUi.hidden = !state.showLock;
    els.showLock.checked = state.showLock;
    els.deviceMeta.textContent = `${dev.w} × ${dev.h} · ${state.duration}s seamless loop`;

    els.scenes.querySelectorAll('.chip').forEach((c) => c.setAttribute('aria-checked', String(c.dataset.scene === state.scene)));
    els.photoGroup.hidden = state.scene !== 'photo';
    els.photoMotion.value = state.photoMotion;

    els.palettes.querySelectorAll('.swatch').forEach((s) => {
      const pal = PALETTES[s.dataset.palette];
      const match = pal.colors.every((c, i) => c.toLowerCase() === state.colors[i].toLowerCase());
      s.setAttribute('aria-checked', String(match));
    });
    els.c.forEach((input, i) => { input.value = state.colors[i]; });

    els.speed.value = state.speed;
    els.speedOut.textContent = `${state.speed}×`;
    els.detail.value = state.detail;
    els.overlay.value = state.overlay;
    els.overlayAmount.value = state.overlayAmount;
    els.overlayAmount.disabled = state.overlay === 'none';
    els.duration.value = String(state.duration);
    els.quality.value = String(state.quality);
    els.vignette.checked = state.vignette;

    sizePreview();
    paintSceneThumbs();
    updateClock();
  }

  function bindControls() {
    els.device.addEventListener('change', () => update({ device: els.device.value }));
    els.showLock.addEventListener('change', () => update({ showLock: els.showLock.checked }));
    els.photoMotion.addEventListener('change', () => update({ photoMotion: els.photoMotion.value }));
    els.c.forEach((input, i) => input.addEventListener('input', () => {
      const colors = state.colors.slice();
      colors[i] = input.value;
      update({ colors });
    }));
    els.speed.addEventListener('input', () => update({ speed: Number(els.speed.value) }));
    els.detail.addEventListener('change', () => update({ detail: Number(els.detail.value) }));
    els.overlay.addEventListener('change', () => update({ overlay: els.overlay.value }));
    els.overlayAmount.addEventListener('change', () => update({ overlayAmount: Number(els.overlayAmount.value) }));
    els.duration.addEventListener('change', () => update({ duration: Number(els.duration.value) }));
    els.quality.addEventListener('change', () => update({ quality: Number(els.quality.value) }));
    els.vignette.addEventListener('change', () => update({ vignette: els.vignette.checked }));
    els.shuffle.addEventListener('click', shuffle);
    els.photoInput.addEventListener('change', loadPhoto);
    els.exportVideo.addEventListener('click', exportVideo);
    els.exportStill.addEventListener('click', exportStill);
    els.closeDialog.addEventListener('click', closeDialog);
    els.dialog.addEventListener('cancel', (e) => { if (exporting) e.preventDefault(); });

    document.querySelectorAll('.tabs [data-tab]').forEach((tab) => {
      tab.addEventListener('click', () => showGuideTab(tab.dataset.tab));
    });
  }

  function showGuideTab(name) {
    document.querySelectorAll('.tabs [data-tab]').forEach((t) => t.setAttribute('aria-selected', String(t.dataset.tab === name)));
    document.querySelectorAll('.tab-panel').forEach((p) => { p.hidden = p.dataset.panel !== name; });
  }

  function shuffle() {
    const sceneIds = Object.keys(SCENES).filter((s) => s !== 'photo' || state.photo);
    const palIds = Object.keys(PALETTES);
    const overlayIds = Object.keys(OVERLAYS);
    const pick = (arr) => arr[Math.floor(Math.random() * arr.length)];
    const palette = pick(palIds);
    update({
      scene: pick(sceneIds),
      palette,
      colors: PALETTES[palette].colors.slice(),
      overlay: Math.random() < 0.5 ? 'none' : pick(overlayIds),
      speed: 1 + Math.floor(Math.random() * 2),
      seed: Math.floor(Math.random() * 1e9),
    });
  }

  function loadPhoto() {
    const file = els.photoInput.files && els.photoInput.files[0];
    if (!file) return;
    const url = URL.createObjectURL(file);
    const img = new Image();
    img.onload = () => {
      if (state.photo && state.photo.src.startsWith('blob:')) URL.revokeObjectURL(state.photo.src);
      update({ photo: img, scene: 'photo' });
    };
    img.onerror = () => {
      URL.revokeObjectURL(url);
      alert('That image could not be opened. Try a JPEG or PNG.');
    };
    img.src = url;
  }

  // ------------------------------------------------------------- preview
  const pctx = els.preview.getContext('2d');
  const previewRenderer = createRenderer();
  let loopStart = performance.now();
  let exporting = false;

  function sizePreview() {
    const rect = els.phone.getBoundingClientRect();
    const dpr = Math.min(window.devicePixelRatio || 1, 2);
    const w = Math.max(1, Math.round(rect.width * dpr));
    const h = Math.max(1, Math.round(rect.height * dpr));
    if (els.preview.width !== w || els.preview.height !== h) {
      els.preview.width = w;
      els.preview.height = h;
    }
  }

  function tick(now) {
    if (!exporting) {
      const p = ((now - loopStart) / 1000 / state.duration) % 1;
      previewRenderer.draw(pctx, els.preview.width, els.preview.height, p, renderOptions());
    }
    requestAnimationFrame(tick);
  }

  function updateClock() {
    const now = new Date();
    const dev = currentDevice();
    const h = now.getHours() % 12 || 12;
    const m = String(now.getMinutes()).padStart(2, '0');
    els.lockTime.textContent = dev.platform === 'android' ? `${String(h).padStart(2, '0')}\n${m}` : `${h}:${m}`;
    els.lockDate.textContent = now.toLocaleDateString(undefined, { weekday: 'long', month: 'long', day: 'numeric' });
  }

  // -------------------------------------------------------------- export
  const even = (n) => Math.max(2, Math.round(n / 2) * 2);

  function exportSize() {
    const dev = currentDevice();
    return { w: even(dev.w * state.quality), h: even(dev.h * state.quality) };
  }

  function fileBase() {
    return `lockloop-${state.scene}-${currentDevice().id}`;
  }

  function makeCanvas(w, h) {
    const canvas = document.createElement('canvas');
    canvas.width = w;
    canvas.height = h;
    canvas.className = 'offscreen';
    document.body.appendChild(canvas);
    return canvas;
  }

  const nextFrame = () => new Promise((r) => setTimeout(r, 0));

  async function pickAvcCodec(w, h, bitrate) {
    // High → Main → Baseline at levels large enough for tall phone screens.
    const candidates = ['avc1.640034', 'avc1.640033', 'avc1.4d0034', 'avc1.4d0033', 'avc1.42003e', 'avc1.420034'];
    for (const codec of candidates) {
      try {
        const res = await VideoEncoder.isConfigSupported({ codec, width: w, height: h, bitrate, framerate: FPS });
        if (res.supported) return codec;
      } catch (e) {
        /* try the next one */
      }
    }
    return null;
  }

  // Frame-exact offline encode: WebCodecs H.264 into an MP4 container.
  async function encodeWithWebCodecs(w, h, onProgress) {
    if (!('VideoEncoder' in window) || !('VideoFrame' in window) || !window.Mp4Muxer) return null;
    const bitrate = Math.min(40e6, Math.round(w * h * FPS * 0.2));
    const codec = await pickAvcCodec(w, h, bitrate);
    if (!codec) return null;

    const canvas = makeCanvas(w, h);
    const ctx = canvas.getContext('2d');
    const renderer = createRenderer();
    const o = renderOptions();
    const muxer = new Mp4Muxer.Muxer({
      target: new Mp4Muxer.ArrayBufferTarget(),
      video: { codec: 'avc', width: w, height: h, frameRate: FPS },
      fastStart: 'in-memory',
    });
    let encodeError = null;
    const encoder = new VideoEncoder({
      output: (chunk, meta) => muxer.addVideoChunk(chunk, meta),
      error: (e) => { encodeError = e; },
    });
    encoder.configure({ codec, width: w, height: h, bitrate, framerate: FPS, avc: { format: 'avc' } });

    try {
      const frames = Math.round(state.duration * FPS);
      for (let i = 0; i < frames; i++) {
        if (encodeError) throw encodeError;
        renderer.draw(ctx, w, h, i / frames, o);
        const frame = new VideoFrame(canvas, { timestamp: Math.round((i * 1e6) / FPS), duration: Math.round(1e6 / FPS) });
        encoder.encode(frame, { keyFrame: i % FPS === 0 });
        frame.close();
        while (encoder.encodeQueueSize > 6) await nextFrame();
        if (i % 3 === 0) {
          onProgress(i / frames);
          await nextFrame();
        }
      }
      await encoder.flush();
      if (encodeError) throw encodeError;
      muxer.finalize();
      return { blob: new Blob([muxer.target.buffer], { type: 'video/mp4' }), ext: 'mp4' };
    } finally {
      if (encoder.state !== 'closed') encoder.close();
      canvas.remove();
    }
  }

  function pickRecorderMime() {
    if (!window.MediaRecorder) return null;
    // Plain 'video/mp4' can mean VP9-in-MP4 on Chromium, which phones handle
    // poorly, so ask for H.264 explicitly first.
    const types = ['video/mp4;codecs=avc1.640033', 'video/mp4;codecs=avc1', 'video/mp4', 'video/webm;codecs=vp9', 'video/webm'];
    return types.find((t) => MediaRecorder.isTypeSupported(t)) || null;
  }

  // Real-time fallback for browsers without WebCodecs.
  async function encodeWithRecorder(w, h, onProgress) {
    const mime = pickRecorderMime();
    if (!mime || !HTMLCanvasElement.prototype.captureStream) return null;
    const canvas = makeCanvas(w, h);
    const ctx = canvas.getContext('2d');
    const renderer = createRenderer();
    const o = renderOptions();
    renderer.draw(ctx, w, h, 0, o);
    const stream = canvas.captureStream(FPS);
    const rec = new MediaRecorder(stream, { mimeType: mime, videoBitsPerSecond: Math.min(25e6, Math.round(w * h * FPS * 0.15)) });
    const chunks = [];
    rec.ondataavailable = (e) => { if (e.data && e.data.size) chunks.push(e.data); };
    const stopped = new Promise((r) => { rec.onstop = r; });
    rec.start(250);
    const total = state.duration * 1000;
    const start = performance.now();
    await new Promise((resolve) => {
      function step(now) {
        const elapsed = now - start;
        if (elapsed >= total) return resolve();
        renderer.draw(ctx, w, h, elapsed / total, o);
        onProgress(elapsed / total);
        requestAnimationFrame(step);
      }
      requestAnimationFrame(step);
    });
    rec.stop();
    await stopped;
    stream.getTracks().forEach((t) => t.stop());
    canvas.remove();
    const type = mime.split(';')[0];
    return { blob: new Blob(chunks, { type }), ext: type === 'video/mp4' ? 'mp4' : 'webm' };
  }

  async function exportVideo() {
    if (exporting) return;
    const { w, h } = exportSize();
    exporting = true;
    els.exportVideo.disabled = true;
    openDialog('Rendering video…', `Rendering ${w} × ${h}. Keep this tab open.`);
    const onProgress = (f) => { els.progressBar.style.width = `${Math.round(f * 100)}%`; };
    try {
      let result = null;
      try {
        result = await encodeWithWebCodecs(w, h, onProgress);
      } catch (e) {
        console.warn('WebCodecs export failed, falling back to MediaRecorder', e);
      }
      if (!result) result = await encodeWithRecorder(w, h, onProgress);
      if (!result) throw new Error('This browser cannot record video. Try the latest Safari or Chrome.');
      onProgress(1);
      const note = result.ext === 'webm'
        ? 'Saved as WebM. Some phones need MP4; if yours rejects it, export from Safari or Chrome on the phone.'
        : 'MP4 ready. Save it to your photos, then follow the lock screen guide.';
      showResult(result.blob, `${fileBase()}.${result.ext}`, note);
    } catch (e) {
      els.dialogTitle.textContent = 'Export failed';
      els.dialogNote.textContent = e && e.message ? e.message : String(e);
      els.progressWrap.hidden = true;
    } finally {
      exporting = false;
      els.exportVideo.disabled = false;
      loopStart = performance.now();
    }
  }

  function exportStill() {
    const { w, h } = exportSize();
    const canvas = makeCanvas(w, h);
    createRenderer().draw(canvas.getContext('2d'), w, h, 0, renderOptions());
    canvas.toBlob((blob) => {
      canvas.remove();
      if (!blob) return;
      openDialog('Still ready', '');
      showResult(blob, `${fileBase()}.png`, 'A static version of this wallpaper, for any phone.');
    }, 'image/png');
  }

  let resultUrl = null;

  function openDialog(title, note) {
    els.dialogTitle.textContent = title;
    els.dialogNote.textContent = note;
    els.progressWrap.hidden = false;
    els.progressBar.style.width = '0%';
    els.resultVideo.hidden = true;
    els.resultActions.hidden = true;
    if (!els.dialog.open) els.dialog.showModal();
  }

  function showResult(blob, filename, note) {
    if (resultUrl) URL.revokeObjectURL(resultUrl);
    resultUrl = URL.createObjectURL(blob);
    const isVideo = blob.type.startsWith('video/');
    els.dialogTitle.textContent = isVideo ? 'Your lock screen is ready' : 'Still ready';
    els.dialogNote.textContent = `${note} (${(blob.size / 1e6).toFixed(1)} MB)`;
    els.progressWrap.hidden = true;
    if (isVideo) {
      els.resultVideo.src = resultUrl;
      els.resultVideo.hidden = false;
      els.resultVideo.play().catch(() => {});
    }
    els.downloadLink.href = resultUrl;
    els.downloadLink.download = filename;
    els.resultActions.hidden = false;

    const file = new File([blob], filename, { type: blob.type });
    const canShare = navigator.canShare && navigator.canShare({ files: [file] });
    els.shareBtn.hidden = !canShare;
    els.shareBtn.onclick = () => {
      navigator.share({ files: [file], title: 'Lockloop wallpaper' }).catch(() => {});
    };
  }

  function closeDialog() {
    if (exporting) return;
    els.resultVideo.pause();
    els.resultVideo.removeAttribute('src');
    els.dialog.close();
  }

  // ---------------------------------------------------------------- boot
  buildDeviceSelect();
  buildSceneChips();
  buildPalettes();
  buildOverlaySelect();
  bindControls();
  showGuideTab(currentDevice().platform === 'android' ? 'samsung' : 'ios');
  if (state.scene === 'photo') state.scene = 'liquid';
  syncUI();
  window.addEventListener('resize', sizePreview);
  setInterval(updateClock, 15000);
  requestAnimationFrame(tick);
})();
