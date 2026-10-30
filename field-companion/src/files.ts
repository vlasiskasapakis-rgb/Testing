// Media files on the device: the Origin Private File System (private to this app, never in the phone's gallery), written
// chunk by chunk through a worker. Without OPFS (e.g. private browsing) the chunks go to IndexedDB instead.
import { db, req, tx } from './store';

interface Backend {
  kind: 'opfs' | 'idb';
  append(tid: string, name: string, data: Blob): Promise<void>;
  read(tid: string, name: string, type: string): Promise<Blob>;
  remove(tid: string, name: string): Promise<void>;
  removeAll(tid: string): Promise<void>;
}

class Opfs implements Backend {
  kind = 'opfs' as const;
  private w: Worker; private n = 0; private wait = new Map<number, (r: { ok: boolean; error?: string }) => void>();
  constructor() {
    this.w = new Worker(new URL('./opfs-worker.ts', import.meta.url), { type: 'module' });
    this.w.onmessage = (e) => { const f = this.wait.get(e.data.id); if (f) { this.wait.delete(e.data.id); f(e.data); } };
  }
  call(msg: Record<string, unknown>, transfer: Transferable[] = []): Promise<void> {
    const id = ++this.n;
    return new Promise((resolve, reject) => {
      this.wait.set(id, (r) => (r.ok ? resolve() : reject(new Error(r.error))));
      this.w.postMessage({ ...msg, id }, transfer);
    });
  }
  probe(): Promise<void> { return this.call({ op: 'probe' }); }
  async append(tid: string, name: string, data: Blob): Promise<void> {
    const buf = await data.arrayBuffer();
    await this.call({ op: 'append', dir: ['t', tid], name, data: buf }, [buf]);
  }
  private async dir(tid: string): Promise<FileSystemDirectoryHandle> {
    const root = await navigator.storage.getDirectory();
    return (await root.getDirectoryHandle('t', { create: true })).getDirectoryHandle(tid, { create: true });
  }
  async read(tid: string, name: string, type: string): Promise<Blob> {
    const f = await (await (await this.dir(tid)).getFileHandle(name)).getFile();
    return new Blob([f], { type: type || f.type });
  }
  async remove(tid: string, name: string): Promise<void> {
    try { await (await this.dir(tid)).removeEntry(name); } catch { /* already gone */ }
  }
  async removeAll(tid: string): Promise<void> {
    try { await (await (await navigator.storage.getDirectory()).getDirectoryHandle('t', { create: true })).removeEntry(tid, { recursive: true }); } catch { /* already gone */ }
  }
}

class Idb implements Backend {
  kind = 'idb' as const;
  private seq = 0;
  async append(tid: string, name: string, data: Blob): Promise<void> {
    const buf = await data.arrayBuffer();          // stored as bytes: Safari keeps Blobs in IndexedDB unreliably
    const k = tid + '/' + name + '/' + String(Date.now()).padStart(15, '0') + '-' + String(++this.seq).padStart(6, '0');
    await tx(['chunks'], 'readwrite', (t) => { t.objectStore('chunks').put({ k, buf }); });
  }
  private range(tid: string, name?: string): IDBKeyRange {
    const p = tid + '/' + (name ? name + '/' : '');
    return IDBKeyRange.bound(p, p + '￿');
  }
  async read(tid: string, name: string, type: string): Promise<Blob> {
    const d = await db();
    const rows = await req(d.transaction('chunks').objectStore('chunks').getAll(this.range(tid, name))) as { buf: ArrayBuffer }[];
    if (!rows.length) throw new Error('missing file ' + name);
    return new Blob(rows.map((r) => r.buf), { type });
  }
  async remove(tid: string, name: string): Promise<void> {
    await tx(['chunks'], 'readwrite', (t) => { t.objectStore('chunks').delete(this.range(tid, name)); });
  }
  async removeAll(tid: string): Promise<void> {
    await tx(['chunks'], 'readwrite', (t) => { t.objectStore('chunks').delete(this.range(tid)); });
  }
}

let backend: Backend | null = null;
const queues = new Map<string, Promise<void>>();

export async function initFiles(): Promise<'opfs' | 'idb'> {
  if (backend) return backend.kind;
  try {
    if (!navigator.storage || !navigator.storage.getDirectory || typeof Worker === 'undefined') throw new Error('no OPFS');
    const o = new Opfs();
    await Promise.race([o.probe(), new Promise((_, rej) => setTimeout(() => rej(new Error('timeout')), 4000))]);
    backend = o;
  } catch { backend = new Idb(); }
  return backend.kind;
}
function b(): Backend { if (!backend) throw new Error('files not ready'); return backend; }

/** Appends in order, one write at a time per file. */
export function appendFile(tid: string, name: string, data: Blob): Promise<void> {
  const key = tid + '/' + name;
  const next = (queues.get(key) || Promise.resolve()).catch(() => undefined).then(() => b().append(tid, name, data));
  queues.set(key, next);
  return next;
}
/** Waits for every pending write of a file. */
export function flushFile(tid: string, name: string): Promise<void> {
  return (queues.get(tid + '/' + name) || Promise.resolve()).catch(() => undefined);
}
export function readFile(tid: string, name: string, type: string): Promise<Blob> { return b().read(tid, name, type); }
export function removeFile(tid: string, name: string): Promise<void> { return b().remove(tid, name); }
export function removeTestimonyFiles(tid: string): Promise<void> { return b().removeAll(tid); }
export function storageKind(): string { return backend ? backend.kind : '?'; }
