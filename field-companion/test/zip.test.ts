import { describe, expect, it } from 'vitest';
import { execFileSync } from 'node:child_process';
import { mkdtempSync, writeFileSync, readFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { crc32, makeZip } from '../src/zip';

describe('zip', () => {
  it('computes CRC-32', async () => {
    expect(await crc32(new Blob(['123456789']))).toBe(0xcbf43926);
  });
  it('makes a ZIP that standard tools open', async () => {
    const big = new Uint8Array(5 * 1024 * 1024).map((_, i) => i % 251);
    const z = await makeZip([{ name: 'abc/001.webm', data: new Blob([big]) }, { name: 'abc/info.txt', data: new Blob(['Μαρτυρία: δοκιμή\n']) }]);
    const dir = mkdtempSync(join(tmpdir(), 'wmz-'));
    writeFileSync(join(dir, 't.zip'), new Uint8Array(await z.arrayBuffer()));
    execFileSync('python3', ['-c', 'import zipfile,sys; z=zipfile.ZipFile(sys.argv[1]); assert z.testzip() is None; z.extractall(sys.argv[2])', join(dir, 't.zip'), dir]);
    expect(readFileSync(join(dir, 'abc', 'info.txt'), 'utf8')).toBe('Μαρτυρία: δοκιμή\n');
    expect(readFileSync(join(dir, 'abc', '001.webm')).length).toBe(big.length);
  });
});
