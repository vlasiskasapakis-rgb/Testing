// The location at the moment of a capture (read each time; nothing is tracked in between). The first reading is often a
// rough one from the network; GPS needs a few seconds. So readings are taken for up to `maxMs` and the most accurate is
// kept, stopping early once it is good enough.
export interface Fix { lat: number; lon: number; accuracy: number }

export const GOOD_M = 25;        // stop listening once this accurate
export const ROUGH_M = 500;      // above this the location is only approximate (no GPS / precise location off)

export function locate(maxMs = 10000): Promise<Fix | null> {
  return new Promise((resolve) => {
    if (!('geolocation' in navigator)) { resolve(null); return; }
    let best: Fix | null = null, done = false, id = -1;
    const finish = () => { if (done) return; done = true; if (id >= 0) navigator.geolocation.clearWatch(id); clearTimeout(tm); resolve(best); };
    const tm = setTimeout(finish, maxMs);
    id = navigator.geolocation.watchPosition(
      (p) => {
        const f = { lat: p.coords.latitude, lon: p.coords.longitude, accuracy: p.coords.accuracy };
        if (!best || f.accuracy < best.accuracy) best = f;
        if (best.accuracy <= GOOD_M) finish();
      },
      (e) => { if (e.code === e.PERMISSION_DENIED) finish(); },
      { enableHighAccuracy: true, timeout: maxMs, maximumAge: 0 },
    );
  });
}
