# Transcription and vocabulary annotation

Owners can transcribe the audio/video of their own stories and review AI-suggested
vocabulary terms. Approved terms are public and exportable as JSON-LD.

## Setup (once)
1. Run `supabase/annotations.sql` in the Supabase SQL editor (after `schema.sql`).
2. Install the Supabase CLI, then from the repo root:
   ```
   supabase login
   supabase link --project-ref sqxhzlwqqhodbhfdnaxv
   supabase secrets set OPENAI_API_KEY=... ANTHROPIC_API_KEY=...
   supabase secrets set GEONAMES_USERNAME=...     # optional
   supabase functions deploy annotate-media
   ```
   Keys live only in Supabase secrets, never in this repo.

## Flow
Log in → open one of your stories → **Transcribe and annotate** → per audio/video:
**Transcribe and suggest terms** (Whisper transcript with timestamps, then Claude
finds mentions, then each mention is looked up in Getty AAT/TGN/ULAN, Wikidata and
GeoNames) → **Approve / Reject** each suggestion. Visitors see the transcript and the
approved terms; anyone can **Export JSON-LD**.

Limits: files over 25 MB can't be transcribed (OpenAI limit). Suggestions replace
earlier *unreviewed* suggestions when re-run; approved/rejected ones are kept.

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
