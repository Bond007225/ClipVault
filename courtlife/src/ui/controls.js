// Tiny DOM helpers for the creator panels. No framework needed.

export function el(tag, attrs = {}, ...children) {
  const node = document.createElement(tag);
  for (const [k, v] of Object.entries(attrs)) {
    if (v == null || v === false) continue;
    if (k.startsWith('on')) node.addEventListener(k.slice(2).toLowerCase(), v);
    else if (k === 'class') node.className = v;
    else if (k === 'style' && typeof v === 'object') Object.assign(node.style, v);
    else if (k in node && typeof v !== 'string') node[k] = v;
    else node.setAttribute(k, v === true ? '' : v);
  }
  for (const c of children.flat()) if (c != null && c !== false) node.append(c instanceof Node ? c : String(c));
  return node;
}

export function section(title, ...children) {
  return el('div', { class: 'section' }, el('h3', {}, title), ...children);
}

export function slider({ label, min, max, step = 1, value, format = (v) => v, onInput, onChange }) {
  const out = el('span', { class: 'value' }, format(value));
  const input = el('input', { type: 'range', min, max, step, value });
  input.addEventListener('input', () => {
    const v = Number(input.value);
    const allowed = onInput?.(v);
    if (Number.isFinite(allowed) && allowed !== v) input.value = allowed;
    out.textContent = format(Number(input.value));
  });
  if (onChange) input.addEventListener('change', () => onChange(Number(input.value)));
  const row = el('label', { class: 'row slider' }, el('span', { class: 'label' }, label), input, out);
  row.input = input;
  row.output = out;
  return row;
}

export function select({ label, options, value, onChange }) {
  const s = el('select', {}, ...Object.entries(options).map(([k, v]) => el('option', { value: k, selected: k === value }, v)));
  s.addEventListener('change', () => onChange(s.value));
  return el('label', { class: 'row' }, el('span', { class: 'label' }, label), s);
}

/** Button grid; nicer than a dropdown for visual choices like hair. */
export function choiceGrid({ label, options, value, onChange }) {
  const grid = el('div', { class: 'choices' });
  for (const [k, v] of Object.entries(options)) {
    grid.append(
      el('button', {
        class: `choice${k === value ? ' active' : ''}`,
        type: 'button',
        onClick: () => {
          grid.querySelectorAll('.choice').forEach((b) => b.classList.remove('active'));
          grid.querySelector(`[data-k="${k}"]`).classList.add('active');
          onChange(k);
        },
        'data-k': k,
      }, v),
    );
  }
  return el('div', { class: 'row-block' }, label ? el('span', { class: 'label' }, label) : null, grid);
}

export function colorPicker({ label, value, onInput, presets = [] }) {
  const input = el('input', { type: 'color', value });
  input.addEventListener('input', () => onInput(input.value));
  const swatches = presets.map((c) =>
    el('button', {
      class: 'swatch', type: 'button', style: { background: c }, title: c,
      onClick: () => {
        input.value = c;
        onInput(c);
      },
    }),
  );
  return el('label', { class: 'row color' }, el('span', { class: 'label' }, label), el('div', { class: 'swatches' }, ...swatches, input));
}

export function toggle({ label, value, onChange }) {
  const input = el('input', { type: 'checkbox', checked: value });
  input.addEventListener('change', () => onChange(input.checked));
  return el('label', { class: 'row toggle' }, el('span', { class: 'label' }, label), input);
}

export function toast(message, kind = 'info') {
  const t = el('div', { class: `toast ${kind}` }, message);
  document.body.append(t);
  setTimeout(() => t.classList.add('show'), 10);
  setTimeout(() => {
    t.classList.remove('show');
    setTimeout(() => t.remove(), 300);
  }, 2600);
}

export const TEAM_COLORS = ['#1d428a', '#ffc72c', '#c8102e', '#552583', '#fdb927', '#007a33', '#000000', '#ffffff', '#ce1141', '#00788c', '#f58426', '#5a2d81'];
