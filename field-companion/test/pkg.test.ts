import { describe, expect, it } from 'vitest';
import { buildPackage, extFor, infoTxt, itemFileName, parseShare, sendOrder, sendProblems, testimonyJson } from '../src/pkg';
import type { Item, Testimony } from '../src/types';

const T: Testimony = { id: '0b9c7a2e-1111-4222-8333-444455556666', title: 'Το πανηγύρι', created: '2026-10-30T08:00:00.000Z',
  consent: { type: 'spoken', file: 'consent.webm' }, nextOrder: 4, sent: [] };
const I = (order: number, type: Item['type'], file: string, title: string, lat: number | null = 39.1, lon: number | null = 26.55): Item =>
  ({ id: 'i' + order, tid: T.id, order, type, file, mime: type === 'photo' ? 'image/jpeg' : 'audio/webm', title, lat, lon, accuracy: lat == null ? null : 12.4, time: '2026-10-30T08:0' + order + ':00.000Z', complete: true });
const items = [I(3, 'photo', '003.jpg', 'Η πλατεία', null, null), I(1, 'audio', '001.webm', 'Αρχή'), I(2, 'video', '002.mp4', 'Χορός')];

describe('package', () => {
  it('names files 001.ext and picks the extension from the format', () => {
    expect(itemFileName(1, 'webm')).toBe('001.webm');
    expect(itemFileName(12, 'jpg')).toBe('012.jpg');
    expect(extFor('audio/webm;codecs=opus', 'audio')).toBe('webm');
    expect(extFor('audio/mp4', 'audio')).toBe('m4a');
    expect(extFor('video/mp4', 'video')).toBe('mp4');
    expect(extFor('image/jpeg', 'photo')).toBe('jpg');
  });
  it('builds testimony.json with the items in order', () => {
    const p = buildPackage(T, items, 'DEMO', 'Μαρία');
    const j = JSON.parse(testimonyJson(p));
    expect(Object.keys(j)).toEqual(['id', 'title', 'site', 'collector', 'created', 'consent', 'items']);
    expect(j.consent).toEqual({ type: 'spoken', file: 'consent.webm' });
    expect(j.items.map((x: { file: string }) => x.file)).toEqual(['001.webm', '002.mp4', '003.jpg']);
    expect(Object.keys(j.items[0])).toEqual(['order', 'type', 'file', 'title', 'lat', 'lon', 'accuracy', 'time']);
    const form = buildPackage({ ...T, consent: { type: 'form', licence: 'CC BY', anonymous: false } }, items, 'DEMO', 'M');
    expect(form.consent).toEqual({ type: 'form', licence: 'CC BY', anonymous: false });
  });
  it('writes info.txt in Greek', () => {
    const txt = infoTxt(buildPackage(T, items, 'DEMO', 'Μαρία'), 'UTC');
    expect(txt).toContain('Τίτλος: Το πανηγύρι');
    expect(txt).toContain('Καταγραφή από: Μαρία');
    expect(txt).toContain('προφορική, ηχογραφημένη στο αρχείο consent.webm');
    expect(txt).toContain('001. Ήχος · «Αρχή»');
    expect(txt).toContain('±12 μ.');
    expect(txt).toContain('003. Φωτογραφία · «Η πλατεία»');
    expect(txt).toContain('θέση άγνωστη');
  });
  it('sends the consent and items first, info.txt and testimony.json last', () => {
    expect(sendOrder(T, items)).toEqual(['consent.webm', '001.webm', '002.mp4', '003.jpg', 'info.txt', 'testimony.json']);
  });
  it('refuses to send without consent, items or titles', () => {
    expect(sendProblems(T, items)).toEqual([]);
    expect(sendProblems({ ...T, consent: null }, [])).toEqual(['consent', 'items']);
    expect(sendProblems(T, [I(1, 'audio', '001.webm', '  ')])).toEqual(['titles']);
    expect(sendProblems(T, [{ ...I(1, 'audio', '001.webm', 'x'), complete: false }])).toEqual(['recording']);
  });
  it('reads Nextcloud share links', () => {
    expect(parseShare('https://nextcloud.aegean.gr/index.php/s/PZF4XtxEHKcWRN9')).toEqual({ origin: 'https://nextcloud.aegean.gr', token: 'PZF4XtxEHKcWRN9' });
    expect(parseShare('https://cloud.example.org/nc/s/AbC123/')).toEqual({ origin: 'https://cloud.example.org/nc', token: 'AbC123' });
    expect(parseShare('http://cloud.example.org/s/AbC123')).toBeNull();
    expect(parseShare('nonsense')).toBeNull();
  });
});
