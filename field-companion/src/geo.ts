// The location at the moment of a capture (read each time; nothing is tracked in between).
export interface Fix { lat: number; lon: number; accuracy: number }

export function locate(timeoutMs = 15000): Promise<Fix | null> {
  return new Promise((resolve) => {
    if (!('geolocation' in navigator)) { resolve(null); return; }
    navigator.geolocation.getCurrentPosition(
      (p) => resolve({ lat: p.coords.latitude, lon: p.coords.longitude, accuracy: p.coords.accuracy }),
      () => resolve(null),
      { enableHighAccuracy: true, timeout: timeoutMs, maximumAge: 30000 },
    );
  });
}
