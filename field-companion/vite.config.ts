import { defineConfig, type Plugin } from 'vite';
import { createHash } from 'node:crypto';
import { readFileSync } from 'node:fs';

// Writes dist/sw.js after the build: it precaches every built file so the installed app works fully offline.
function serviceWorker(): Plugin {
  return {
    name: 'wm-service-worker',
    apply: 'build',
    generateBundle(_opts, bundle) {
      const files = Object.keys(bundle).filter((f) => !f.endsWith('.map'));
      const extra = ['./', 'sites.json', 'manifest.webmanifest', 'icons/icon.svg', 'icons/icon-192.png', 'icons/icon-512.png', 'icons/apple-touch-icon.png'];
      const assets = Array.from(new Set(extra.concat(files.map((f) => f.replace(/^\/?/, '')))));
      const version = createHash('sha256').update(assets.join('|') + Date.now()).digest('hex').slice(0, 12);
      const tpl = readFileSync(new URL('./src/sw-template.js', import.meta.url), 'utf8');
      this.emitFile({ type: 'asset', fileName: 'sw.js', source: tpl.replace('__VERSION__', version).replace('__ASSETS__', JSON.stringify(assets)) });
    },
  };
}

export default defineConfig({
  base: './',
  plugins: [serviceWorker()],
  build: { outDir: '../field', emptyOutDir: true, sourcemap: false, target: 'es2021' },
  test: { include: ['test/**/*.test.ts'], environment: 'node' },
} as any);
