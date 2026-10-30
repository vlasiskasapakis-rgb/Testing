/* Walking Memory Field Companion: service worker (generated at build time from src/sw-template.js).
   The app shell is cached on install so the app works fully offline. Uploads to Nextcloud and map tiles
   are never cached. sites.json is fetched fresh when online (the cached copy is used offline). */
const CACHE = 'wm-field-__VERSION__';
const ASSETS = __ASSETS__;

self.addEventListener('install', (ev) => {
  ev.waitUntil(caches.open(CACHE).then((c) => c.addAll(ASSETS)).then(() => self.skipWaiting()));
});
self.addEventListener('activate', (ev) => {
  ev.waitUntil(caches.keys()
    .then((keys) => Promise.all(keys.filter((k) => k.startsWith('wm-field-') && k !== CACHE).map((k) => caches.delete(k))))
    .then(() => self.clients.claim()));
});
self.addEventListener('fetch', (ev) => {
  const req = ev.request;
  if (req.method !== 'GET') return;
  const url = new URL(req.url);
  if (url.origin !== self.location.origin || url.pathname.endsWith('/sites.json') && navigator.onLine) return;   // other sites (Nextcloud, map tiles): network only
  if (req.mode === 'navigate') {
    ev.respondWith(caches.match('./', { ignoreSearch: true }).then((r) => r || fetch(req)));
    return;
  }
  ev.respondWith(caches.match(req, { ignoreSearch: true }).then((r) => r || fetch(req)));
});
