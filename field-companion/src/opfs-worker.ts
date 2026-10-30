// Writes media to the Origin Private File System. Sync access handles exist only in workers; they work on Chrome and on
// Safari (15.2+), unlike createWritable(). Each chunk is appended and flushed at once, so a closed browser loses nothing
// already written.
/// <reference lib="webworker" />
type Msg = { id: number; op: 'append'; dir: string[]; name: string; data: ArrayBuffer } | { id: number; op: 'probe' };

async function dirOf(path: string[]): Promise<FileSystemDirectoryHandle> {
  let d = await navigator.storage.getDirectory();
  for (const p of path) d = await d.getDirectoryHandle(p, { create: true });
  return d;
}

self.onmessage = async (ev: MessageEvent<Msg>) => {
  const m = ev.data;
  try {
    if (m.op === 'probe') {
      const d = await dirOf(['probe']);
      const fh = await d.getFileHandle('p.bin', { create: true });
      const h = await (fh as any).createSyncAccessHandle();
      h.write(new Uint8Array([1, 2, 3]), { at: 0 }); h.flush(); h.close();
      (self as unknown as Worker).postMessage({ id: m.id, ok: true });
      return;
    }
    const d = await dirOf(m.dir);
    const fh = await d.getFileHandle(m.name, { create: true });
    const h = await (fh as any).createSyncAccessHandle();
    try { h.write(new Uint8Array(m.data), { at: h.getSize() }); h.flush(); }
    finally { h.close(); }
    (self as unknown as Worker).postMessage({ id: m.id, ok: true });
  } catch (e) {
    (self as unknown as Worker).postMessage({ id: m.id, ok: false, error: String((e as Error)?.message || e) });
  }
};
