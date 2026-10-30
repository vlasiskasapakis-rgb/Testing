// A ZIP file (stored, without compression: media is already compressed) built in the browser, without libraries.
// Large files are read in slices for the checksum, so memory stays low.
const TABLE = (() => {
  const t = new Uint32Array(256);
  for (let n = 0; n < 256; n++) { let c = n; for (let k = 0; k < 8; k++) c = c & 1 ? 0xedb88320 ^ (c >>> 1) : c >>> 1; t[n] = c >>> 0; }
  return t;
})();

export async function crc32(b: Blob): Promise<number> {
  let c = 0xffffffff;
  const STEP = 4 * 1024 * 1024;
  for (let off = 0; off < b.size; off += STEP) {
    const u = new Uint8Array(await b.slice(off, off + STEP).arrayBuffer());
    for (let i = 0; i < u.length; i++) c = TABLE[(c ^ u[i]) & 255] ^ (c >>> 8);
  }
  return (c ^ 0xffffffff) >>> 0;
}

function dosTime(d: Date): [number, number] {
  return [(d.getHours() << 11) | (d.getMinutes() << 5) | Math.floor(d.getSeconds() / 2),
          ((d.getFullYear() - 1980) << 9) | ((d.getMonth() + 1) << 5) | d.getDate()];
}

export async function makeZip(entries: { name: string; data: Blob }[], when = new Date()): Promise<Blob> {
  const enc = new TextEncoder();
  const [tm, dt] = dosTime(when);
  const parts: BlobPart[] = [], central: Uint8Array<ArrayBuffer>[] = [];
  let offset = 0;
  for (const e of entries) {
    const name = new Uint8Array(enc.encode(e.name)), crc = await crc32(e.data), size = e.data.size;
    if (size >= 0xffffffff || offset >= 0xffffffff) throw new Error('too large for ZIP');
    const h = new DataView(new ArrayBuffer(30));
    h.setUint32(0, 0x04034b50, true); h.setUint16(4, 20, true); h.setUint16(6, 0x0800, true);   // UTF-8 names
    h.setUint16(8, 0, true); h.setUint16(10, tm, true); h.setUint16(12, dt, true);
    h.setUint32(14, crc, true); h.setUint32(18, size, true); h.setUint32(22, size, true);
    h.setUint16(26, name.length, true); h.setUint16(28, 0, true);
    parts.push(h.buffer, name, e.data);
    const c = new DataView(new ArrayBuffer(46));
    c.setUint32(0, 0x02014b50, true); c.setUint16(4, 20, true); c.setUint16(6, 20, true); c.setUint16(8, 0x0800, true);
    c.setUint16(10, 0, true); c.setUint16(12, tm, true); c.setUint16(14, dt, true);
    c.setUint32(16, crc, true); c.setUint32(20, size, true); c.setUint32(24, size, true);
    c.setUint16(28, name.length, true); c.setUint32(42, offset, true);
    const row = new Uint8Array(46 + name.length); row.set(new Uint8Array(c.buffer), 0); row.set(name, 46);
    central.push(row);
    offset += 30 + name.length + size;
  }
  const csize = central.reduce((n, r) => n + r.length, 0);
  const end = new DataView(new ArrayBuffer(22));
  end.setUint32(0, 0x06054b50, true); end.setUint16(8, entries.length, true); end.setUint16(10, entries.length, true);
  end.setUint32(12, csize, true); end.setUint32(16, offset, true);
  return new Blob([...parts, ...central, end.buffer], { type: 'application/zip' });
}
