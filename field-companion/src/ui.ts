// The screens: first launch, home, new testimony (title + consent), a testimony (capture, items, map, sending).
import { t, setLang, getLang, LICENCES } from './i18n';
import { appendFile, flushFile, readFile, removeFile, removeTestimonyFiles, storageKind } from './files';
import { canRecord, keepAwake, openStream, pickMime, Recording, snapshot, stopStream } from './media';
import { locate, ROUGH_M } from './geo';
import { checkShare } from './nextcloud';
import { extFor, itemFileName, sendProblems } from './pkg';
import { sendTestimony } from './send';
import { showMap } from './map';
import { deleteItem, deleteTestimonyMeta, getSetting, getTestimony, listItems, listTestimonies, putItem, putTestimony, setSetting } from './store';
import type { Item, Kind, Settings, SiteConfig, Testimony } from './types';

// ---------- helpers ----------
type Attrs = Record<string, string | boolean | ((e: Event) => void) | undefined>;
function h(tag: string, attrs?: Attrs | null, ...kids: (Node | string | null | undefined | false)[]): HTMLElement {
  const e = document.createElement(tag);
  if (attrs) for (const k of Object.keys(attrs)) {
    const v = attrs[k];
    if (v === undefined || v === false) continue;
    if (typeof v === 'function') e.addEventListener(k.slice(2), v as EventListener);
    else if (v === true) e.setAttribute(k, '');
    else e.setAttribute(k, v);
  }
  for (const c of kids) if (c !== null && c !== undefined && c !== false) e.append(c);
  return e;
}
const app = (): HTMLElement => document.getElementById('app') as HTMLElement;
function uuid(): string {
  if (crypto.randomUUID) return crypto.randomUUID();
  const b = crypto.getRandomValues(new Uint8Array(16)); b[6] = (b[6] & 15) | 64; b[8] = (b[8] & 63) | 128;
  const x = Array.from(b, (n) => n.toString(16).padStart(2, '0')).join('');
  return x.slice(0, 8) + '-' + x.slice(8, 12) + '-' + x.slice(12, 16) + '-' + x.slice(16, 20) + '-' + x.slice(20);
}
function fmt(iso: string): string {
  const d = new Date(iso);
  return isNaN(d.getTime()) ? iso : d.toLocaleString(getLang() === 'el' ? 'el-GR' : 'en-GB', { dateStyle: 'medium', timeStyle: 'short' });
}
function mmss(s: number): string { s = Math.floor(s); return String(Math.floor(s / 60)).padStart(2, '0') + ':' + String(s % 60).padStart(2, '0'); }
let toastTimer = 0;
export function toast(msg: string, action?: { label: string; run: () => void }): void {
  const box = document.getElementById('toast') as HTMLElement;
  box.innerHTML = ''; box.append(h('span', null, msg));
  if (action) box.append(h('button', { type: 'button', onclick: () => { box.hidden = true; action.run(); } }, action.label));
  box.hidden = false; clearTimeout(toastTimer);
  toastTimer = window.setTimeout(() => { box.hidden = true; }, action ? 12000 : 5000);
}
function header(title: string, back?: string): HTMLElement {
  return h('header', { class: 'top' },
    back ? h('a', { class: 'back', href: back }, t('back')) : h('span', { class: 'brand' }, t('appName')),
    h('h1', null, title),
    h('button', { type: 'button', class: 'ghost', onclick: () => { setLang(getLang() === 'el' ? 'en' : 'el'); route(); } }, t('lang')));
}
function confirmAsk(msg: string): boolean { return window.confirm(msg); }

// ---------- state ----------
let settings: Settings | null = null;
let siteCfg: SiteConfig | null = null;
const sentThisSession: string[] = [];
let busy = false;            // recording or sending: no navigation surprises
let activeItem = '';          // the item being recorded right now

export async function boot(): Promise<void> {
  settings = (await getSetting<Settings>('settings')) || null;
  siteCfg = (await getSetting<SiteConfig>('siteCfg')) || null;
  window.addEventListener('hashchange', () => { if (!busy) route(); });
  window.addEventListener('online', () => { void offerUnsent(); });
  route();
  if (navigator.onLine) void offerUnsent(true);
}

