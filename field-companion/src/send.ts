// Sending a testimony: file by file to Nextcloud, testimony.json last. Every confirmed file is remembered, so an
// interrupted send continues where it stopped without sending anything twice. Only when every file is confirmed are the
// testimony's files and details deleted from the phone.
import { readFile, removeTestimonyFiles } from './files';
import { prepareFolder, putFile, targets, NetError } from './nextcloud';
import { buildPackage, infoTxt, sendOrder, sendProblems, testimonyJson } from './pkg';
import { deleteTestimonyMeta, getTestimony, listItems, putTestimony } from './store';
import type { Settings, SiteConfig } from './types';

export interface SendResult { ok: boolean; sent: number; total: number; error?: string }

export async function sendTestimony(id: string, settings: Settings, site: SiteConfig,
                                    progress: (done: number, total: number) => void): Promise<SendResult> {
  const t = await getTestimony(id);
  if (!t) return { ok: true, sent: 0, total: 0 };
  const items = await listItems(id);
  const problems = sendProblems(t, items);
  const order = sendOrder(t, items);
  if (problems.length) return { ok: false, sent: t.sent.length, total: order.length, error: 'problems:' + problems.join(',') };
  if (location.protocol !== 'https:' && !/^(localhost|127\.0\.0\.1)$/.test(location.hostname)) {
    return { ok: false, sent: t.sent.length, total: order.length, error: 'https' };
  }
  const pkg = buildPackage(t, items, settings.site, settings.collector);
  const generated: Record<string, Blob> = {
    'info.txt': new Blob([infoTxt(pkg)], { type: 'text/plain;charset=utf-8' }),
    'testimony.json': new Blob([testimonyJson(pkg)], { type: 'application/json' }),
  };
  const mimes: Record<string, string> = {};
  items.forEach((i) => { mimes[i.file] = i.mime; });
  if (t.consent && t.consent.type === 'spoken') mimes[t.consent.file] = t.consentMime || 'audio/webm';

  try {
    const ts = targets(site, settings.collector);
    const prep = await prepareFolder(ts, t.id);
    if (t.remoteDir === undefined) { t.remoteDir = prep.dir; await putTestimony(t); }
    const dir = t.remoteDir ?? prep.dir;
    let done = order.filter((f) => t.sent.includes(f)).length;
    progress(done, order.length);
    for (const name of order) {
      if (t.sent.includes(name)) continue;
      const body = generated[name] || (await readFile(t.id, name, mimes[name] || 'application/octet-stream'));
      await putFile(prep.target, dir, t.id, name, body);
      t.sent.push(name);
      await putTestimony(t);                // remembered at once: a later send skips it
      progress(++done, order.length);
    }
  } catch (e) {
    const fresh = await getTestimony(id);
    return { ok: false, sent: fresh ? fresh.sent.length : 0, total: order.length, error: e instanceof NetError ? e.message : String(e) };
  }
  // everything is on Nextcloud: nothing of it stays on the phone
  await removeTestimonyFiles(id);
  await deleteTestimonyMeta(id);
  return { ok: true, sent: order.length, total: order.length };
}

/** The whole testimony as one ZIP file (a folder named after the testimony id with the same files as a direct send),
 *  for uploading by hand on the Nextcloud share page when the app cannot send directly. */
export async function packageZip(id: string, settings: Settings): Promise<{ blob: Blob; name: string }> {
  const { makeZip } = await import('./zip');
  const t = await getTestimony(id);
  if (!t) throw new Error('missing');
  const items = await listItems(id);
  const problems = sendProblems(t, items);
  if (problems.length) throw new Error('problems:' + problems.join(','));
  const pkg = buildPackage(t, items, settings.site, settings.collector);
  const mimes: Record<string, string> = {};
  items.forEach((i) => { mimes[i.file] = i.mime; });
  if (t.consent && t.consent.type === 'spoken') mimes[t.consent.file] = t.consentMime || 'audio/webm';
  const entries: { name: string; data: Blob }[] = [];
  for (const name of sendOrder(t, items)) {
    const data = name === 'info.txt' ? new Blob([infoTxt(pkg)], { type: 'text/plain' })
      : name === 'testimony.json' ? new Blob([testimonyJson(pkg)], { type: 'application/json' })
      : await readFile(id, name, mimes[name] || 'application/octet-stream');
    entries.push({ name: t.id + '/' + name, data });
  }
  const day = t.created.slice(0, 10);
  return { blob: await makeZip(entries), name: 'WM_' + settings.site + '_' + day + '_' + t.id.slice(0, 8) + '.zip' };
}

/** After an upload by hand: the testimony leaves the phone. */
export async function forgetTestimony(id: string): Promise<void> {
  await removeTestimonyFiles(id);
  await deleteTestimonyMeta(id);
}
