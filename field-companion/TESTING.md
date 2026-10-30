# Manual test checklist

Automated: `npm test` (package files). The end-to-end flow below was also run in Chromium with a fake camera/microphone and a
simulated Nextcloud. Repeat it on a real **Android phone (Chrome)** and **iPhone (Safari, added to the Home Screen)**.

**First launch**
- [ ] An unknown site code is refused; a known one (any letters case) is accepted with a name.
- [ ] Offline at first launch: "An internet connection is needed the first time".
- [ ] Settings → *Check the connection to Nextcloud* says "Nextcloud answers ✓" (if not: CORS, see README).

**Consent before capture**
- [ ] In a new testimony, Audio / Video / Photo are locked ("Consent first").
- [ ] Spoken consent: record, stop → "Spoken consent recorded", it plays back; capture unlocks.
- [ ] Consent form: cannot be saved without the tick and anonymity; then "Consent form · CC BY · anonymous: …".

**Capture**
- [ ] Audio: record, pause (timer stops), resume, stop → a title is required (Save disabled while empty).
- [ ] Video: past 3 minutes a warning appears; recording continues.
- [ ] Photo: the in-page camera, switch camera, take photo → title.
- [ ] Each item shows time and location (± accuracy), or "no location" if denied.
- [ ] **No photo or video appears in the phone's Gallery / Photos.**

**Offline and restarts**
- [ ] Airplane mode: open the app from the home screen, record a whole testimony, close the app, reopen it, play everything.
- [ ] Restart the phone's browser: all items are still there.
- [ ] Close the app during a recording: on reopening, the item is there ("Title needed") and plays up to the moment it stopped.

**Sending**
- [ ] Offline: *Send all* says sending will be possible when connected; coming back online offers "Send now".
- [ ] Turn off data in the middle of a send: "Sending stopped: N files remain"; everything is still on the phone.
- [ ] Send again: only the missing files are sent (no `(2)` copies in Nextcloud); then "Sent" and the testimony is gone
      from the phone.
- [ ] In Nextcloud: one folder per testimony with all media, `info.txt` (Greek, readable) and `testimony.json`
      (matching the items).
- [ ] The facilitator's synced folder receives the same.
