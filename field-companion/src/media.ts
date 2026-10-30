// Recording with getUserMedia + MediaRecorder, and photos from an in-page camera (never <input capture>, which may save
// to the gallery). Chrome records WebM; Safari records MP4 (AAC / H.264).
import type { Kind } from './types';

const AUDIO = ['audio/webm;codecs=opus', 'audio/webm', 'audio/mp4', 'audio/ogg;codecs=opus'];
const VIDEO = ['video/webm;codecs=vp9,opus', 'video/webm;codecs=vp8,opus', 'video/webm', 'video/mp4;codecs=avc1,mp4a', 'video/mp4'];

export function pickMime(kind: 'audio' | 'video'): string {
  if (typeof MediaRecorder === 'undefined') return '';
  for (const m of kind === 'audio' ? AUDIO : VIDEO) if (MediaRecorder.isTypeSupported(m)) return m;
  return '';
}

export function canRecord(): boolean {
  return !!(navigator.mediaDevices && 'getUserMedia' in navigator.mediaDevices && typeof MediaRecorder !== 'undefined');
}

export async function openStream(kind: Kind, facing: 'environment' | 'user' = 'environment'): Promise<MediaStream> {
  if (kind === 'audio') return navigator.mediaDevices.getUserMedia({ audio: { echoCancellation: false, noiseSuppression: false }, video: false });
  return navigator.mediaDevices.getUserMedia({
    audio: kind === 'video',
    video: { facingMode: { ideal: facing }, width: { ideal: kind === 'photo' ? 1920 : 1280 }, height: { ideal: kind === 'photo' ? 1080 : 720 } },
  });
}

export function stopStream(s: MediaStream | null): void {
  if (s) s.getTracks().forEach((t) => t.stop());
}

/** A recording whose data is handed over every second (written to the device at once), with pause and resume. */
export class Recording {
  private mr: MediaRecorder;
  private writes: Promise<void> = Promise.resolve();
  private stopped: Promise<void>;
  private started = 0; private pausedAt = 0; private pausedFor = 0;
  readonly mime: string;
  error: unknown = null;

  constructor(stream: MediaStream, mime: string, onData: (b: Blob) => Promise<void>) {
    this.mr = mime ? new MediaRecorder(stream, { mimeType: mime }) : new MediaRecorder(stream);
    this.mime = (this.mr.mimeType || mime || '').split(';')[0] || 'application/octet-stream';
    this.mr.ondataavailable = (e) => {
      if (!e.data || !e.data.size) return;
      this.writes = this.writes.then(() => onData(e.data)).catch((err) => { this.error = err; });
    };
    this.stopped = new Promise((resolve) => { this.mr.onstop = () => resolve(); });
  }
  start(): void { this.started = Date.now(); this.mr.start(1000); }
  pause(): void { if (this.mr.state === 'recording') { this.mr.pause(); this.pausedAt = Date.now(); } }
  resume(): void { if (this.mr.state === 'paused') { this.mr.resume(); this.pausedFor += Date.now() - this.pausedAt; this.pausedAt = 0; } }
  get paused(): boolean { return this.mr.state === 'paused'; }
  /** Seconds recorded, without the pauses. */
  elapsed(): number {
    if (!this.started) return 0;
    const now = this.pausedAt || Date.now();
    return Math.max(0, (now - this.started - this.pausedFor) / 1000);
  }
  async stop(): Promise<void> {
    if (this.mr.state !== 'inactive') this.mr.stop();
    await this.stopped;
    await this.writes;
    if (this.error) throw this.error;
  }
}

/** A photo from the camera preview, as JPEG. */
export function snapshot(video: HTMLVideoElement): Promise<Blob> {
  const c = document.createElement('canvas');
  c.width = video.videoWidth || 1280; c.height = video.videoHeight || 720;
  const g = c.getContext('2d');
  if (!g) return Promise.reject(new Error('no canvas'));
  g.drawImage(video, 0, 0, c.width, c.height);
  return new Promise((resolve, reject) => c.toBlob((b) => (b ? resolve(b) : reject(new Error('no image'))), 'image/jpeg', 0.9));
}

/** Keeps the screen on while recording or sending (a locked screen stops recording on phones). */
let lock: { release(): Promise<void> } | null = null;
export async function keepAwake(on: boolean): Promise<void> {
  try {
    if (on && !lock && (navigator as any).wakeLock) lock = await (navigator as any).wakeLock.request('screen');
    if (!on && lock) { await lock.release(); lock = null; }
  } catch { lock = null; }
}
