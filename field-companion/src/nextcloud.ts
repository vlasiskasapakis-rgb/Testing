// Uploads to the site's Nextcloud folder through its public share link (best: a "File drop (upload only)" share:
// people with the link can add files but never see or download anything). Uses Nextcloud's public WebDAV.
import { parseShare } from './pkg';
import type { SiteConfig } from './types';

export interface Target { base: string; headers: Record<string, string> }
export class NetError extends Error { constructor(msg: string, readonly status = 0) { super(msg); } }

const ASCII = /^[\x20-\x7e]*$/;

/** The two WebDAV addresses of a public share: the current one, and the older one (with the share token as user). */
export function targets(site: SiteConfig, nickname: string): Target[] {
  const s = parseShare(site.share);
  if (!s) throw new NetError('bad share link');
  const common: Record<string, string> = { 'X-Requested-With': 'XMLHttpRequest' };
  if (nickname && ASCII.test(nickname)) common['X-NC-Nickname'] = nickname;
  const pw = site.password || '';
  const newer: Target = { base: s.origin + '/public.php/dav/files/' + s.token, headers: { ...common } };
  if (pw) newer.headers.Authorization = 'Basic ' + btoa('anonymous:' + pw);
  const older: Target = { base: s.origin + '/public.php/webdav', headers: { ...common, Authorization: 'Basic ' + btoa(s.token + ':' + pw) } };
  return [newer, older];
}

async function call(url: string, init: RequestInit, timeoutMs: number): Promise<Response> {
  const ctl = new AbortController();
  const tm = setTimeout(() => ctl.abort(), timeoutMs);
  try { return await fetch(url, { ...init, signal: ctl.signal, credentials: 'omit', cache: 'no-store', redirect: 'error' }); }
  catch (e) { throw new NetError((e as Error).name === 'AbortError' ? 'timeout' : 'network'); }
  finally { clearTimeout(tm); }
}

function enc(path: string): string { return path.split('/').map(encodeURIComponent).join('/'); }

/** Creates the testimony's folder. Returns the folder ('' if the share does not allow folders: files then get the
 *  testimony id as a prefix) and the address that worked. */
export async function prepareFolder(ts: Target[], folder: string): Promise<{ target: Target; dir: string }> {
  let last: NetError = new NetError('network');
  for (const t of ts) {
    let r: Response;
    try { r = await call(t.base + '/' + enc(folder), { method: 'MKCOL', headers: t.headers }, 20000); }
    catch (e) { last = e as NetError; continue; }
    if (r.status === 201 || r.status === 405) return { target: t, dir: folder };      // created, or already there
    if (r.status === 404 || r.status === 401) { last = new NetError('HTTP ' + r.status, r.status); continue; }
    if (r.status === 403 || r.status === 409 || r.status === 400) return { target: t, dir: '' };   // no folders allowed
    last = new NetError('HTTP ' + r.status, r.status);
  }
  throw last;
}

export async function putFile(t: Target, dir: string, prefix: string, name: string, body: Blob): Promise<void> {
  const path = dir ? dir + '/' + name : prefix + '_' + name;
  const timeout = 60000 + Math.round(body.size / 50000) * 1000;        // at least ~50 KB/s
  const r = await call(t.base + '/' + enc(path), { method: 'PUT', headers: { ...t.headers, 'Content-Type': body.type || 'application/octet-stream' }, body }, timeout);
  if (r.status === 201 || r.status === 204 || r.status === 200) return;
  throw new NetError('HTTP ' + r.status, r.status);
}

/** Can this phone reach the share? Any answer from Nextcloud means yes; a network error means offline or blocked
 *  (e.g. the server does not allow this app's address: CORS). Nothing is written. */
export async function checkShare(site: SiteConfig): Promise<'ok' | 'denied' | 'blocked'> {
  const ts = targets(site, '');
  for (const t of ts) {
    try {
      const r = await call(t.base + '/', { method: 'PROPFIND', headers: { ...t.headers, Depth: '0' } }, 15000);
      if (r.status < 400 || r.status === 405) return 'ok';
      if (r.status === 404) continue;
      return r.status === 401 || r.status === 403 ? 'denied' : 'ok';
    } catch { /* next */ }
  }
  return 'blocked';
}
