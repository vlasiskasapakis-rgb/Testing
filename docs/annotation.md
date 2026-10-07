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

## File names
When a file has a **title** (📍 details in the upload form), that title is its name everywhere: the upload list, the story view in the
app (🎙 / 🎬 / 🖼 dropdowns), the timeline, the transcripts, and all of the annotation website. Files without a title keep
"Audio 2", "Image 1" (numbered per type).

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
(an upload still works without them, but the details, including each file's location, are then NOT saved; the app tells you when that happens).

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
- Variants of the same name ("Στη Μυτιλήνη", "Μυτιλήνη", "Μυτιλήνης"; leading articles/prepositions are dropped) are looked up
  **once** and the term is placed on every line where any variant is said. Names are checked in order of importance — how often they
  are said, and whether they also appear in the file details — up to **300 names per story**; if a very long story has more, the
  status line says how many less frequent names were not checked. Wikidata answers are remembered while the page is open, so pressing
  **Suggest** again (or another story with the same names) does not search them again.
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

## Story links (connect/ page)
`…/connect/` (button **Story links** in the annotation site's header) is a board where annotators connect stories. Desktop only;
annotators edit, administrators can read.
- **Boards**: make as many as you need (a route, a theme, a family…): **+ New board**, **Rename**, **Delete board** (deleting a board
  never deletes stories).
- **Stories** (left): search, filter (drafts / published / not on this board), then **Add** or drag a story onto the board. Each story
  is a box with its title, narrator, status and number of files; **Details** opens a dropdown with the first photo, narrator, location,
  consent code, every file (title, identity, time) and a link that opens the story in the annotation site.
- **Connect**: drag from the **●** on the right of a box to another box — the arrow means "this story, then that one". Or use
  **Connect to…** at the bottom of a box (keyboard friendly). Click a line to **Label** it ("same village", "continues"…),
  **Reverse** it or **Delete** it; the same actions are in the **Links** list on the left.
- Boxes are **numbered** in order along the lines (1 → 2 → 3 …); the Links list shows the whole order. Branches are numbered top to
  bottom.
- Move boxes by dragging their title bar (or focus a box and use the arrow keys, Shift for bigger steps). Drag the empty board to
  pan, mouse wheel to zoom, **Fit to screen**, **Tidy up** (each chain left to right, unconnected stories in a row below).
- Everything is saved immediately (status at the top right). Removing a box removes its lines; deleting a story removes it from all
  boards. Tables: `story_boards`, `story_board_items` (position of each story), `story_board_links` — re-run `supabase/roles.sql` once.

### Walks in the AR app
Tick **Walk in the AR app** under a board (and optionally write a short description) to offer it to visitors as a walk.
In the app, the start screen asks **How do you want to explore?**:
- **Free roam** — all stories around you, as before;
- **Follow a walk** — pick a walk (with its number of stops and description). Only its stories are shown, numbered in the order of
  the lines (the same order as the numbers on the board; stories without lines are left out, and if a board has no lines at all its
  stories are taken left to right). **Draft stories are skipped.** The map shows the route with numbered stops (✓ = seen, orange =
  next); the card at the bottom says "Stop 2 of 5 · 120 m away" and announces when you arrive. Opening a stop's story marks it as
  seen; progress is kept on the phone. At the end the card says the walk is completed.
The button under the language (🧭 Free roam / 🚶 walk name · 2/5) switches mode at any time, lists the stops with distances and
can **restart the walk**. Without any published walk the app works exactly as before. Openings from the walk card are counted in
the analytics as "Walk (next stop)". Needs `supabase/roles.sql` re-run (columns `is_walk`, `description`; visitors may read walks).

## Heritage objects in ECHOES (links to other ECHOES tools, e.g. OCRA)
If a story is about an object or monument that is documented in ECHOES (for example modelled and annotated in OCRA), annotators can
link it: in the story on the annotation site, open **🏛 Heritage objects (ECHOES)**, paste the object's ECHOES address (e.g.
`http://echoes-eccch.eu/HDT/…`) and an optional name, **Add**. Visitors see the links in the story view (app and stories website),
and the RDF export declares the object as `hdto:HC1_Heritage_Entity` and says the story's narrative refers to it
(`crm:P67_refers_to`), so ECCCH can find the oral stories about that object. No 3D model is needed on our side. Table
`story_heritage` — re-run `supabase/roles.sql` once.

## Validation before publishing (validate/ page)
Annotators no longer publish directly: a **validator** approves every story and every walk first.
- **Stories**: on the annotation site the button is **Submit for validation** (with an optional message). The story becomes
  *Submitted for validation*; **Withdraw from validation** turns it back into a draft. A validator then either **approves and
  publishes** it, or **returns it with comments** — the story becomes *Returned with comments*, the comments are shown in red at the top
  of the story (with the whole validation history), and the annotator fixes it and presses **Submit again for validation**.
  Published stories can still be unpublished by annotators. The story list shows the status and can be filtered by it.
- **Walks**: on the Story links page, **Submit as a walk for validation** replaces the old checkbox; states: *Not a walk*, *Waiting for
  validation* (Withdraw), *Returned by the validator* (with the comment; Submit again), *Published walk in the app* (Withdraw the walk).
  Visitors see a walk only after a validator approves it.
- **Validator page** `…/validate/` (also a **Validation** button in the annotation site's header for validators): stories and walks
  waiting for validation. Each story shows who submitted it and their message, its files (with a preview player), transcript lines,
  approved terms, a warning for term suggestions not yet reviewed, expert comments, consent code and location, and opens in full in the
  annotation site. Each walk shows its stops in order and warns about stops that are not published (visitors won't see them).
  **Approve and publish** or **Return with comments** (a comment is required). Recent decisions are listed at the bottom.
- The database enforces it: only validators can publish or return a story and approve or return a walk (trigger), and every
  submission/decision is recorded in `reviews`. Make someone a validator (they also need the annotator role) in the SQL editor:
  `update public.profiles set role = 'annotator', is_validator = true where user_id = (select id from auth.users where email = '…');`
  Existing published stories and walks stay published. Re-run `supabase/roles.sql` once (as written, without enabling RLS).

## Deleting a story (annotation website)
Annotators can delete **any** story (the person who uploaded it can still delete their own in the app). Open the story and press
**Delete story** (top right). A dialog lists what goes with it — its files, transcripts, terms and image notes, and its view
statistics — and the button only works after ticking **I understand this cannot be undone**. The story disappears for everyone
(app, map, annotation website); its uploaded files are removed from storage. The analytics history of annotators' corrections is kept.
This needs `supabase/roles.sql` to be re-run once (it lets annotators delete stories and their files); until then the site says
the database did not allow the deletion and nothing is removed.

## Story location (app)
In **New story**, the story's location is your GPS position by default, but it can refer to another place: press **Pick on the map**
and tap the place (it shows "Chosen on the map: …"); **My location (GPS)** goes back to your position. The story then appears at the
chosen place in the app (and is opened there, like any story, within 100 m). The **+** button no longer needs a GPS fix, so a story
can be added indoors by choosing its place on the map; finishing without a GPS fix or a chosen place asks for one. Each file keeps its
own location (📍 details) as before.

## Stories website for visitors
`…/stories/` (it opens `index.html?view=1`; the app's start screen links to it: "No phone at hand? See the stories on the website")
lets anyone see the stories without logging in, on a computer or a phone: a map of all **published** stories and a list with a
photo, narrator and number of recordings/photos, with search. **Show** offers the published walks: choosing one lists its stops in
order (1, 2, 3…) and draws the route on the map. Clicking a story (map or list) opens the same story view as the app — recordings
with the photos appearing as they are mentioned, subtitles and terms. There is no AR distance lock here. Openings are counted in the
analytics like the app's map/list.
**Connected stories**: a story's view (website and app) lists the stories it is connected to in published walks — "→ Next" /
"← Before", the walk's name and the line's label — and opens them with a tap. On the website, **Show connections between stories**
(in "All stories") draws those lines on the map (hover for the walk and label). Only published walks and published stories are shown.

## Uploading stories from a computer (facilitator website)
`…/upload/` (it opens `index.html?web=1`; the app's start screen also links to it: "On a computer? Upload stories from the
website") is the same story upload as in the app, for a desktop browser: log in, **+ New story**, the narrator's consent, title,
files (add, edit — blur, crop, mute — and give details), **Finish story**, check and submit. **My stories** lists your stories
(open, play, delete). There is no AR, camera or GPS here, so the **story location is always chosen on the map** — the map has a
**place search** (OpenStreetMap); finishing without a location asks for one. Files' own locations are also chosen on the map.
The place search is also available in the app's map picker.

## Map of all locations (annotation website)
The **Map** button in the header (next to **Stories**) shows every location that users uploaded, **for each file** (photo, audio, video)
and for each story:
- a **marker for each file's own location**: 🖼 photo, 🎙 audio, 🎬 video (colour = the user; the legend lists users). When several files share the same place (for example
  they all kept the GPS default) the dot shows their **number**; click it to list the files and open their stories. A **hollow circle**
  is the place where a story was created;
- **Connect files of the same story** (on by default) draws a line from the story's creation place through its files in their order
  (dashed = draft). Files at the same place add no line;
- **Connect each user's stories in order** (off) draws a dotted line through each user's stories in the order they were created;
- **Connect stories that share terms** (off) draws purple lines between stories with approved terms in common (thicker = more terms;
  **Min. shared terms** filters weak links; terms shared by very many stories are ignored);
- **Show** filters drafts / published.
If no file has its own location (older uploads, or `supabase/roles.sql` not yet re-run) the map says so and shows only the story places.

### Expert comments on transcript lines
Under every transcript line there is **💬 Add comment**: a short text for visitors (background, explanation, a correction…), saved
with your name; **Edit** / **Delete** change it later. Visitors see comments wherever they see the story (AR app and stories website):
- while the recording plays, the terms of the moment appear in a box right under the subtitles ("🏷 Terms: …"; "—" when none)
  and the comment of the line being heard under it ("💬 Expert note: … — name"; "—" between comments — the box keeps the
  height of the longest comment so nothing moves); the
  timeline has a purple **Comments** lane (tap a mark to jump there);
- in the transcript, under its line; and in an **Expert notes** list with the time (▶ 00:05 jumps there).
Comments of draft stories are visible only to annotators until the story is published. The RDF export includes them as W3C Web
Annotations with motivation `oa:commenting` (text body, author, the line's time span). Table `transcript_comments` — re-run
`supabase/roles.sql` once.

### Locations of transcript lines
Every term on a transcript line has a **📍 Location** button (next to Approve / Reject). It opens a map:
- when the term is a Wikidata item with coordinates (a village, a church, a country…), its place is **filled in automatically**;
  **Place of the term (Wikidata)** puts it back, **Location of the file** uses the recording's own location;
- otherwise click on the map (or drag the marker) where that part of the story took place, then **Save location**;
  **Remove location** clears it.
Terms you add by hand, and suggested terms, get the Wikidata place automatically when there is one; you can always change it.
The button then shows the coordinates. Locations are saved in `annotations.lat` / `annotations.lon` (re-run `supabase/roles.sql`
once; until then the button does not appear). Changes are counted as term edits in the analytics, and the RDF export adds them to the
annotation as `dcterms:spatial` → `crm:E53_Place` with a `geo:wktLiteral` point.

### One story at a time, in transcript order
Choose a story in **Story** (or press **Show only this story on the map** in a marker's popup) to see only that story's files at
their own locations, joined **in the order they appear in the transcripts**:
- each recording (audio/video) comes in the story's order, followed by the photos shown or noted on its transcript
  (image links and image notes with a time), in time order; a file counts at its **first** appearance;
- terms on transcript lines that have a location are stops too (red 📍 markers), at the moment they are said;
- markers are **numbered** in that order (several numbers on one marker = same place), and the line joins them 1 → 2 → 3 …;
- a marker's popup gives the file details and every moment it appears (“in *recording* at mm:ss”) with the transcript line spoken then;
- the list under the map shows the full order, marking files with **no location** (left out of the line) and files **not linked to any
  recording** (grey markers, no line). Rejected notes are ignored; suggested and approved ones count.
Choose **All stories** to go back to the overview.

## Help for new annotators (annotation website)
- The start page and the **Help** button in the header show a 6-step "How it works" guide.
- Drafts are listed first. Collapsible boxes show ▸ / ▾. The transcription language picker is labelled "Recording language".
- **Publish** and **Unpublish** ask for confirmation; publishing also says how many suggestions are still unreviewed.
- Leaving a story, logging out or closing the tab with an unsaved transcript asks first.
- Image notes: each step gets a ✓ when done, and **Add note** stays disabled with a "Still needed: …" hint until all three are done.

## Analytics website (`analytics/`, address `…/analytics/`)
For the project owner. Log in with an account that has `is_admin = true` (run once in the SQL editor, Run as: postgres):
```sql
update public.profiles set is_admin = true where user_id = (select id from auth.users where email = 'you@example.com');
```
It shows, for the chosen period (7 / 30 / 90 days / all):
- **Story consumption in the app**: visitors, story openings, different stories per visitor (average and most), recordings played
  and listened to the end, openings from the AR view; openings per day; visitors by number of stories opened; a table per story
  (openings, visitors, plays, to the end, from AR / map / list) and per anonymous visitor (how many stories each person opened).
  Visitors are a random id kept in the browser - no name, e-mail or IP; browsers that send "Do Not Track" are not counted.
- **Annotators' corrections**: transcript words and lines corrected (counted on every save against the previous version or the
  automatic transcription), suggestions approved / rejected and the acceptance rate, terms added / edited / deleted by hand, image
  notes; corrections per day; tables per annotator and per story. Term changes are recorded by a database trigger.
Everything is shown as charts on the page (most opened stories, where stories were opened from, opening → playing → listening to the end, what each annotator did, words corrected per annotator, approved vs rejected suggestions, corrections per story); the detailed tables sit underneath in collapsed "Table …" sections and can be sorted and downloaded as CSV. Requires the analytics part of `supabase/roles.sql` (re-run it once); counting
starts from then on.

## RDF export for ECHOES / ECCCH (annotation website)
- **Export RDF (Turtle)** next to **Export JSON-LD** on each story downloads `story-<id>.ttl`; **Export all published stories as RDF**
  (under the story list) downloads one `.ttl` file with every published story, ready to load into a triple store.
- Same graph as the JSON-LD (checked: both parse to the identical set of triples): HDT ontology (HC1 Heritage Entity, HC2 Digital Twin,
  HC5/HC6/HC7, HP1/HP2/HP4/HP8/HP9/HP10/HP11/HP22), CIDOC-CRM, Narrative ontology, W3C Web Annotation (time and
  `xywh=percent` fragment selectors), SKOS terms from Wikidata/Getty, GeoSPARQL `wktLiteral` points, Dublin Core terms.
- Each file also carries its details: title (`rdfs:label`), identity (`crm:P3_has_note`), date recorded (`dcterms:created`),
  period (`dcterms:temporal`) and location (`dcterms:spatial` → `crm:E53_Place` with a WKT point).
- `hdto:` is the ECHOES HDTO namespace `http://isl.ics.forth.gr/ontology/echoes/`, the one used by the ECHOES knowledge base and
  OCRA; it comes from `HDT_NS` in `config.js`, so it can be changed there if ECHOES ever moves it.

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

## Optional: AI help for term suggestions (same Groq key)
**3 · Suggest terms** can also ask a Groq text model (same `GROQ_API_KEY` as transcription, no new key) what the story mentions.
1. Edge Functions -> Deploy a new function -> Via Editor, name it exactly `suggest-terms`,
   paste `supabase/functions/suggest-terms/index.ts`, deploy (leave Verify JWT on).
2. Optional secret `GROQ_TEXT_MODEL` to choose the model. Without it the function uses `openai/gpt-oss-120b`, and
   `llama-3.3-70b-versatile` if that one is no longer offered.
How it works: the function (annotators only) sends the story's transcript lines and file details (title, identity, time,
location) to the model and gets back what is mentioned — the exact words and line, the base form of the name ("της Μυτιλήνης" →
"Μυτιλήνη"), an English name and a type (person, place, event, object, material, practice, concept). This also finds ordinary
words the rules miss: objects, materials, crafts and customs ("αργαλειός", "σαπούνι", "λάδι"). Mentions whose words are not
really in that line are thrown away. **The AI never gives links**: the page looks every name up in Wikidata (and the English name if
the original finds nothing), skips results that are films, songs, surnames, given names or disambiguation pages, and scores it with
the usual evidence plus "found by the AI". Long stories are sent in parts; if the free quota runs out part-way, what was found is
used. If the function is not deployed, or the quota is used up, Suggest says so and uses the rules only. The transcript text is
sent to Groq (the audio already is, for transcription).

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

`hdto:` is the ECHOES HDTO namespace `http://isl.ics.forth.gr/ontology/echoes/` (as used by the ECHOES knowledge base and OCRA); the export uses `HDT_NS` from `config.js`
(`urn:echoes:hdto:`). Replace it when ECHOES publishes one, and verify the `nont:` namespace.