export function route(): void {
  if (!settings || !siteCfg) { renderSetup(); return; }
  const hsh = location.hash.replace(/^#\/?/, '');
  const [v, id] = hsh.split('/');
  if (v === 'new') renderNew();
  else if (v === 't' && id) void renderTestimony(id);
  else if (v === 'settings') renderSettings();
  else void renderHome();
  window.scrollTo(0, 0);
}

// ---------- first launch ----------
async function loadSites(): Promise<Record<string, SiteConfig>> {
  const r = await fetch('sites.json', { cache: 'no-store' });
  if (!r.ok) throw new Error('sites ' + r.status);
  const j = await r.json();
  const out: Record<string, SiteConfig> = {};
  Object.keys(j.sites || {}).forEach((k) => { out[k.toUpperCase()] = j.sites[k]; });
  return out;
}

function renderSetup(): void {
  const root = app(); root.innerHTML = '';
  const code = h('input', { id: 'suCode', type: 'text', autocomplete: 'off', autocapitalize: 'characters', maxlength: '20', required: true }) as HTMLInputElement;
  const name = h('input', { id: 'suName', type: 'text', autocomplete: 'name', maxlength: '80', required: true }) as HTMLInputElement;
  code.value = settings?.site || ''; name.value = settings?.collector || '';
  const err = h('p', { class: 'err', role: 'alert' });
  const btn = h('button', { type: 'submit', class: 'big primary' }, t('start')) as HTMLButtonElement;
  const form = h('form', { class: 'card', novalidate: true },
    h('p', { class: 'lead' }, t('setupLead')),
    h('label', { for: 'suCode' }, t('siteCode')), code,
    h('label', { for: 'suName' }, t('yourName')), name, err, btn);
  form.addEventListener('submit', async (ev) => {
    ev.preventDefault(); err.textContent = '';
    const c = code.value.trim().toUpperCase(), n = name.value.replace(/\s+/g, ' ').trim();
    if (!n) { err.textContent = t('needName'); name.focus(); return; }
    btn.disabled = true; btn.textContent = t('checking');
    try {
      const sites = await loadSites();
      if (!c || !sites[c]) { err.textContent = t('badSite'); code.focus(); return; }
      settings = { site: c, collector: n }; siteCfg = sites[c];
      await setSetting('settings', settings); await setSetting('siteCfg', siteCfg);
      try { if (navigator.storage && navigator.storage.persist) await setSetting('persisted', await navigator.storage.persist()); } catch { /* not supported */ }
      location.hash = '#'; route();
    } catch { err.textContent = t('needOnline'); }
    finally { btn.disabled = false; btn.textContent = t('start'); }
  });
  root.append(header(t('setupTitle')), h('main', null, form));
  code.focus();
}

// ---------- home ----------
async function eligible(): Promise<Testimony[]> {
  const out: Testimony[] = [];
  for (const x of await listTestimonies()) if (!sendProblems(x, await listItems(x.id)).length) out.push(x);
  return out;
}
async function offerUnsent(quiet = false): Promise<void> {
  if (!navigator.onLine || busy || !settings) return;
  const list = await eligible();
  if (!list.length) return;
  if (!location.hash || location.hash === '#') { void renderHome(); return; }
  if (!quiet) toast(t('unsentBanner', { n: list.length }), { label: t('sendNow'), run: () => { void sendMany(list.map((x) => x.id)); } });
}

async function warnings(): Promise<HTMLElement> {
  const box = h('div', { class: 'warns' });
  if (!window.isSecureContext) box.append(h('p', { class: 'warn' }, t('httpsWarn')));
  if (!canRecord()) box.append(h('p', { class: 'warn' }, t('noRecord')));
  try {
    if (navigator.storage && navigator.storage.persisted && !(await navigator.storage.persisted())) box.append(h('p', { class: 'warn' }, t('persistWarn')));
    if (navigator.storage && navigator.storage.estimate) {
      const e = await navigator.storage.estimate();
      if (e.quota && e.usage != null && e.quota - e.usage < 300 * 1024 * 1024) box.append(h('p', { class: 'warn' }, t('lowSpace', { mb: Math.round((e.quota - e.usage) / 1048576) })));
    }
  } catch { /* not supported */ }
  if (!(window.matchMedia && window.matchMedia('(display-mode: standalone)').matches) && !(navigator as any).standalone) box.append(h('p', { class: 'tip' }, t('install')));
  return box;
}

async function renderHome(): Promise<void> {
  const root = app(); root.innerHTML = '';
  const main = h('main');
  root.append(h('header', { class: 'top' }, h('span', { class: 'brand' }, t('appName')),
    h('a', { class: 'ghost', href: '#settings', 'aria-label': t('settings') }, '⚙'),
    h('button', { type: 'button', class: 'ghost', onclick: () => { setLang(getLang() === 'el' ? 'en' : 'el'); route(); } }, t('lang'))), main);
  main.append(await warnings());
  const list = await listTestimonies();
  const ready = navigator.onLine ? await eligible() : [];
  if (ready.length) main.append(h('div', { class: 'banner' }, h('span', null, t('unsentBanner', { n: ready.length })),
    h('button', { type: 'button', class: 'primary', onclick: () => { void sendMany(ready.map((x) => x.id)); } }, t('sendNow'))));
  if (sentThisSession.length) main.append(h('div', { class: 'card sentlist' }, h('h2', null, t('sentSession')),
    h('ul', null, ...sentThisSession.map((x) => h('li', null, '✓ ' + x + ' · ' + t('st_sent'))))));
  if (!list.length) main.append(h('p', { class: 'empty' }, t('noTestimonies')));
  const ul = h('ul', { class: 'tlist' });
  for (const x of list) {
    const n = (await listItems(x.id)).length;
    const st = x.sent.length ? 'partial' : 'unsent';
    ul.append(h('li', null, h('a', { href: '#t/' + x.id },
      h('b', null, x.title),
      h('span', null, fmt(x.created) + ' · ' + (n === 1 ? t('nItems1') : t('nItems', { n }))),
      h('span', { class: 'chip ' + st }, t('st_' + st)))));
  }
  main.append(ul);
  main.append(h('a', { class: 'fab', href: '#new', 'aria-label': t('newT') }, '+'));
}

// ---------- settings ----------
function renderSettings(): void {
  const root = app(); root.innerHTML = '';
  const out = h('p', { role: 'status', class: 'note' });
  root.append(header(t('settings'), '#'), h('main', null, h('div', { class: 'card' },
    h('p', null, t('site') + ': ', h('b', null, settings!.site + (siteCfg?.name ? ' – ' + siteCfg.name : ''))),
    h('p', null, t('collector') + ': ', h('b', null, settings!.collector)),
    h('button', { type: 'button', class: 'big', onclick: () => { siteCfg = null; renderSetup(); } }, t('change')),
    h('button', { type: 'button', class: 'big', onclick: async () => { out.textContent = t('checking'); out.textContent = t('conn_' + (await checkShare(siteCfg!))); } }, t('checkConn')),
    out,
    h('p', { class: 'note' }, t('storage', { k: storageKind() === 'opfs' ? 'OPFS' : 'IndexedDB' })))));
}

// ---------- new testimony ----------
function renderNew(): void {
  const root = app(); root.innerHTML = '';
  const title = h('input', { id: 'ntTitle', type: 'text', maxlength: '120', placeholder: t('tTitlePh'), required: true }) as HTMLInputElement;
  const err = h('p', { class: 'err', role: 'alert' });
  const form = h('form', { class: 'card', novalidate: true }, h('label', { for: 'ntTitle' }, t('tTitle')), title, err,
    h('button', { type: 'submit', class: 'big primary' }, t('next')));
  form.addEventListener('submit', async (ev) => {
    ev.preventDefault();
    const v = title.value.replace(/\s+/g, ' ').trim();
    if (!v) { err.textContent = t('needTTitle'); title.focus(); return; }
    const x: Testimony = { id: uuid(), title: v.slice(0, 120), created: new Date().toISOString(), consent: null, nextOrder: 1, sent: [] };
    await putTestimony(x);
    location.hash = '#t/' + x.id;
  });
  root.append(header(t('newT'), '#'), h('main', null, form));
  title.focus();
}

// ---------- one testimony ----------
async function renderTestimony(id: string): Promise<void> {
  const x = await getTestimony(id);
  if (!x) { location.hash = '#'; return; }
  let items = await listItems(id);
  // a recording interrupted by a closed app: keep what was written; it needs a title
  for (const i of items) if (!i.complete && i.id !== activeItem) { i.complete = true; await putItem(i); }
  items = await listItems(id);
  const root = app(); root.innerHTML = '';
  const main = h('main');
  root.append(header(x.title, '#'), main);

  // consent
  const cbox = h('section', { class: 'card', 'aria-labelledby': 'cH' }, h('h2', { id: 'cH' }, t('consentTitle')));
  if (x.consent) {
    cbox.append(h('p', { class: 'ok' }, x.consent.type === 'spoken' ? t('consentSpokenDone')
      : t('consentFormDone', { l: x.consent.licence, a: x.consent.anonymous ? t('yes') : t('no') })));
    if (x.consent.type === 'spoken') { const f = x.consent.file; cbox.append(h('button', { type: 'button', onclick: () => { void viewFile(x, f, x.consentMime || '', 'audio'); } }, t('play'))); }
  } else {
    cbox.append(h('p', { class: 'lead' }, t('consentLead')),
      h('button', { type: 'button', class: 'big', onclick: () => { void capture(x, 'consent'); } }, t('consentSpoken')),
      consentForm(x));
  }
  main.append(cbox);

  // capture
  const locked = !x.consent;
  const cap = h('section', { class: 'card capbtns', 'aria-label': t('record') },
    ...(['audio', 'video', 'photo'] as Kind[]).map((k) => h('button', { type: 'button', class: 'cap ' + k, disabled: locked || !canRecord(), onclick: () => { void capture(x, k); } },
      h('span', { class: 'ico', 'aria-hidden': 'true' }, k === 'audio' ? '🎙' : k === 'video' ? '🎬' : '📷'), t(k))));
  if (locked) cap.append(h('p', { class: 'note' }, t('captureLocked')));
  main.append(cap);

  // items
  const sec = h('section', { class: 'card', 'aria-labelledby': 'iH' }, h('h2', { id: 'iH' }, t('items') + ' (' + items.length + ')'));
  if (!items.length) sec.append(h('p', { class: 'empty' }, t('none')));
  const ol = h('ol', { class: 'items' });
  items.forEach((i) => {
    const acc = Math.round(i.accuracy || 0);
    const where = i.lat != null ? '📍 ±' + (acc >= 1000 ? (acc / 1000).toFixed(1) + ' km' : acc + ' m') + (acc > ROUGH_M ? ' ⚠ ' + t('roughLoc') : '') : t('noLocation');
    ol.append(h('li', null,
      h('div', { class: 'ititle' }, h('span', { class: 'no' }, String(i.order).padStart(3, '0')), (i.type === 'audio' ? '🎙 ' : i.type === 'video' ? '🎬 ' : '📷 '),
        i.title ? h('b', null, i.title) : h('b', { class: 'need' }, '⚠ ' + t('needTitle'))),
      h('div', { class: 'imeta' }, fmt(i.time) + ' · ' + where + (x.sent.includes(i.file) ? ' · ' + t('st_sent') : '')),
      h('div', { class: 'iact' },
        h('button', { type: 'button', onclick: () => { void viewFile(x, i.file, i.mime, i.type); } }, t('play')),
        h('button', { type: 'button', disabled: x.sent.includes(i.file), onclick: async () => {
          const v = await askTitle(i.title); if (v === null) return; i.title = v; await putItem(i); void renderTestimony(id); } }, t('rename')),
        h('button', { type: 'button', class: 'danger', disabled: x.sent.includes(i.file), onclick: async () => {
          if (!confirmAsk(t('delItemQ', { t: i.title || i.file }))) return;
          await removeFile(x.id, i.file); await deleteItem(i.id); void renderTestimony(id); } }, t('del')))));
  });
  sec.append(ol);
  main.append(sec);

  // map
  const mapBox = h('div', { class: 'map', id: 'map', role: 'region', 'aria-label': t('map') });
  const mapSec = h('section', { class: 'card' }, h('h2', null, t('map')), mapBox, h('p', { class: 'note' }, t('mapNote')));
  main.append(mapSec);
  showMap(mapBox, items, (i) => { void viewFile(x, i.file, i.mime, i.type); });
  mapSec.hidden = mapBox.hidden;

  // sending
  const probs = sendProblems(x, items);
  const out = h('p', { role: 'status', class: 'note', 'aria-live': 'polite' });
  const send = h('button', { type: 'button', class: 'big primary', disabled: !!probs.length, onclick: () => { void sendOne(x, out, send as HTMLButtonElement); } }, t('sendAll'));
  if (probs.length && x.consent) out.textContent = t('cannotSend', { p: probs.map((p) => t('pr_' + p)).join(', ') });
  main.append(h('section', { class: 'card' }, send, out,
    h('button', { type: 'button', class: 'danger small', onclick: async () => {
      if (!confirmAsk(t('delTestimonyQ', { t: x.title }))) return;
      await removeTestimonyFiles(x.id); await deleteTestimonyMeta(x.id); location.hash = '#'; } }, t('delTestimony'))));
}

function consentForm(x: Testimony): HTMLElement {
  const signed = h('input', { type: 'checkbox', id: 'cfSigned' }) as HTMLInputElement;
  const lic = h('select', { id: 'cfLic' }, ...LICENCES.map((l) => h('option', { value: l }, l))) as HTMLSelectElement;
  lic.value = 'CC BY';
  const anonYes = h('input', { type: 'radio', name: 'cfAnon', value: 'yes', id: 'cfAnonY' }) as HTMLInputElement;
  const anonNo = h('input', { type: 'radio', name: 'cfAnon', value: 'no', id: 'cfAnonN' }) as HTMLInputElement;
  const err = h('p', { class: 'err', role: 'alert' });
  const box = h('details', { class: 'cform' }, h('summary', { class: 'big' }, t('consentForm')),
    h('label', { class: 'check' }, signed, t('formSigned')),
    h('label', { for: 'cfLic' }, t('licence')), lic,
    h('fieldset', null, h('legend', null, t('anonymous')),
      h('label', { class: 'check' }, anonYes, t('yes')), h('label', { class: 'check' }, anonNo, t('no'))),
    err,
    h('button', { type: 'button', class: 'big primary', onclick: async () => {
      if (!signed.checked || (!anonYes.checked && !anonNo.checked)) { err.textContent = t('needSigned'); return; }
      x.consent = { type: 'form', licence: lic.value, anonymous: anonYes.checked };
      await putTestimony(x); void renderTestimony(x.id);
    } }, t('saveConsent')));
  return box;
}

// ---------- viewing a file ----------
async function viewFile(x: Testimony, file: string, mime: string, kind: Kind): Promise<void> {
  const blob = await readFile(x.id, file, mime);
  const url = URL.createObjectURL(blob);
  const media = kind === 'photo' ? h('img', { src: url, alt: file }) : h(kind === 'video' ? 'video' : 'audio', { src: url, controls: true, playsinline: true, preload: 'metadata' });
  const d = h('dialog', { class: 'viewer', 'aria-label': file }, media, h('button', { type: 'button', class: 'big', onclick: () => (d as HTMLDialogElement).close() }, t('close'))) as HTMLDialogElement;
  d.addEventListener('close', () => { URL.revokeObjectURL(url); d.remove(); });
  document.body.append(d); d.showModal();
}

/** Asks for an item's title (required). null: the user chose to delete the capture. */
function askTitle(current = '', allowDelete = false): Promise<string | null> {
  return new Promise((resolve) => {
    const inp = h('input', { type: 'text', id: 'atIn', maxlength: '120', placeholder: t('itemTitlePh') }) as HTMLInputElement;
    inp.value = current;
    const save = h('button', { type: 'submit', class: 'big primary', disabled: !current.trim() }, t('save')) as HTMLButtonElement;
    inp.addEventListener('input', () => { save.disabled = !inp.value.trim(); });
    const form = h('form', { method: 'dialog' }, h('label', { for: 'atIn' }, t('itemTitle')), inp, save,
      allowDelete ? h('button', { type: 'button', class: 'danger', onclick: () => { if (confirmAsk(t('discardQ'))) { done(null); } } }, t('discard'))
        : h('button', { type: 'button', onclick: () => done(null) }, t('cancel')));
    const d = h('dialog', { class: 'ask' }, form) as HTMLDialogElement;
    let finished = false;
    function done(v: string | null): void { if (finished) return; finished = true; d.close(); d.remove(); resolve(v); }
    form.addEventListener('submit', (ev) => { ev.preventDefault(); const v = inp.value.replace(/\s+/g, ' ').trim(); if (v) done(v.slice(0, 120)); });
    d.addEventListener('cancel', (ev) => { ev.preventDefault(); });      // the title is required: no Escape
    document.body.append(d); d.showModal(); inp.focus();
  });
}

// ---------- capturing ----------
async function capture(x: Testimony, kind: Kind | 'consent'): Promise<void> {
  const media: Kind = kind === 'consent' ? 'audio' : kind;
  let stream: MediaStream | null = null;
  let facing: 'environment' | 'user' = 'environment';
  const ov = h('div', { class: 'overlay', role: 'dialog', 'aria-modal': 'true', 'aria-label': kind === 'consent' ? t('consentSpoken') : t(kind) });
  const status = h('p', { class: 'recstat', role: 'status', 'aria-live': 'polite' });
  const preview = h('video', { class: 'preview', playsinline: true, autoplay: true, muted: true }) as HTMLVideoElement;
  preview.muted = true;
  const controls = h('div', { class: 'controls' });
  ov.append(h('h2', null, kind === 'consent' ? t('consentSpoken') : t(kind)), media !== 'audio' ? preview : h('div', { class: 'mic', 'aria-hidden': 'true' }, '🎙'), status, controls);
  document.body.append(ov);
  busy = true;
  const close = async () => { stopStream(stream); stream = null; await keepAwake(false); ov.remove(); busy = false; };

  try { stream = await openStream(media, facing); }
  catch { await close(); toast(t('permDenied')); return; }
  if (media !== 'audio') { preview.srcObject = stream; void preview.play().catch(() => undefined); }

  if (media === 'photo') {
    controls.append(
      h('button', { type: 'button', class: 'big primary', onclick: async () => {
        const blob = await snapshot(preview);
        const pos = locate();
        const order = x.nextOrder++; await putTestimony(x);
        const it: Item = { id: uuid(), tid: x.id, order, type: 'photo', file: itemFileName(order, 'jpg'), mime: 'image/jpeg', title: '',
                           lat: null, lon: null, accuracy: null, time: new Date().toISOString(), complete: false };
        await putItem(it); await appendFile(x.id, it.file, blob); it.complete = true; it.size = blob.size; await putItem(it);
        await close();
        void pos.then((p) => setLocation(x.id, it, p));
        await finishItem(x, it);
      } }, t('shutter')),
      h('button', { type: 'button', onclick: async () => {
        facing = facing === 'environment' ? 'user' : 'environment'; stopStream(stream);
        try { stream = await openStream('photo', facing); preview.srcObject = stream; } catch { toast(t('permDenied')); }
      } }, t('switchCam')),
      h('button', { type: 'button', onclick: () => { void close(); } }, t('cancel')));
    return;
  }

  // audio, video, spoken consent: recorded straight to the device, a second at a time
  const mime = pickMime(media === 'video' ? 'video' : 'audio');
  let rec: Recording | null = null;
  let it: Item | null = null;
  let file = '';
  let timer = 0, warned = false;
  const startBtn = h('button', { type: 'button', class: 'big primary' }, t('record')) as HTMLButtonElement;
  const pauseBtn = h('button', { type: 'button', class: 'big', hidden: true }, t('pause')) as HTMLButtonElement;
  const stopBtn = h('button', { type: 'button', class: 'big danger', hidden: true }, t('stop')) as HTMLButtonElement;
  const cancelBtn = h('button', { type: 'button' }, t('cancel')) as HTMLButtonElement;
  controls.append(startBtn, pauseBtn, stopBtn, cancelBtn);
  cancelBtn.onclick = () => { void close(); };
  const tick = () => {
    if (!rec) return;
    const s = rec.elapsed();
    status.textContent = (rec.paused ? t('paused') : '● ' + t('recording')) + ' ' + mmss(s);
    if (media === 'video' && s > 180 && !warned) { warned = true; toast(t('longVideo')); }
  };
  startBtn.onclick = async () => {
    startBtn.hidden = true; cancelBtn.hidden = true;
    const actualMime = mime || (media === 'video' ? 'video/mp4' : 'audio/mp4');
    if (kind === 'consent') {
      file = 'consent.' + extFor(actualMime, 'audio');
      if (x.consentMime) await removeFile(x.id, file);
    } else {
      const order = x.nextOrder++; await putTestimony(x);
      file = itemFileName(order, extFor(actualMime, media));
      it = { id: uuid(), tid: x.id, order, type: media, file, mime: actualMime.split(';')[0], title: '', lat: null, lon: null, accuracy: null,
             time: new Date().toISOString(), complete: false };
      activeItem = it.id;
      await putItem(it);       // saved before the first second: an interruption keeps what was recorded
      const target = it;
      void locate().then((p) => setLocation(x.id, target, p));
    }
    rec = new Recording(stream!, mime, (b) => appendFile(x.id, file, b));
    rec.start(); await keepAwake(true);
    timer = window.setInterval(tick, 500); tick();
    pauseBtn.hidden = media !== 'audio' && kind !== 'consent'; stopBtn.hidden = false;
  };
  pauseBtn.onclick = () => {
    if (!rec) return;
    if (rec.paused) { rec.resume(); pauseBtn.textContent = t('pause'); } else { rec.pause(); pauseBtn.textContent = t('resume'); }
    tick();
  };
  stopBtn.onclick = async () => {
    if (!rec) return;
    stopBtn.disabled = true; pauseBtn.disabled = true; clearInterval(timer);
    try { await rec.stop(); } catch { /* what was written is kept */ }
    await flushFile(x.id, file);
    const realMime = rec.mime;
    await close();
    if (kind === 'consent') {
      x.consent = { type: 'spoken', file }; x.consentMime = realMime; await putTestimony(x);
      void renderTestimony(x.id); return;
    }
    if (it) {
      it.complete = true; it.mime = realMime || it.mime;
      const cur = (await listItems(x.id)).find((y) => y.id === it!.id);
      if (cur) { cur.complete = true; cur.mime = it.mime; await putItem(cur); it = cur; } else await putItem(it);
      activeItem = '';
      await finishItem(x, it);
    }
  };
}

// The location may arrive after the title was saved: only the location fields of the stored item change.
async function setLocation(tid: string, it: Item, p: { lat: number; lon: number; accuracy: number } | null): Promise<void> {
  if (!p) return;
  Object.assign(it, { lat: p.lat, lon: p.lon, accuracy: p.accuracy });
  const cur = (await listItems(tid)).find((y) => y.id === it.id);
  if (!cur) return;                                   // deleted meanwhile
  Object.assign(cur, { lat: p.lat, lon: p.lon, accuracy: p.accuracy }); await putItem(cur);
  if (location.hash === '#t/' + tid && !busy && !document.querySelector('dialog[open]')) void renderTestimony(tid);
}

async function finishItem(x: Testimony, it: Item): Promise<void> {
  const v = await askTitle('', true);
  if (v === null) { await removeFile(x.id, it.file); await deleteItem(it.id); }
  else { const cur = (await listItems(x.id)).find((y) => y.id === it.id) || it; cur.title = v; await putItem(cur); }
  void renderTestimony(x.id);
}

// ---------- sending ----------
async function sendOne(x: Testimony, out: HTMLElement, btn: HTMLButtonElement): Promise<boolean> {
  if (!navigator.onLine) { out.textContent = t('offline'); return false; }
  btn.disabled = true; busy = true; await keepAwake(true);
  const r = await sendTestimony(x.id, settings!, siteCfg!, (i, n) => { out.textContent = t('sending', { i, n }); });
  await keepAwake(false); busy = false; btn.disabled = false;
  if (r.ok) { sentThisSession.push(x.title); toast(t('sentDone', { t: x.title })); if (location.hash.startsWith('#t/')) location.hash = '#'; else void renderHome(); return true; }
  out.textContent = r.error === 'https' ? t('sendHttps') : t('sendFailed', { n: r.total - r.sent }) + ' ' + reason(r.error || '');
  if (location.hash.startsWith('#t/' + x.id)) { const keep = out.textContent; await renderTestimony(x.id); const o = document.querySelector('[role=status].note'); if (o) o.textContent = keep; }
  return false;
}

// Why a send failed, in words: no answer at all (offline, or Nextcloud does not allow this app: CORS), or Nextcloud's answer.
function reason(e: string): string {
  const m = /HTTP (\d+)/.exec(e);
  if (m) {
    const c = +m[1];
    if (c === 401 || c === 403) return t('why_denied', { c });
    if (c === 404) return t('why_notfound', { c });
    if (c === 413 || c === 507) return t('why_full', { c });
    return t('why_http', { c });
  }
  if (e === 'timeout') return t('why_timeout');
  if (e.startsWith('problems:')) return '';
  return t('why_network');
}

async function sendMany(ids: string[]): Promise<void> {
  const out = h('p'); const btn = h('button') as HTMLButtonElement;
  for (const id of ids) {
    const x = await getTestimony(id); if (!x) continue;
    toast(x.title + ' …');
    if (!(await sendOne(x, out, btn))) { toast(out.textContent || ''); break; }
  }
  if (!location.hash || location.hash === '#') void renderHome();
}
