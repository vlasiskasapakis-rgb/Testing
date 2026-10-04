// Supabase Edge Function: for annotators only, transcribe a story recording with Groq's
// hosted Whisper (free tier) and return timestamped segments. Nothing is saved here;
// the page puts the text in the transcript box for the owner to edit.
//
// Secret (Edge Functions -> Secrets): GROQ_API_KEY.
// SUPABASE_URL / SUPABASE_ANON_KEY / SUPABASE_SERVICE_ROLE_KEY are provided by Supabase.

// @ts-ignore: resolved by Deno at runtime
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';
declare const Deno: any;

const MODEL = 'whisper-large-v3';
const MAX_BYTES = 25 * 1024 * 1024;   // Groq's free-tier file limit
const LANGS = ['el', 'en', 'fr', 'it'];

const cors = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
};
const json = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), { status, headers: { ...cors, 'Content-Type': 'application/json' } });

Deno.serve(async (req: Request) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: cors });
  const url = Deno.env.get('SUPABASE_URL'), anon = Deno.env.get('SUPABASE_ANON_KEY'), svc = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY');
  const groqKey = Deno.env.get('GROQ_API_KEY');
  if (!groqKey) return json({ error: 'GROQ_API_KEY is not set on the server' }, 500);

  const userClient = createClient(url, anon, { global: { headers: { Authorization: req.headers.get('Authorization') ?? '' } } });
  const { data: u } = await userClient.auth.getUser();
  if (!u?.user) return json({ error: 'Not signed in' }, 401);

  let mediaId = '', lang = '';
  try {
    const body = await req.json();
    mediaId = String(body.media_id || '');
    lang = LANGS.includes(body.language) ? body.language : '';
  } catch { /* handled below */ }
  if (!/^[0-9a-f-]{36}$/i.test(mediaId)) return json({ error: 'media_id required' }, 400);

  const admin = createClient(url, svc);
  const { data: profile } = await admin.from('profiles').select('role').eq('user_id', u.user.id).single();
  if (profile?.role !== 'annotator') return json({ error: 'Only annotators can transcribe' }, 403);
  const { data: media } = await admin.from('story_media').select('id,kind,path').eq('id', mediaId).single();
  if (!media) return json({ error: 'Media not found' }, 404);
  if (media.kind === 'image') return json({ error: 'Images have no audio to transcribe' }, 400);

  const dl = await admin.storage.from('story-media').download(media.path);
  if (dl.error || !dl.data) return json({ error: 'Could not read the media file' }, 500);
  if (dl.data.size > MAX_BYTES) return json({ error: 'File is larger than 25 MB, the free transcription limit' }, 413);

  const form = new FormData();
  form.append('file', dl.data, media.path.split('/').pop() || 'media');
  form.append('model', MODEL);
  form.append('response_format', 'verbose_json');
  form.append('timestamp_granularities[]', 'segment');
  form.append('timestamp_granularities[]', 'word');
  if (lang) form.append('language', lang);

  const r = await fetch('https://api.groq.com/openai/v1/audio/transcriptions', {
    method: 'POST', headers: { Authorization: `Bearer ${groqKey}` }, body: form,
  });
  if (r.status === 429) return json({ error: 'The free transcription quota is used up for now. Try again later.' }, 429);
  if (!r.ok) return json({ error: `Transcription service error (${r.status})` }, 502);

  const d = await r.json();
  const segments = (d.segments || []).map((s: any) => ({
    start_s: Number(s.start) || 0, end_s: Number(s.end) || 0, text: String(s.text || '').trim(),
  })).filter((s: any) => s.text);
  if (!segments.length && d.text) segments.push({ start_s: 0, end_s: 0, text: String(d.text).trim() });
  // Attach word timings (when the service returns them) to the segment they fall in, so annotations
  // can point at the exact seconds a word is spoken.
  const words = (d.words || []).map((w: any) => ({ w: String(w.word || '').trim(), s: Number(w.start) || 0, e: Number(w.end) || 0 })).filter((w: any) => w.w);
  for (const sg of segments as any[]) {
    const inSeg = words.filter((w: any) => w.s >= sg.start_s - 0.05 && w.s < sg.end_s + 0.05).slice(0, 300);
    sg.words = inSeg.length ? inSeg.map((w: any) => ({ w: w.w, s: +w.s.toFixed(2), e: +w.e.toFixed(2) })) : null;
  }
  return json({ ok: true, segments });
});
