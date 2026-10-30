// A map with one numbered pin per item. Items captured at (almost) the same spot are fanned out around it, with a small
// dot at the real location, so every one stays visible and tappable. Pins are drawn without images, so they show
// offline too, on a blank background when the OpenStreetMap tiles cannot load.
import L from 'leaflet';
import 'leaflet/dist/leaflet.css';
import type { Item } from './types';

let current: L.Map | null = null;
const COLOR: Record<string, string> = { audio: '#186078', video: '#7B1FA2', photo: '#C25E00' };
const ICON: Record<string, string> = { audio: '🎙', video: '🎬', photo: '📷' };

function esc(s: string): string { return s.replace(/[&<>"]/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;' }[c] as string)); }

export function showMap(box: HTMLElement, items: Item[], onTap: (i: Item) => void): void {
  if (current) { current.remove(); current = null; }
  const pts = items.filter((i) => i.lat != null && i.lon != null);
  box.hidden = !pts.length;
  if (!pts.length) return;
  const m = L.map(box, { zoomControl: true, attributionControl: true });
  current = m;
  L.tileLayer('https://tile.openstreetmap.org/{z}/{x}/{y}.png', { maxZoom: 19, attribution: '© OpenStreetMap', referrerPolicy: 'strict-origin-when-cross-origin' } as L.TileLayerOptions).addTo(m);

  // items within ~3 m of each other share a spot
  const groups = new Map<string, Item[]>();
  pts.forEach((i) => {
    const k = (i.lat as number).toFixed(5) + ',' + (i.lon as number).toFixed(5);
    const g = groups.get(k); if (g) g.push(i); else groups.set(k, [i]);
  });
  const ll: L.LatLngExpression[] = [];
  groups.forEach((g) => {
    const p: L.LatLngExpression = [g[0].lat as number, g[0].lon as number];
    ll.push(p);
    if (g.length > 1) L.circleMarker(p, { radius: 5, color: '#fff', weight: 2, fillColor: '#13262E', fillOpacity: 1, interactive: false }).addTo(m);
    const r = g.length > 1 ? 22 + 3 * g.length : 0;                       // pixels from the spot
    g.forEach((i, n) => {
      const a = (2 * Math.PI * n) / g.length - Math.PI / 2;
      const dx = Math.round(r * Math.cos(a)), dy = Math.round(r * Math.sin(a));
      const label = String(i.order).padStart(3, '0');
      const icon = L.divIcon({
        className: 'pin',
        html: '<span style="background:' + COLOR[i.type] + '">' + ICON[i.type] + ' ' + label + '</span>',
        iconSize: [64, 28], iconAnchor: [32 - dx, 14 - dy],
      });
      L.marker(p, { icon, title: label + ' · ' + (i.title || ''), alt: label + ' ' + (i.title || ''), keyboard: true, riseOnHover: true })
        .bindTooltip(esc(label + ' · ' + (i.title || '…')), { direction: 'top', offset: [dx, dy - 14] })
        .on('click', () => onTap(i)).addTo(m);
    });
  });
  if (ll.length === 1) m.setView(ll[0], 18); else m.fitBounds(L.latLngBounds(ll), { padding: [50, 50], maxZoom: 18 });
  setTimeout(() => m.invalidateSize(), 50);
}
