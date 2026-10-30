export type Kind = 'audio' | 'video' | 'photo';

export type Consent =
  | { type: 'spoken'; file: string }
  | { type: 'form'; licence: string; anonymous: boolean };

/** A testimony kept on this device until it has been sent. */
export interface Testimony {
  id: string;            // UUID, also the folder name on Nextcloud
  title: string;
  created: string;       // ISO time
  consent: Consent | null;
  nextOrder: number;     // the next item's number (001, 002, …)
  consentMime?: string;  // the recorded consent's format
  sent: string[];        // file names Nextcloud has confirmed (so a send resumes without duplicates)
  remoteDir?: string;    // where its files go on Nextcloud ('' when the share does not allow folders)
}

/** One recording or photo of a testimony. */
export interface Item {
  id: string;
  tid: string;           // its testimony
  order: number;
  type: Kind;
  file: string;          // 001.webm, 002.jpg, …
  mime: string;
  title: string;         // required before sending
  lat: number | null;
  lon: number | null;
  accuracy: number | null;
  time: string;          // ISO time of the capture
  complete: boolean;     // false while recording (or if the app closed during a recording)
  size?: number;
}

export interface Settings {
  site: string;          // site code
  collector: string;     // the collector's name
}

export interface SiteConfig {
  name?: string;
  share: string;         // Nextcloud public share link (File drop)
  password?: string;
}
