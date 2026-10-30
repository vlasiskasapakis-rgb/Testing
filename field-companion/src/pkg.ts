// The package of a testimony: testimony.json and info.txt, generated from what is on the device (never edited by hand).
import type { Consent, Item, Kind, Testimony } from './types';

export interface PackageItem { order: number; type: Kind; file: string; title: string; lat: number | null; lon: number | null; accuracy: number | null; time: string }
export interface PackageJson {
  id: string; title: string; site: string; collector: string; created: string;
  consent: Consent; items: PackageItem[];
}

/** 1 → "001.webm" */
export function itemFileName(order: number, ext: string): string {
  return String(order).padStart(3, '0') + '.' + ext;
}

/** The file extension for a recording's format: webm, ogg, m4a (audio in MP4), mp4 (video), jpg. */
export function extFor(mime: string, kind: Kind): string {
  const m = mime.toLowerCase();
  if (kind === 'photo' || m.startsWith('image/')) return 'jpg';
  if (m.includes('webm')) return 'webm';
  if (m.includes('ogg')) return 'ogg';
  if (m.includes('mp4') || m.includes('aac') || m.includes('m4a')) return kind === 'audio' ? 'm4a' : 'mp4';
  if (m.includes('quicktime')) return 'mov';
  return kind === 'audio' ? 'webm' : 'mp4';
}

export function buildPackage(t: Testimony, items: Item[], site: string, collector: string): PackageJson {
  if (!t.consent) throw new Error('no consent');
  return {
    id: t.id, title: t.title, site, collector, created: t.created,
    consent: t.consent.type === 'spoken' ? { type: 'spoken', file: t.consent.file } : { type: 'form', licence: t.consent.licence, anonymous: t.consent.anonymous },
    items: items.slice().sort((a, b) => a.order - b.order).map((i) => ({
      order: i.order, type: i.type, file: i.file, title: i.title, lat: i.lat, lon: i.lon, accuracy: i.accuracy, time: i.time,
    })),
  };
}

export function testimonyJson(p: PackageJson): string {
  return JSON.stringify(p, null, 2) + '\n';
}

const KIND_EL: Record<Kind, string> = { audio: 'Ήχος', video: 'Βίντεο', photo: 'Φωτογραφία' };

function whenEl(iso: string, timeZone?: string): string {
  const d = new Date(iso);
  if (isNaN(d.getTime())) return iso;
  return d.toLocaleString('el-GR', { timeZone, year: 'numeric', month: '2-digit', day: '2-digit', hour: '2-digit', minute: '2-digit', second: '2-digit', hour12: false });
}

/** The same information as testimony.json, in plain Greek for people. */
export function infoTxt(p: PackageJson, timeZone?: string): string {
  const L: string[] = [];
  L.push('Walking Memory – Μαρτυρία από το πεδίο', '');
  L.push('Τίτλος: ' + p.title);
  L.push('Κωδικός μαρτυρίας: ' + p.id);
  L.push('Τόπος (κωδικός): ' + p.site);
  L.push('Καταγραφή από: ' + p.collector);
  L.push('Δημιουργήθηκε: ' + whenEl(p.created, timeZone) + ' (' + p.created + ')');
  L.push('');
  if (p.consent.type === 'spoken') L.push('Συναίνεση: προφορική, ηχογραφημένη στο αρχείο ' + p.consent.file);
  else L.push('Συναίνεση: υπογεγραμμένο έντυπο συναίνεσης · Άδεια: ' + p.consent.licence + ' · Ανωνυμία: ' + (p.consent.anonymous ? 'ναι' : 'όχι'));
  L.push('');
  L.push('Στοιχεία (' + p.items.length + '):');
  p.items.forEach((i) => {
    const where = i.lat != null && i.lon != null
      ? 'θέση ' + i.lat.toFixed(6) + ', ' + i.lon.toFixed(6) + (i.accuracy != null ? ' (±' + Math.round(i.accuracy) + ' μ.)' : '')
      : 'θέση άγνωστη';
    L.push('  ' + String(i.order).padStart(3, '0') + '. ' + KIND_EL[i.type] + ' · «' + i.title + '» · ' + whenEl(i.time, timeZone) + ' · ' + where + ' · αρχείο ' + i.file);
  });
  L.push('');
  L.push('Τα αρχεία είναι ακατέργαστα (χωρίς επεξεργασία). Δεν δημοσιεύονται από την εφαρμογή.');
  return L.join('\n') + '\n';
}

/** The order in which a testimony's files are sent: the consent recording, the items, then info.txt and, last,
 *  testimony.json (its arrival means the testimony is complete). */
export function sendOrder(t: Testimony, items: Item[]): string[] {
  const out: string[] = [];
  if (t.consent && t.consent.type === 'spoken') out.push(t.consent.file);
  items.slice().sort((a, b) => a.order - b.order).forEach((i) => out.push(i.file));
  out.push('info.txt', 'testimony.json');
  return out;
}

/** What still stops a testimony from being sent. */
export function sendProblems(t: Testimony, items: Item[]): string[] {
  const p: string[] = [];
  if (!t.consent) p.push('consent');
  if (!items.length) p.push('items');
  if (items.some((i) => !i.complete)) p.push('recording');
  if (items.some((i) => !i.title.trim())) p.push('titles');
  return p;
}

/** "https://cloud.example.org/index.php/s/AbC123" → { origin, token } */
export function parseShare(link: string): { origin: string; token: string } | null {
  try {
    const u = new URL(link.trim());
    const m = /\/s\/([A-Za-z0-9]+)\/?$/.exec(u.pathname);
    if (!m || u.protocol !== 'https:') return null;
    const prefix = u.pathname.slice(0, u.pathname.indexOf('/s/')).replace(/\/index\.php$/, '');
    return { origin: u.origin + prefix, token: m[1] };
  } catch { return null; }
}
