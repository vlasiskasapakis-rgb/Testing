# Walking Memory Field Companion

An installable web app (PWA) for facilitators and collectors in the field. It records a narrator's testimony on the phone (audio,
video, photos, each with its location and time) after the narrator's consent, and sends the **raw** material to the pilot
site's folder on **Nextcloud**. It never publishes anything: the facilitator redacts the material offline and uploads it to
the platform later.

- Works fully offline once installed; nothing goes to the phone's gallery or to other apps; no accounts, analytics or trackers.
- Every second of a recording is written to the app's private storage at once, so a closed browser loses nothing.
- After **all** files of a testimony are confirmed by Nextcloud, the testimony is deleted from the phone.
- Greek and English, large buttons.

The built app is in [`../field/`](../field/) and is published with the rest of the site on GitHub Pages:
**https://vlasiskasapakis-rgb.github.io/Testing/field/**

## How it is used

1. **First launch**: the site code (checked against `sites.json`) and the collector's name. Both stay on the phone.
2. **Home**: the testimonies on this phone (title, date, number of items, *not sent / partly sent*) and a big **+**.
3. **New testimony**: a title, then the **consent** (required): either *record spoken consent* (a short audio clip), or
   *consent form signed* (tick + licence, default CC BY, + anonymous yes/no). Audio / Video / Photo stay locked until then.
4. **Capture**: Audio (with pause/resume), Video (a warning, not a block, after 3 minutes), Photo (in-page camera). After each
   capture a short title is required. Location (lat, lon, accuracy), time and order are saved automatically.
5. **Testimony view**: the items in order with playback, a map with one pin per item (tap opens it; pins show offline without
   tiles), rename or delete before sending, and **Send all**.

## What is sent

To the site's Nextcloud share, in a folder named after the testimony id (`<id>/`):

| File | |
|---|---|
| `consent.webm` / `consent.m4a` | the spoken consent, if recorded |
| `001.webm`, `002.jpg`, `003.mp4`, … | the items, in the browser's own format (Chrome: WebM; iPhone: MP4/M4A; photos: JPEG) |
| `info.txt` | the same information as `testimony.json`, in plain Greek |
| `testimony.json` | sent **last**: its arrival means the testimony is complete |

```json
{ "id": "…", "title": "…", "site": "DEMO", "collector": "…", "created": "2026-10-30T08:00:00.000Z",
  "consent": { "type": "spoken", "file": "consent.webm" },
  "items": [ { "order": 1, "type": "audio", "file": "001.webm", "title": "…", "lat": 39.1, "lon": 26.55, "accuracy": 12, "time": "…" } ] }
```
(`"consent": { "type": "form", "licence": "CC BY", "anonymous": false }` for a signed form.)

Sending goes file by file. Each file Nextcloud confirms is remembered on the phone, so an interrupted send (no signal, locked
phone) continues with the missing files only. When the phone comes back online the app offers to send what is waiting. If the
share does not allow folders, the files are sent as `<id>_001.webm` etc.

### When the app cannot send directly: upload by hand

Until the Nextcloud server allows uploads from the app (see CORS below), use **"Cannot send? Upload by hand"** under
*Send all* on the testimony's screen:
1. **Save as file**: the whole testimony as one `.zip` (a folder named after the testimony id with the media, `info.txt` and
   `testimony.json`), saved to the phone's Files / Downloads (not the gallery).
2. **Open the Nextcloud page** (the share link) and upload that `.zip` there.
3. **Uploaded – delete from device**: the testimony leaves the phone. Delete the `.zip` from Downloads too.

The facilitator unzips it on the computer. A failed direct send now also says why (no answer / CORS, refused, link not
found, size).

## Configuration: site codes and Nextcloud links (`public/sites.json`)

```json
{ "sites": { "DEMO": { "name": "Demo site", "share": "https://nextcloud.aegean.gr/index.php/s/PZF4XtxEHKcWRN9", "password": "" } } }
```

For each pilot site, in Nextcloud: create a folder → **Share** → **Share link** → set it to **File drop (upload only)**
(people with the link can add files but cannot see or download anything) → copy the link into `sites.json` under a new code.
Add the share's password if it has one (note that `sites.json` is public, like the app itself: anyone who has it can drop files
into the folder, but cannot read them). The facilitator syncs that folder with the Nextcloud desktop client.

After changing `sites.json`, rebuild (`npm run build`) and commit `field/`. Phones read the new list the next time they open the
app online.

## Nextcloud must allow uploads from the app (CORS)

