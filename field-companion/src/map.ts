// A map with one pin per item. The pins are drawn by Leaflet itself (no images), so they show offline too, on a blank
// background when the OpenStreetMap tiles cannot load.
import L from 'leaflet';
import 'leaflet/dist/leaflet.css';
import type { Item } from './types';

let current: L.Map | null = null;

export function showMap(box: HTMLElement, items: Item[], onTap: (i: Item) => void): void {
  if (current) { current.remove(); current = null; }
  const pts = items.filter((i) => i.lat != null && i.lon != null);
  box.hidden = !pts.length;
  if (!pts.length) return;
  const m = L.map(box, { zoomControl: true, attributionControl: true });
  current = m;
  L.tileLayer('https://tile.openstreetmap.org/{z}/{x}/{y}.png', { maxZoom: 19, attribution: '© OpenStreetMap', referrerPolicy: 'strict-origin-when-cross-origin' } as L.TileLayerOptions).addTo(m);
  const color: Record<string, string> = { audio: '#186078', video: '#7B1FA2', photo: '#C25E00' };
  const ll: L.LatLngExpression[] = [];
  pts.forEach((i) => {
    const p: L.LatLngExpression = [i.lat as number, i.lon as number];
    ll.push(p);
    L.circleMarker(p, { radius: 13, color: '#fff', weight: 3, fillColor: color[i.type], fillOpacity: 1 })
      .bindTooltip(String(i.order).padStart(3, '0') + ' · ' + (i.title || '…'), { permanent: false })
      .on('click', () => onTap(i)).addTo(m);
  });
  if (ll.length === 1) m.setView(ll[0], 17); else m.fitBounds(L.latLngBounds(ll), { padding: [30, 30], maxZoom: 18 });
  setTimeout(() => m.invalidateSize(), 50);
}
