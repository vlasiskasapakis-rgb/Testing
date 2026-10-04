# Roles, annotation and playback

## Who can do what
| | Not logged in | Facilitator (default) | Annotator |
|---|---|---|---|
| See published stories | yes | yes | yes |
| Collect, redact and upload stories | no | yes (saved as **drafts**) | yes |
| See their own drafts / delete their own stories | no | yes | own only |
| See every story, drafts included | no | no | yes |
| Transcribe, annotate, link images to moments, publish | no | **no** | yes |

Every new account is a facilitator. This is enforced by the database rules, not only by hiding
buttons. A story reaches the public only when an annotator presses **Publish for everyone**.

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
- **Word timings** (Whisper on this device, or the Groq server option) are saved with each line
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

For each image you only **pick terms from the transcript**; you never type times:
- **What is in this image?** lists the terms already approved on the audio/video. Tick the ones the image shows. Each ticked term gets a
  note for every transcript line where it is mentioned, and the image is linked to those lines automatically, so viewers see the image
  and the term exactly while it is spoken. A term with no timed mention yet is shown whenever the image is shown.
- **Mark area** draws one area for the term; it applies to all its mentions. Unticking removes the term's notes from the image.
- If more mentions are approved later, **Update from the transcript (N new)** appears: one tap adds them.
- **When is this image shown?** (collapsed) lists the periods the image is linked to (with the transcript line) and lets you delete one, or
  tick extra transcript lines to show the image during them as well.
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
refused and the shared free quota can run out; the on-device and file options still work.

## Flow
Log in → open one of your stories → **Transcribe and annotate** → per audio/video:
1. Get a transcript: **Transcribe on the server** (if set up), or **Transcribe on this device (free)** runs Whisper in the browser
   (first use downloads ~250 MB, cached afterwards; slow on phones; nothing is uploaded),
   or **Load a .srt / .vtt / .txt file**, or type it. Edit freely. Format: one line per
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
**Suggest matches (on this device)** runs CLIP in the browser (first use downloads ~150 MB) and
pre-suggests up to 3 likely terms per image for you to approve or reject. It is experimental: it
works best for clear objects/places and compares against English labels. Visitors see approved terms
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
