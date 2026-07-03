/* audit.js — deterministic detail gate (design-loop-protocol §7 AUDIT)
 *
 * Use: after page load, inject this whole file via evaluate and evaluate `JSON.stringify(__ultraAudit())`.
 *   Optional: set window.__DESIGN_TOKENS = { fonts:["Pretendard","JetBrains Mono"], maxFontSizes:8 }
 *   before injection to check against the DESIGN.md allowances (otherwise the body font + one mono family are allowed by default).
 * Output: { page, pass, counts, violations:{ clipped, fontDrift, deadCandidates, shell, overflowX, contrast } }
 * Principle: check only what a machine can decide for certain — taste judgments belong to RE-SCORE (cold multi-model).
 */
function __ultraAudit() {
  const T = (window.__DESIGN_TOKENS || {});
  const vis = el => {
    const r = el.getBoundingClientRect(), s = getComputedStyle(el);
    return r.width > 1 && r.height > 1 && s.visibility !== 'hidden' && s.display !== 'none' && s.opacity !== '0';
  };
  const sel = el => {
    let p = el.tagName.toLowerCase();
    if (el.id) return p + '#' + el.id;
    if (el.classList.length) p += '.' + el.classList[0];
    const t = (el.textContent || '').trim().slice(0, 24);
    return p + (t ? `("${t}")` : '');
  };

  /* 1. clipped — buttons/labels short on typeset pixels (words cut off). Allow 1px horizontally, 3px line-height slack vertically. */
  const clipped = [];
  document.querySelectorAll('button, a, [role="button"], label, .btn, th, [class*="badge"], [class*="chip"], [class*="tab"]')
    .forEach(el => {
      if (!vis(el) || !(el.textContent || '').trim()) return;
      const s = getComputedStyle(el);
      const hidden = s.overflow === 'hidden' || s.overflowX === 'hidden';
      const cutX = el.scrollWidth > el.clientWidth + 1;
      const cutY = el.scrollHeight > el.clientHeight + 3;
      const ellipsized = s.textOverflow === 'ellipsis' && cutX; // intentional ellipsis still counts as clipping on buttons/chips
      if ((hidden && (cutX || cutY)) || ellipsized || (!hidden && cutY))
        clipped.push({ el: sel(el), scroll: [el.scrollWidth, el.scrollHeight], box: [el.clientWidth, el.clientHeight] });
    });

  /* 2. fontDrift — font families outside the allowance / type scale over budget. */
  const famOf = s => s.split(',')[0].replace(/["']/g, '').trim().toLowerCase();
  const allow = new Set((T.fonts || [famOf(getComputedStyle(document.body).fontFamily)])
    .map(f => String(f).toLowerCase()));
  ['monospace', 'ui-monospace'].forEach(m => allow.add(m));
  const fams = {}, sizes = new Set(), famOff = [];
  document.querySelectorAll('body *').forEach(el => {
    if (!el.textContent || !el.textContent.trim() || !vis(el)) return;
    if (el.children.length && ![...el.childNodes].some(n => n.nodeType === 3 && n.textContent.trim())) return;
    const s = getComputedStyle(el), f = famOf(s.fontFamily);
    fams[f] = (fams[f] || 0) + 1;
    sizes.add(s.fontSize);
    if (![...allow].some(a => f.includes(a) || a.includes(f)) && famOff.length < 12)
      famOff.push({ el: sel(el), font: f });
  });
  const fontDrift = {
    families: Object.keys(fams),
    offenders: famOff,
    distinctSizes: sizes.size,
    sizeBudget: T.maxFontSizes || 8,
    sizeOver: sizes.size > (T.maxFontSizes || 8)
  };

  /* 3. deadCandidates — interactive-looking elements with no destination/handler marker.
   *    (dynamic listeners are invisible statically — these are candidates only; the truth is decided by VERIFY §8 task-walk clicks.
   *     Only elements with a justification written in the FLOW.md §3 button map are exempt.) */
  const dead = [];
  document.querySelectorAll('a, button, [role="button"]').forEach(el => {
    if (!vis(el)) return;
    const href = el.getAttribute('href');
    /* Caution: for a <button> outside a form, el.type defaults to "submit" — judging wiring by type lets everything slip through.
     *       submit only has meaning inside a form → recognize it solely via closest('form'). */
    const wired = el.onclick || el.getAttribute('onclick') || el.dataset.nav || el.dataset.href ||
      el.closest('form');
    const deadHref = el.tagName === 'A' && (!href || href === '#' || href.trim() === '');
    if ((deadHref && !wired) || (el.tagName !== 'A' && !wired)) dead.push(sel(el));
  });

  /* 4. shell — signals of a meaningless hollow page. */
  const bodyText = (document.body.innerText || '').trim();
  const placeholders = (bodyText.match(/lorem|ipsum|placeholder|TODO|TBD|sample ?data|example ?text|content ?here|coming soon/gi) || []);
  let blankCanvas = 0, canvases = document.querySelectorAll('canvas');
  canvases.forEach(c => {
    if (!c.width || !c.height) { blankCanvas++; return; }
    try {
      const x = c.getContext('2d');
      if (!x) return; // webgl etc. — verdict deferred
      const d = x.getImageData(0, 0, Math.min(c.width, 64), Math.min(c.height, 64)).data;
      let uniform = true;
      for (let i = 4; i < d.length; i += 4)
        if (d[i] !== d[0] || d[i + 1] !== d[1] || d[i + 2] !== d[2]) { uniform = false; break; }
      if (uniform) blankCanvas++;
    } catch (e) { /* tainted etc. — deferred */ }
  });
  const interactive = document.querySelectorAll('a[href]:not([href="#"]), button, input, select, textarea').length;
  /* Hard signals (any one alone means shell): placeholder text · blank canvas.
   * Soft signals (must overlap to count as shell): sparse body text + nothing to do — prevents false positives
   * on legitimately terse pages like login (enough interactive elements passes). */
  const hard = [], soft = [];
  if (placeholders.length) hard.push(`placeholder ${placeholders.length} occurrence(s): ${[...new Set(placeholders.map(p => p.toLowerCase()))].join(',')}`);
  if (blankCanvas) hard.push(`blank canvas ${blankCanvas}/${canvases.length}`);
  if (bodyText.length < 200) soft.push(`body text ${bodyText.length} chars (<200)`);
  if (interactive < 3) soft.push(`interactive elements ${interactive} (<3)`);
  const shell = { pass: hard.length === 0 && soft.length < 2, reasons: [...hard, ...soft] };

  /* 5. overflowX — horizontal page scroll (broken layout). */
  const overflowX = document.documentElement.scrollWidth > document.documentElement.clientWidth + 1;

  /* 6. contrast — worst-case WCAG AA for text on solid backgrounds (best-effort). */
  const lum = (r, g, b) => {
    const f = v => { v /= 255; return v <= 0.03928 ? v / 12.92 : Math.pow((v + 0.055) / 1.055, 2.4); };
    return 0.2126 * f(r) + 0.7152 * f(g) + 0.0722 * f(b);
  };
  const rgb = s => { const m = s.match(/rgba?\(([\d.]+)[, ]+([\d.]+)[, ]+([\d.]+)(?:[, /]+([\d.]+))?/); return m ? [+m[1], +m[2], +m[3], m[4] === undefined ? 1 : +m[4]] : null; };
  const bgOf = el => { for (let e = el; e; e = e.parentElement) { const c = rgb(getComputedStyle(e).backgroundColor); if (c && c[3] > 0.9) return c; } return null; };
  const contrast = [];
  document.querySelectorAll('body *').forEach(el => {
    if (contrast.length >= 12 || !vis(el)) return;
    if (![...el.childNodes].some(n => n.nodeType === 3 && n.textContent.trim())) return;
    const s = getComputedStyle(el), fg = rgb(s.color), bg = bgOf(el);
    if (!fg || !bg) return;
    const L1 = lum(fg[0], fg[1], fg[2]), L2 = lum(bg[0], bg[1], bg[2]);
    const ratio = (Math.max(L1, L2) + 0.05) / (Math.min(L1, L2) + 0.05);
    const large = parseFloat(s.fontSize) >= 24 || (parseFloat(s.fontSize) >= 18.66 && +s.fontWeight >= 700);
    if (ratio < (large ? 3 : 4.5)) contrast.push({ el: sel(el), ratio: +ratio.toFixed(2), need: large ? 3 : 4.5 });
  });

  const counts = { clipped: clipped.length, fontOffenders: famOff.length, deadCandidates: dead.length, contrast: contrast.length };
  const pass = !counts.clipped && !counts.deadCandidates && !famOff.length && !fontDrift.sizeOver &&
    shell.pass && !overflowX && !counts.contrast;
  return { page: location.pathname, pass, counts, violations: { clipped, fontDrift, deadCandidates: dead, shell, overflowX, contrast } };
}
