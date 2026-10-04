# Roles, annotation and playback

## Who can do what
| | Not logged in | Facilitator (default) | Annotator |
|---|---|---|---|
| See published stories | yes | yes | yes |
| Collect, redact and upload stories | no | yes (saved as **drafts**) | yes |
| See their own drafts / delete their own stories | no | yes | own only |
| See every story, drafts included | no | no | yes |
| Transcribe, annotate, link images to moments, publish (on the **annotation website**) | no | **no** | yes |

Every new account is a facilitator. This is enforced by the database rules, not only by hiding
buttons. A story reaches the public only when an annotator presses **Publish for everyone**.

## Order of the files
The order of a story's files is the order they appear in the story (and in the app): the first audio is listed and played first.
- **While uploading** each file has ↑ and ↓ buttons in the list; the list order is the saved order. Numbers ("Audio 1, 2…") follow the new order.
- **Afterwards**, on the annotation website, the **Order of recordings** dropdown above the player has ↑ / ↓ for each recording;
  a move is saved at once. Re-run `supabase/roles.sql` once: it lets the story's owner and annotators change only the `position` of a story's media.

## Details for each file (facilitators)
In the upload form each image, audio or video has a 📍 button for its details: **title**, **identity** (who or what it is about),
**date recorded** (starts as the file's date), **period it refers to** (free text, e.g. "summer 1965") and **location**. The location
starts as your GPS position; you can press **Pick on the map** and tap a place instead. Visitors and annotators see these under
each file (the location links to OpenStreetMap). Re-run `supabase/roles.sql` once: it adds the columns to `story_media`
(an upload still works without them, but the details are then not saved).

## One dropdown per recording in the player area
In the story view (the app and the annotation website) each audio or video is its own dropdown ("Audio 2 · Second tape") holding its
details, player, subtitles, timeline and its own **screen** that shows the images and terms active at that moment of *that* recording.
One is open at a time (the first by default); playing a recording, or pressing one of its
timeline bars or ▶ buttons, opens its dropdown.

## One dropdown per recording (annotation website)
In the **Transcript & terms** tab every recording is its own dropdown, labelled with its title and a summary
("Audio 1 · Kitchen story — 12 lines · 3 approved · 5 to review"). Opening it shows its details (title, identity, date, period, location),
its transcript text and the terms on its lines. One recording is open at a time; while a recording plays with **Follow playback** on,
its dropdown opens by itself. The three buttons below work on all recordings, open or not.

## Three buttons in a row (annotation website)
At the top of the right column, always in view: **1 · Transcribe**, **2 · Save transcript**, **3 · Suggest terms** (plus a small
language picker for the transcription). They work on the whole story:
1. **1 · Transcribe** fills the transcript text of every recording that has none yet (Groq server). If every recording already has
   text it asks before replacing it. A recording's text can also be loaded from a .srt / .vtt / .txt file (link in its section) or
   typed. Edit the text freely.
2. **2 · Save transcript** stores the changed texts.
3. **3 · Suggest terms** uses all saved transcripts together with the story's details and suggests the terms once (below). If a
   transcript has unsaved changes it asks you to save first. For a story with only images, buttons 1 and 2 are disabled.

## One combined suggestion for the whole story (annotation website)
**3 · Suggest terms** combines everything known about the story in one pass. The details are used **inside the transcript**, not as a
separate list:
- Names spoken in the transcript are looked up in Wikidata. The **title, identity, period and location** of the file decide which
  match is right and how confident the suggestion is.
- Places **near the file's location** (and terms from its identity or period) are matched to the transcript lines, even partially:
  "των Αγίων Θεοδώρων" is recognised as "Ναός Αγίων Θεοδώρων, Μυτιλήνη" when that church is near the location. The suggestion is
  placed on that line, at the seconds where the words are said. Nearby places that nobody mentions are **not** suggested for recordings.
- Images (which have no transcript) get the terms spoken while they are shown (through their time links), terms from their own
  identity, title or period, and up to three places within 300 m of their own location.

Each suggestion carries a **confidence** (high / medium / low) and a visible **Why:** line, for example
"High confidence: mentioned at 00:00 · 90 m from the file's location". Text and details that agree rank highest.
Among several Wikidata matches for a name, the one nearest the location (or whose description fits the details) is chosen.
Unreviewed automatic suggestions are replaced on each run; approved, rejected and hand-made terms are kept.
Re-run `supabase/roles.sql` once (it adds `annotations.reason`; suggestions work without it, but the "Why" text is then not saved).

## Two places to work
- **The app** (`index.html`): visitors listen to published stories; facilitators record, redact and upload (drafts). No annotation tools.
- **The annotation website** (`annotate/index.html`, same hosting, address `…/annotate/`): annotators log in with their account
  (the same Supabase accounts and the same `config.js`), see all stories, and on a wide screen work with the player, timeline and
  public preview on the left and the transcription / terms / image notes on the right. Publishing and the JSON-LD export are there too.
  Accounts without the annotator role see a message instead. The right side has two tabs, **Transcript & terms** and **Images**; click a line's time to play from there, and the current line is highlighted (and followed while playing, unless you untick **Follow playback**). Everything below about annotating happens on this website.

## Setup (once, in this order)
1. SQL editor: run `supabase/schema.sql`, then `supabase/annotations.sql`, then `supabase/roles.sql` (re-run `roles.sql` after pulling updates: it also creates the consent tables)
   (afterwards, only `roles.sql` is meant to be re-run). `roles.sql` creates the roles, makes existing stories published, and
   makes every existing account a facilitator.
2. Make someone an annotator (they sign up first, then you run this in the SQL editor):
   ```sql
   update public.profiles set role = 'annotator'
   where user_id = (select id from auth.users where email = 'person@example.com');
   ```
3. Optional fast transcription: see the Groq section below. Re-deploy `transcribe-media` after
   updating it, because it now checks that the caller is an annotator.

Note: uploaded files live in a public storage bucket under unguessable paths. Drafts are hidden from
every list and query, but anyone who is given a draft file's exact URL could open it.

## Troubleshooting: "new row violates row-level security policy"
That means the signed-in account is not an annotator in the database. Check in the SQL editor:
```sql
select u.email, p.role from auth.users u left join public.profiles p on p.user_id = u.id order by u.email;
```
- The account you annotate with must show `annotator`. Promote it with the `update public.profiles ...` statement above.
- The top-left button shows who the app thinks you are, e.g. `Log out · Nikos (annotator)`. If it says `(facilitator)`, log out and in again, or
  hard-refresh to drop an old cached copy of the page.
- If the roles look right, re-run `roles.sql` (it recreates every policy). `schema.sql` and `annotations.sql` now refuse to run once roles are
  installed, because re-running them would weaken the security rules; `roles.sql` is the only file to re-run for updates.

## Annotator workflow
1. **Stories** (top left) lists every story with its status; open one without having to be nearby.
2. **Transcribe and annotate**: for each audio/video get a transcript, find or add terms, approve.
3. For each image (shown as a small thumbnail; tap it to open it larger in a popup): tick the terms it shows, optionally mark an area (**Mark area** opens the popup, drag on the image), and use **Link this image to a
   moment of the story**: choose the audio/video, pick a transcript line or set start/end (the small
   player has "Start/End = current time"), then **Add link**. An image can have several links.
   Each term on an audio/video row has a **Time** button: set when in the recording it applies (the
   player on that section has Start/End = current time), or choose **Whole recording**. Transcript-based
   suggestions start with their transcript line's range.
4. **Publish for everyone**.

## Exact seconds for suggestions
A term points at the seconds where its word is spoken, not at its whole transcript line:
- **Word timings** (from the Groq server option) are saved with each line
  (`transcript_segments.words`; run `roles.sql` once to add the column). Terms found in such a line get the exact
  range of the word, with a little padding.
- **No word timings** (typed text, `.srt`/`.vtt`, or a line you edited): the range is *estimated* from where the word sits
  in the line, with a minimum width of about 1 second. Check these; use **Time → Find exact seconds**, or set
  start/end with the player.
- **Set exact times for all suggestions** refines older suggestions that still cover the whole line. Anything
  you already adjusted is left alone.
- Editing a line's text in the box drops its word timings (they no longer match); re-run the transcription to get them back.

## Consent before every upload
Pressing **+** first opens a consent screen for the participant (the facilitator can switch its language). All four statements must be
ticked; the app then creates a record and shows a code like `WM-7K3Q-9D2F`, derived from the record's id, with a **Copy code**
button. Write the same code on the paper form the participant signs. The code stays visible on the upload screen, is stored with
the story, and is shown (with a copy button) to the story's owner and to annotators; the Stories list can be searched by it.
- A participant who tells several stories on one form can reuse the code: choose it under "Use a code you already created".
- The database refuses a new story that has no consent record belonging to the uploader.
- To find the story behind a form (SQL editor): `select c.code, s.title, s.status from consents c left join stories s on s.consent_id = c.id where c.code = 'WM-XXXX-XXXX';`
- The consent wording (4 statements, `consentC1`-`consentC4` in `index.html`) is a plain-language draft: have your ethics/legal
  reviewers approve or replace it, and bump `CONSENT_VERSION` when it changes. No participant name is stored digitally; identity lives
  on the paper form. Withdrawal today = the facilitator who uploaded the story deletes it.

## Annotating (simplified)
For each audio/video the sheet has two steps: **1 · Transcript** (get or edit the text; options such as language and speed are tucked
under "Options") and **2 · Terms** (find terms automatically, approve or reject). Extra details of a term (type, exact times) are under
**More** and are rarely needed.

Image notes are three steps; you never type times:
1. **Choose a term** (from the terms already approved on the audio/video).
2. **Mark an area** on the image (opens the popup; drag on the image).
3. **Choose a part of the transcription**: tick one or more lines (lines where the term is spoken are pre-ticked). The note's start/end come
   from those lines and the image is linked to them automatically.
Press **Add note**. The **Notes on this image** table (Term · Area · Time · Transcript line) groups the notes of the same term. **View** shows the area on the image, the time button plays that moment, **✕** deletes one note and **Delete all** removes every note of a term (after a confirmation).
Behind the scenes a timed note uses `annotations.av_media_id` + `start_s`/`end_s` (re-run `roles.sql` once). Viewers see only the notes
that apply to the current second next to the image; the timeline has a dark "Image notes" lane (tap to jump and pause); outside playback
all notes are listed with their times. The JSON-LD export gives each timed image note an `oa:hasScope` with the audio/video and time fragment.

## Term names follow the selected language
Viewers see each term's name in the language they picked (Greek, English, French, Italian), taken from the vocabulary the term came
from: Wikidata labels directly, and Getty AAT/TGN/ULAN terms through the matching Wikidata item. If the vocabulary has no name in that
language, the name stored by the annotator is shown. Annotator screens and the JSON-LD export keep the stored names. Names are looked up
once per language per visit and apply to the term list, the timeline bars and the "terms at this moment" box.

## Subtitles
If a story has a timed transcript, it is shown as subtitles while the recording plays: video uses the browser's own subtitle track
(works in full screen), audio shows a caption bar under the player. Long transcript lines are split into short subtitles (using word
timings when they exist). Viewers can switch subtitles off; the choice is remembered. Transcripts without timestamps are not shown as
subtitles (they still appear in the transcript list).

## What the public sees
- Every audio/video has a **timeline** under its player: amber bars are the parts linked to images, blue bars are the parts
  where a term applies (hover a bar for its name; the term list below also has ▶ time buttons). Tapping a bar **jumps there and pauses**, so you can look at the image or terms in your own time (the box under the player shows them); tapping an empty part of the bar moves the playhead without changing play/pause. The ▶ buttons (images list, term times, transcript lines) still play from that moment. The term list and the images are collapsible sections (closed by default, except the images of a story that has no audio/video). Terms with no time range apply to the
  whole recording and have no bar.
- Image-only story: the image with its approved terms and marked areas.
- Story with audio/video: while it plays, the image linked to the current moment appears under the
  player (with its areas), together with the terms that apply to that moment. **Images tied to the story** lists each linked image with
  **▶ from mm:ss**: tapping it jumps the playback there. Transcript lines are tappable too.

# Transcription and vocabulary annotation

Owners transcribe the audio/video of their own stories and attach vocabulary terms.
Approved terms are public and exportable as JSON-LD. Everything runs in the page and in
your Supabase database: no server function and no paid API key.

## Setup (once)
Run `supabase/annotations.sql` in the Supabase SQL editor (after `schema.sql`). It is safe to
run again; it replaces its own policies, so run it again after pulling updates.

## Optional: free fast transcription on the server (Groq)
1. Create a free key at console.groq.com.
2. Supabase dashboard -> Edge Functions -> Secrets: add `GROQ_API_KEY`.
3. Edge Functions -> Deploy a new function -> Via Editor, name it exactly `transcribe-media`,
   paste `supabase/functions/transcribe-media/index.ts`, deploy (leave Verify JWT on).
The button **Transcribe on the server (free, fast)** then works. Files over 25 MB are
refused and the shared free quota can run out; the file option (.srt / .vtt / .txt) still works.

## Flow
Log in → open one of your stories → **Transcribe and annotate** → per audio/video:
1. Get a transcript: **Transcribe on the server** (if set up), or **Load a .srt / .vtt / .txt file**, or type it. Edit freely. Format: one line per
   segment, optionally `[mm:ss-mm:ss] text`.
2. **Save transcript**, or **Save and find terms automatically**: capitalised words/names
   in each line are searched on Wikidata (the kind is guessed: person, place, event, concept).
3. For anything missing, use **+ Add a term** under a line: it searches Wikidata and Getty
   AAT/TGN/ULAN (Getty may be blocked by the browser; Wikidata still works). Pick the type
   and add it.
4. **Approve / Reject** automatic suggestions; fix the type if it was guessed wrong.
   Visitors see the transcript and approved terms; anyone can **Export JSON-LD**.

## Images
In **Transcribe and annotate**, each image of your story appears with the terms you have already
approved from the audio/video. Tick the ones the image shows. Optionally **Mark area** and drag a
box on the image (stored as fractions of its width/height, so it survives resizing).
Visitors see approved terms
and boxes under the image; the JSON-LD export adds `HP9` / `P67 refers to` on the image and a
`xywh=percent:` fragment for boxes.

The automatic step is a simple name heuristic, not AI: it misses things and suggests wrong
matches, so review it. Re-saving replaces earlier *unreviewed* automatic suggestions;
approved/rejected and hand-added ones are kept. Lines without timestamps are stored without
a time range, and the export then links the whole media file instead of a time fragment.

## Mapping to the Heritage Digital Twin Ontology (ECHOES HDTO v0.1)
| App | HDTO / CRM |
|---|---|
| Story point | `HC1 Heritage Entity` → `HP1` → `HC2 Heritage Digital Twin` |
| Photo / video | `HC7 Digital Visual Object`, `HP22 represents` the entity |
| Audio | `HC5 Digital Representation`, `HP22 represents` |
| Spoken story | `nont:Narration` `HP4 narrates` a `nont:Narrative` (`HP2 has story`) |
| Transcript | `HC6 Digital Document` + `crm:E31`, `HP8` / `HP11` |
| Mentioned event | `HP10 tells about` → `crm:E5 Event` (HP10's range is events only) |
| Mentioned person / place / thing / type | `crm:P67 refers to` → `E21` / `E53` / `E70` / `E55` |
| Time-anchored tag | `oa:Annotation` with a media-fragment selector (`t=start,end`) |

`hdt:` has no official namespace in v0.1; the export uses `HDT_NS` from `config.js`
(`urn:echoes:hdto:`). Replace it when ECHOES publishes one, and verify the `nont:` namespace.
