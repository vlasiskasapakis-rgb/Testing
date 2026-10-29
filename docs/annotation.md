# Roles, annotation and playback

## Who can do what
| | Not logged in | Facilitator (with a site) | Annotator | Admin |
|---|---|---|---|---|
| See published stories | yes | yes | yes | yes |
| Testimonies, their stories and fragments, of **their site** | no | yes | no | sees all |
| Capture stories in the AR app | no | yes | no | no |
| Community validation of the site's testimonies | no | yes | no | no |
| See stories once the community has validated their testimony | no | own site | yes (their site, or all sites without one) | yes |
| Transcribe, annotate, mark a story as done | no | no | yes | no |
| Final export of a testimony (RDF + JSON-LD), which publishes its stories; reopen a story | no | no | yes | no |
| Publish walks (Story links page) | no | no | yes | no |
| Who works where, accounts, sites, languages, audit log (`admin/`) | no | no | no | yes |

Accounts are personal and created by an admin (there is no sign-up in the app). Each account belongs to one **pilot site**; a
facilitator sees and uploads only to that site. All of this is enforced by the database rules, not only by hiding buttons, and
every write is kept in the audit log. Nothing is public before the final export of its testimony. There are no validators any
more: after the community has validated a testimony, the annotators annotate its stories and publish them with the final export.

## File names
A fragment is named by its type and number in the story ("Audio 2", "Image 1", numbered per type) in the upload list, the story
view in the app (🎙 / 🎬 / 🖼 dropdowns), the timeline, the transcripts and the annotation website. A photo or a video can have a
caption, shown under it. (Fragments from before testimonies may still have a title, which is then their name.)

## Order of the files
The order of a story's files is the order they appear in the story (and in the app): the first audio is listed and played first.
- **While uploading** each file has ↑ and ↓ buttons in the list; the list order is the saved order. Numbers ("Audio 1, 2…") follow the new order.
- **Afterwards**, on the annotation website, the **Order of recordings** dropdown above the player has ↑ / ↓ for each recording;
  a move is saved at once. Re-run `supabase/roles.sql` once: it lets the story's owner and annotators change only the `position` of a story's media.

## Facilitator workflow (facilitator/ website and AR app)
**Testimony → stories → fragments.** A **testimony** is one interview with one narrator, under one printed consent form. It holds
**stories** (each answers one interview question), and each story holds its **fragments** (the files). The community validates a
whole testimony; the annotators then annotate the content of its stories (their fragments), not the testimony itself.

Before the platform: the narrator signs the printed consent form, which stays at the pilot site. The facilitator records the
interview, keeps the files on the site's collection station, redacts them (mutes names, blurs faces) and cuts them into
fragments. The platform only receives redacted, already cut files; the website has no recording, editing or redaction tools.

The facilitator website is `…/facilitator/` (the AR app's start screen links to it; the older `…/upload/`, `…/review/` and
`…/consent/` addresses now open it). Sections: **Testimonies** and **Community validation**. An account that is not a facilitator
with a site sees a message instead.

