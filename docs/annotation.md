# Transcription and vocabulary annotation

Owners transcribe the audio/video of their own stories and attach vocabulary terms.
Approved terms are public and exportable as JSON-LD. Everything runs in the page and in
your Supabase database: no server function and no paid API key.

## Setup (once)
Run `supabase/annotations.sql` in the Supabase SQL editor (after `schema.sql`). It is safe to
run again; it replaces its own policies, so run it again after pulling updates.

## Flow
Log in → open one of your stories → **Transcribe and annotate** → per audio/video:
1. Get a transcript: **Transcribe on this device (free)** runs Whisper in the browser
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