The app (on `vlasiskasapakis-rgb.github.io`) uploads to another domain (`nextcloud.aegean.gr`). Browsers only allow this if
Nextcloud says so. **Settings → Check the connection to Nextcloud** in the app shows whether it works ("Nextcloud answers ✓").
If it says there is no connection while the phone is online, ask the Nextcloud administrator to add one of these:

*Apache* (in the Nextcloud virtual host):
```apache
<If "%{REQUEST_URI} =~ m#^/public\.php/(dav|webdav)#">
  Header always set Access-Control-Allow-Origin "https://vlasiskasapakis-rgb.github.io"
  Header always set Access-Control-Allow-Methods "PUT, MKCOL, PROPFIND, OPTIONS"
  Header always set Access-Control-Allow-Headers "Authorization, Content-Type, Depth, X-Requested-With, X-NC-Nickname"
  Header always set Access-Control-Max-Age "86400"
</If>
RewriteEngine On
RewriteCond %{REQUEST_METHOD} OPTIONS
RewriteCond %{REQUEST_URI} ^/public\.php/(dav|webdav)
RewriteRule ^ - [R=204,L]
```
*nginx* (inside the Nextcloud `server` block, before the PHP location):
```nginx
location ~ ^/public\.php/(dav|webdav) {
    add_header Access-Control-Allow-Origin "https://vlasiskasapakis-rgb.github.io" always;
    add_header Access-Control-Allow-Methods "PUT, MKCOL, PROPFIND, OPTIONS" always;
    add_header Access-Control-Allow-Headers "Authorization, Content-Type, Depth, X-Requested-With, X-NC-Nickname" always;
    add_header Access-Control-Max-Age 86400 always;
    if ($request_method = OPTIONS) { return 204; }
    rewrite ^ /public.php$request_uri;   # then handled by the usual Nextcloud PHP location
}
```
Alternative without CORS: serve the built `field/` folder from the Nextcloud domain itself (e.g. `https://nextcloud.aegean.gr/field/`).

The app uses Nextcloud's public WebDAV (`/public.php/dav/files/<token>/`, and the older `/public.php/webdav` as a fallback).

## Install on a phone

The app must be opened over **https://** (GitHub Pages is).

- **Android (Chrome)**: open the address → menu ⋮ → **Install app** (or *Add to Home screen*). Open it from the icon.
- **iPhone (Safari)**: open the address in **Safari** → Share ⬆ → **Add to Home Screen**. **This step is required on iPhone**:
  otherwise Safari may erase the app's stored recordings after about 7 days without use.

Allow microphone, camera and location when asked (the installed app on iPhone may ask again in each session).

## iPhone (Safari) notes

- **Storage**: Safari only keeps storage reliably for apps added to the Home Screen; `storage.persist()` is often refused in the
  browser. The app shows a warning when storage is not persistent. Send testimonies soon after recording.
- **Formats**: Safari records MP4 (AAC / H.264), so files are `.m4a` / `.mp4` (and the consent `consent.m4a`) rather than WebM.
- **Screen lock / switching apps** stops a recording. The app keeps the screen awake while recording (iOS 16.4+); what was
  recorded until then is kept and appears with "Title needed".
- **No background sending**: sending happens while the app is open. If the phone locks, sending stops and continues later from
  where it stopped.
- **Private browsing** has no app storage (OPFS): the app then keeps recordings in IndexedDB, with less space.

## Develop

```sh
cd field-companion
npm install
npm run dev        # http://localhost:5173 (camera and microphone work on localhost)
npm test           # unit tests (package files, share links)
npm run build      # type-check + build into ../field (commit it to publish on GitHub Pages)
```

Code: `src/ui.ts` (screens), `src/media.ts` (MediaRecorder, camera), `src/files.ts` + `src/opfs-worker.ts` (Origin Private
File System, written chunk by chunk from a worker; IndexedDB fallback), `src/store.ts` (IndexedDB metadata), `src/pkg.ts`
(`testimony.json`, `info.txt`), `src/send.ts` + `src/nextcloud.ts` (upload), `src/map.ts` (Leaflet), `src/i18n.ts` (Greek/English),
`src/sw-template.js` (offline service worker, generated into `field/sw.js`).

## Privacy

Recordings stay in the app's private storage (never the gallery, never shared with other apps) until they are sent, and are
deleted from the phone once Nextcloud has confirmed every file. The site code and the collector's name are stored on the phone
only. The app loads no third-party scripts and has no analytics; the map loads OpenStreetMap tiles when online.

See [TESTING.md](TESTING.md) for the manual test checklist.