**Status flow.** Testimony: `draft` → `community_validation` → `validated`. Its stories follow it (`draft` →
`community_validation` → `ready_for_annotation`); from then on each story goes on alone: `submitted` (annotation done) →
`published` (the final export of its testimony); an annotator can reopen a story (back to `ready_for_annotation`). **Withdrawn**: at any status a facilitator of the site can withdraw one story, or a whole testimony (which withdraws
all its stories). A withdrawn story is hidden everywhere (only admins and the site's facilitators still see it), cannot change any
more, and the action is logged.

### Testimony
**+ New testimony** asks for:
- the **consent code** printed in advance on the form (2 to 40 characters; kept in capitals; must not already be registered);
- what the narrator agrees to (all are needed): to give the story to the project; that it may be cut into pieces (fragments);
  that others (the community and the project team) may comment on it and add details; that it may be shown and shared under the
  chosen licence; that they take part freely and can withdraw at any time;
- the **licence** — CC BY 4.0, CC BY-SA 4.0, CC BY-NC 4.0, CC BY-NC-SA 4.0, CC BY-NC-ND 4.0, Project use only, each explained in
  plain words;
- a **title** (e.g. "Feasts and work at the harbour") — visitors see it with every story of the testimony, in the app and on the
  stories website, so with anonymity it must not contain the narrator's name;
- **Anonymity** (yes / no) and the **narrator**: with anonymity only the initials (e.g. "E.K."), never shown to visitors;
  without, the name as the consent allows, which visitors see with the published stories as credit;
- the **date of the interview** and its **language or dialect** (no place: each story has its own place).

The code, the agreements, the licence and the anonymity cannot be changed later (a testimony created by mistake, e.g. with a
wrong code, can be deleted while it has no stories, or withdrawn). The title, the narrator, the date and the language can be
corrected while the testimony is a draft (a new title reaches its stories at once). The list of testimonies shows code, title,
narrator, interview date, language, licence, number of stories and status, with search (code, title, narrator) and a status
filter. Older testimonies without a title need one before they can go to the community.

### Story
On the testimony's page, **+ New story**: **Title**, **Theme** (the interview question this story answers — its "why"),
**Who** (free text), **Where** (the place's name and a **point on the map**, required), **When** (free text, e.g. "14/7/1965",
"summer 1965", "~1922"). The story takes the testimony's licence and language (and, when the narrator is not anonymous, the
narrator's name), copied by the database. The source is set by the system: website or AR app.

### Fragments of a story
- **File**: several at once, by drag and drop or the file picker: audio WAV, MP3, M4A; images JPG, PNG, TIFF; video MP4 (up to
  50 MB each by default — the storage bucket's limit; `MAX_UPLOAD_MB` in `config.js` changes the page's limit). The type is
  detected from the file. The original is stored as it is; the browser computes its SHA-256 and the database stores the storage
  server's own fingerprint (eTag) and size; a thumbnail (photo, video) or a waveform (audio) is made for display. The recording
  date is read from the file name (`YYYYMMDD…`) or the file.
- **Order**: drag a fragment by its handle (or ↑ / ↓); the position is saved. Each fragment plays inline (audio, photo, video).
- **Caption**: for a photo or a video only.

**Send to community validation** (on the testimony's page) is possible when the testimony has at least one story and every story
has its theme and at least one audio fragment (a checklist shows what is missing). **Back to draft** is possible until the
community validates it.

### AR pathway (AR app, facilitators only)
Only a facilitator with a site sees **+** in the AR app; visitors cannot capture anything. Capture records audio, photo or video on
site, with the location (GPS) and time from the device. The minimal built-in redaction stays (mute part of an audio, blur part of a
photo) before upload. First the **testimony**: choose one of the site's draft testimonies, or **+ New testimony**
(the same fields as on the website). Then the **story** (title, theme, who, where — the place's name and the point: GPS or chosen on
the map — when) and its fragments (a caption for each photo or video; at least one audio fragment). The story joins its testimony
as a draft with source **AR app**; it is never published directly.

### Community validation
**Community validation** lists the site's testimonies with the community, each with its progress ("1 of 3 stories validated by
the community"), and below, in green, the testimonies already validated (they stay in the list). Opening one shows it on a large
screen (**Full screen** for a projector): its title, the narrator, the interview (date, language), how many stories are validated,
and **its stories side by side** as cards (number, title, theme, a picture, how many fragments and comments, and "Not validated
yet" or, in green, "✓ Validated by the community"). Opening a card shows that story full size: its theme, who, where and when,
its fragments with play buttons and captions, and what the community said (**← All stories**, **Next story →**). Nothing is
corrected there — the who, what, where and when stay as they are. With the community, the facilitator:
- **+ Write down what the community said** — dated comments with the facilitator's name, listed under the story (a facilitator
  can delete their own comment until the testimony is validated). They are never public; the annotators see them on the
  annotation website (**What the community said**), and the facilitators on the story's page;
- **✓ The community validates this story** — the story turns green and the screen goes back to all the stories (**Undo** on the
  story takes it back); on the testimony's page such a story shows "With the community ✓";
- **✓ Send the testimony to annotation** — once every story is green: all its stories move on to annotation
  (`ready_for_annotation`). The stories stay on the screen, green, and the testimony stays in the list.
While a testimony is with the community, it and its stories and fragments cannot be changed (on the website or in the AR app, and
no stories are added). To change something, **Back to draft** on the testimony's page, correct it, and send it again (the
stories then need to be validated again).

### Rules kept by the database (roles.sql)
A new testimony needs a unique code, every agreement, a title, a licence, the anonymity, the narrator (initials only with anonymity), the
date of the interview and the language; no story outside a draft testimony of the same site; testimonies and stories are
visible only within their site; only the site's facilitators create or change testimonies, stories and fragments, and only while
the testimony is a draft; with the community, they only add comments (`facilitator_comments`, read by the site's
facilitators and the annotators) and mark each story as validated (`stories.community_validated_at`); the testimony goes to
annotation only when all its stories are, and a story moves on only together with its testimony;
annotators see a story only after that; nothing is public before publication; withdrawn stays withdrawn. Every write is recorded
in `audit_log` (user, time, entity, action, previous value, change); admins read it on the admin page.

### Admin page (`admin/`)
For admins (`profiles.is_admin`). It opens with **Who works on which pilot site**: for each site, its facilitators (with the
number of testimonies and stories each has created) and annotators, and the accounts without a site (a facilitator without a site
cannot upload). Then **Accounts** (role facilitator/annotator, site, admin — the accounts themselves are created in
Supabase: Authentication → Users → Add user), **Pilot sites** (add, rename, delete), **Languages and dialects** (code + label;
e.g. `el-lesvos` "Lesvian Greek") and the **Audit log** (latest 200 writes, with the previous value). Turn off "Allow new users to
sign up" in Supabase (Authentication → Sign In / Providers) so that only admins create accounts.

### Older data
Running `roles.sql` updates older data once: the earlier consent codes become testimonies (renamed, keeping their code, licence
and agreements; their status follows their stories), so the narrator, date and language of those can be filled in on the
testimony's page; a photo's or video's title becomes its caption, and the first who / where / when of a story's fragments become
the story's. Stories from before sites have no site: annotators and the uploader keep seeing them as before. A story an earlier
validator had returned goes back to annotation, and a walk still waiting for a validator becomes "not a walk" again (publish it
from the Story links page); published stories and walks stay published.

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
Under a board, **Publish as a walk in the app** (and optionally write a short description) offers it to visitors as a walk;
**Withdraw the walk** takes it back. Annotators publish walks directly; only published stories are shown in a walk.
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

## Annotation done and final export (annotation website)
There is no validation step after annotation: the annotators publish the stories themselves, a whole testimony at a time.
- **✓ Annotation done** (on a story): asks for confirmation, and says how many term suggestions are still unreviewed (they stay
  hidden). The story becomes *Annotated: waiting for the final export*. **Reopen for annotation** turns it back.
- Under each testimony in the list: "2 of 3 stories done" and **Final export (RDF + JSON)**, which works once every story of the
  testimony is done. After a confirmation it builds one graph for the testimony and all its stories, **publishes** the stories
  (visitors see them in the app and on the stories website) and downloads two files with the same content:
  `testimony-<code>.ttl` (RDF Turtle) and `testimony-<code>.jsonld` (JSON-LD). Once everything is published the button becomes
  **Export again**, which only downloads the files.
- What the files hold: the testimony (date and language of the interview, licence, and the narrator only when not
  anonymous; not the consent code), and for each story its title, theme, who / where (name and point) / when, licence, files (with
  the captions of photos and videos), transcripts, approved terms (where in the recording, or which area of an image), image ↔
  moment links and expert comments, using CIDOC-CRM, the ECHOES heritage ontology (namespace from `WM_CONFIG.HDT_NS`), Dublin Core
  and Web Annotation. Term suggestions that were not approved are left out.
- **Unpublish and reopen** (on a published story) takes it off the app and back to annotation; export the testimony again when it
  is done.
- The database enforces it: only annotators mark stories done, reopen them and publish them (and only stories marked done), and
  every step is recorded in `reviews` (shown as **History** on the story). The old `validate/` address opens the annotation website.
  Re-run `supabase/roles.sql` once.

## Deleting a story (annotation website)
Withdrawal (facilitator website) is the normal way to take a story away. Deleting is for mistakes: a facilitator can delete a
**draft** of their site, and annotators can delete a story that is already in annotation, annotated or published. Open the story
and press **Delete story** (top right). A dialog lists what goes with it — its files, transcripts, terms and image notes, and its view
statistics — and the button only works after ticking **I understand this cannot be undone**. The story disappears for everyone
(app, map, annotation website); its uploaded files are removed from storage. The audit log and the history of annotators'
corrections are kept.

## Story location (app)
In **New story**, the story's location is your GPS position by default, but it can refer to another place: press **Pick on the map**
and tap the place (it shows "Chosen on the map: …"); **My location (GPS)** goes back to your position. The story then appears at the
chosen place in the app (and is opened there, like any story, within 100 m). The **+** button no longer needs a GPS fix, so a story
can be added indoors by choosing its place on the map; finishing without a GPS fix or a chosen place asks for one. Each file keeps its
own location (📍 details) as before.

## Stories website for visitors
`…/stories/` (it opens `index.html?view=1`; the app's start screen links to it: "No phone at hand? See the stories on the website")
lets anyone see the stories without logging in, on a computer or a phone: a map of all **published** stories and a list with a
photo, the testimony's title and number of recordings/photos, with search (titles of stories and testimonies). **Show** offers the published walks: choosing one lists its stops in
order (1, 2, 3…) and draws the route on the map. Clicking a story (map or list) opens the same story view as the app — recordings
with the photos appearing as they are mentioned, subtitles and terms. There is no AR distance lock here. Openings are counted in the
analytics like the app's map/list.
**Connected stories**: a story's view (website and app) lists the stories it is connected to in published walks — "→ Next" /
"← Before", the walk's name and the line's label — and opens them with a tap. On the website, **Show connections between stories**
(in "All stories") draws those lines on the map (hover for the walk and label). Only published walks and published stories are shown.

## Comments and term locations (annotation website)

### Expert comments on transcript lines
Under every transcript line there is **💬 Add comment**: a short text for visitors (background, explanation, a correction…), saved
with your name; **Edit** / **Delete** change it later. Visitors see comments wherever they see the story (AR app and stories website):
- while the recording plays, the terms of the moment appear in a box right under the subtitles ("🏷 Terms: …"; "—" when none)
  and the comment of the line being heard under it ("💬 Expert note: … — name"; "—" between comments — the box keeps the
  height of the longest comment so nothing moves); the
  timeline has a purple **Comments** lane (tap a mark to jump there);
- in the transcript, under its line; and in an **Expert notes** list with the time (▶ 00:05 jumps there).
Comments of draft stories are visible only to annotators until the story is published. Table `transcript_comments` — re-run
`supabase/roles.sql` once.

### Locations of transcript lines
Every term on a transcript line has a **📍 Location** button (next to Approve / Reject). It opens a map:
- when the term is a Wikidata item with coordinates (a village, a church, a country…), its place is **filled in automatically**;
  **Place of the term (Wikidata)** puts it back, **Location of the file** uses the recording's own location;
- otherwise click on the map (or drag the marker) where that part of the story took place, then **Save location**;
  **Remove location** clears it.
Terms you add by hand, and suggested terms, get the Wikidata place automatically when there is one; you can always change it.
The button then shows the coordinates. Locations are saved in `annotations.lat` / `annotations.lon` (re-run `supabase/roles.sql`
once; until then the button does not appear). Changes are counted as term edits in the analytics.

## Help for new annotators (annotation website)
- The start page and the **Help** button in the header show a 6-step "How it works" guide.
- Drafts are listed first. Collapsible boxes show ▸ / ▾. The transcription language picker is labelled "Recording language".
- **✓ Annotation done**, **Reopen**, **Unpublish and reopen** and the final export ask for confirmation; "done" also says how many suggestions are still unreviewed.
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

## Two places to work
- **The app** (`index.html`): visitors listen to published stories; facilitators of a site record, redact and upload (then community validation). No annotation tools.
- **The facilitator website** (`…/facilitator/`): testimonies, their stories and fragments, and community validation.
- **The annotation website** (`annotate/index.html`, same hosting, address `…/annotate/`): annotators log in with their account
  (the same Supabase accounts and the same `config.js`), see all stories, and on a wide screen work with the player, timeline and
  public preview on the left and the transcription / terms / image notes on the right. The final export (which publishes) is there too.
  Accounts without the annotator role see a message instead. The right side has two tabs, **Transcript & terms** and **Images**; click a line's time to play from there, and the current line is highlighted (and followed while playing, unless you untick **Follow playback**). Everything below about annotating happens on this website.

## Setup (once, in this order)
1. SQL editor: run `supabase/schema.sql`, then `supabase/annotations.sql`, then `supabase/roles.sql` (re-run `roles.sql` after
   pulling updates; afterwards, only `roles.sql` is meant to be re-run). `roles.sql` creates the roles, sites, testimonies,
   stories' workflow and the audit log, and makes every existing account a facilitator (without a site, so it can do nothing yet).
2. Make yourself an admin (SQL editor), then use `…/admin/` for everything else (who works where, accounts, sites, languages):
   ```sql
   update public.profiles set is_admin = true
   where user_id = (select id from auth.users where email = 'you@example.com');
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
1. **Testimonies and stories** (top left) lists the stories grouped under their testimony (title · code · narrator, date of the
   interview, how many stories and how many are waiting to be annotated); open a testimony to see its stories in the order
   they were recorded, each with its status, and open one without having to be nearby. Testimonies with stories to annotate come
   first; older stories without a testimony are in their own group. Search finds titles, names, codes and narrators.
2. **Transcribe and annotate**: for each audio/video get a transcript, find or add terms, approve.
3. For each image (shown as a small thumbnail; tap it to open it larger in a popup): tick the terms it shows, optionally mark an area (**Mark area** opens the popup, drag on the image), and use **Link this image to a
   moment of the story**: choose the audio/video, pick a transcript line or set start/end (the small
   player has "Start/End = current time"), then **Add link**. An image can have several links.
   Each term on an audio/video row has a **Time** button: set when in the recording it applies (the
   player on that section has Start/End = current time), or choose **Whole recording**. Transcript-based
   suggestions start with their transcript line's range.
4. **✓ Annotation done** on each story; when all the stories of a testimony are done, **Final export (RDF + JSON)** under the
   testimony downloads the files and publishes its stories.

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

## Testimonies and licences
See "Facilitator workflow" above: the licence is chosen with the narrator when the testimony is created (on the facilitator
website or in the AR app); the database copies it to every story of that testimony (`stories.license`, not editable). The licence
is shown on the story (app and stories website, linked to the licence text in the viewer's language) and on the annotation
website, and is written in the final export. Visitors also see the story's testimony (its title), theme, who, where, when and, when the narrator is not anonymous, the narrator.

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
all notes are listed with their times.

## Term names follow the selected language
Viewers see each term's name in the language they picked (Greek, English, French, Italian), taken from the vocabulary the term came
from: Wikidata labels directly, and Getty AAT/TGN/ULAN terms through the matching Wikidata item. If the vocabulary has no name in that
language, the name stored by the annotator is shown. Annotator screens keep the stored names. Names are looked up
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
Approved terms are public. Everything runs in the page and in
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
   Visitors see the transcript and approved terms.

## Images
In **Transcribe and annotate**, each image of your story appears with the terms you have already
approved from the audio/video. Tick the ones the image shows. Optionally **Mark area** and drag a
box on the image (stored as fractions of its width/height, so it survives resizing).
Visitors see approved terms
and boxes under the image.

The automatic step is a simple name heuristic, not AI: it misses things and suggests wrong
matches, so review it. Re-saving replaces earlier *unreviewed* automatic suggestions;
approved/rejected and hand-added ones are kept. Lines without timestamps are stored without
a time range (the term then applies to the whole file).
