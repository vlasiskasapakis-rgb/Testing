// Supabase Edge Function: for annotators only, ask a Groq text model (same GROQ_API_KEY as
// transcribe-media) which people, places, events, objects, materials, practices and concepts a
// story's transcripts and file details mention. It returns the exact words and line of each
// mention, the base form of the name and an English name. It does NOT return links: the page
// looks every name up in Wikidata itself, so nothing invented can become an annotation.
// Nothing is saved here.
//
// Secrets (Edge Functions -> Secrets): GROQ_API_KEY (required), GROQ_TEXT_MODEL (optional).
// SUPABASE_URL / SUPABASE_ANON_KEY / SUPABASE_SERVICE_ROLE_KEY are provided by Supabase.

// @ts-ignore: resolved by Deno at runtime
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';
declare const Deno: any;

// Tried in order; a model Groq no longer offers is skipped. GROQ_TEXT_MODEL (if set) goes first.
const MODELS = ['openai/gpt-oss-120b', 'llama-3.3-70b-versatile'];
const LANG_NAMES: Record<string, string> = { el: 'Greek', en: 'English', fr: 'French', it: 'Italian' };
const TYPES = ['person', 'place', 'event', 'object', 'material', 'practice', 'concept'];
const CHUNK_CHARS = 6000;     // transcript characters per request (free-tier tokens per minute are limited)
const MAX_CHUNKS = 12;
const MAX_TERMS = 600;

const cors = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
};
const json = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), { status, headers: { ...cors, 'Content-Type': 'application/json' } });

// ---- pure helpers (no network) ----
function norm(s: string): string {
  return String(s || '').normalize('NFD').replace(/[̀-ͯ]/g, '').toLowerCase()
    .replace(/[^\p{L}\p{N}]+/gu, ' ').trim();
}
function sameTok(a: string, b: string): boolean {
  if (a === b) return true;
  const n = Math.min(a.length, b.length); if (n < 4) return false;
  let i = 0; while (i < n && a[i] === b[i]) i++;
  return i >= Math.max(4, n - 2);
}
// The words the model quoted, exactly as they are in the line (or null when they are not there).
function wordsInLine(line: string, words: string, name: string): string | null {
  const raw = String(line).split(/\s+/).filter(Boolean);
  const toks = raw.map(norm);
  for (const q of [words, name]) {
    const qt = norm(q).split(' ').filter(Boolean);
    if (!qt.length || qt.length > 8) continue;
    for (let i = 0; i + qt.length <= toks.length; i++) {
      let ok = true;
      for (let j = 0; j < qt.length; j++) if (!sameTok(toks[i + j], qt[j])) { ok = false; break; }
      if (ok) return raw.slice(i, i + qt.length).join(' ').replace(/^[«"“'(\[]+|[»"”'),.;:·!?\]]+$/g, '');
    }
  }
  return null;
}
type Line = { key: string; idx: number; text: string };
type FileInfo = { key: string; id: string; kind: string; details: string };
function chunkLines(lines: Line[]): Line[][] {
  const out: Line[][] = []; let cur: Line[] = [], size = 0;
  for (const l of lines) {
    if (size + l.text.length > CHUNK_CHARS && cur.length) { out.push(cur); cur = []; size = 0; }
    cur.push(l); size += l.text.length + 12;
  }
  if (cur.length) out.push(cur);
  return out.slice(0, MAX_CHUNKS);
}
function buildPrompt(lang: string, files: FileInfo[], lines: Line[], withDetails: boolean): string {
  const L = LANG_NAMES[lang] || 'Greek';
  return [
    `You help archivists index an oral-history story (recordings in ${L}). Find every term an annotator would tag:`,
    `- person: named people (also family members when named);`,
    `- place: towns, villages, neighbourhoods, streets, buildings, churches, monasteries, landmarks, regions, countries;`,
    `- event: historical events, wars, disasters, feasts, festivals, fairs;`,
    `- object: tools, artefacts, furniture, garments, foods, dishes, vehicles, instruments;`,
    `- material: wool, clay, olive oil, silk …;`,
    `- practice: crafts, trades, customs, rituals, farming or household practices (e.g. weaving, grape harvest, soap making);`,
    `- concept: other notions of cultural or historical importance.`,
    `Skip very generic words with no heritage value (people, thing, time, day, house, life, place).`,
    ``,
    `Return JSON only: {"m":[...],"d":[...]}`,
    `"m" = mentions in the transcript lines, one entry per line where the term is said:`,
    `  {"f": file key, "l": line number, "w": the exact words as written in that line (1-6 words, copied verbatim),`,
    `   "n": the base dictionary form in ${L} (nominative singular; for names the usual full name), "en": the English name, "t": type}`,
    withDetails ? `"d" = terms from the FILE DETAILS that are not in the lines: {"f": file key, "n": ..., "en": ..., "t": ...}` : `"d" = []`,
    `Types: ${TYPES.join(', ')}. At most 150 entries in "m". No explanations.`,
    ``,
    `FILE DETAILS:`,
    ...files.map((f) => `${f.key} (${f.kind}): ${f.details || '—'}`),
    ``,
    `TRANSCRIPT LINES (file#line: text):`,
    ...lines.map((l) => `${l.key}#${l.idx}: ${l.text}`),
  ].join('\n');
}
function parseModelJson(text: string): any {
  try { return JSON.parse(text); } catch { /* try the first {...} block */ }
  const a = text.indexOf('{'), b = text.lastIndexOf('}');
  if (a >= 0 && b > a) { try { return JSON.parse(text.slice(a, b + 1)); } catch { /* fall through */ } }
  return null;
}
// Keeps only mentions that point at a real line and whose words are really in it.
function validate(out: any, files: FileInfo[], lineOf: Map<string, string>) {
  const byKey = new Map(files.map((f) => [f.key, f]));
  const terms: any[] = [];
  for (const x of (Array.isArray(out?.m) ? out.m : []).slice(0, 200)) {
    const f = byKey.get(String(x?.f || '')); const idx = Number(x?.l);
    const name = String(x?.n || '').trim().slice(0, 120), en = String(x?.en || '').trim().slice(0, 120);
    if (!f || !Number.isInteger(idx) || !name) continue;
    const line = lineOf.get(f.key + '#' + idx); if (line == null) continue;
    const w = wordsInLine(line, String(x?.w || ''), name); if (!w) continue;
    terms.push({ media_id: f.id, idx, words: w.slice(0, 120), name, en, type: TYPES.includes(x?.t) ? x.t : 'concept' });
  }
  for (const x of (Array.isArray(out?.d) ? out.d : []).slice(0, 60)) {
    const f = byKey.get(String(x?.f || '')); const name = String(x?.n || '').trim().slice(0, 120);
    if (!f || !name) continue;
    terms.push({ media_id: f.id, idx: null, words: null, name, en: String(x?.en || '').trim().slice(0, 120), type: TYPES.includes(x?.t) ? x.t : 'concept' });
  }
  return terms;
}
// ---- end of pure helpers ----

async function callGroq(key: string, models: string[], prompt: string): Promise<{ ok: boolean; status?: number; data?: any; model?: string; error?: string }> {
  let last = { ok: false, status: 502, error: 'no model available' } as any;
  for (const model of models) {
    const body: any = {
      model, temperature: 0.1, max_tokens: 6000, response_format: { type: 'json_object' },
      messages: [{ role: 'system', content: 'You extract index terms for a cultural-heritage archive. Answer with JSON only.' }, { role: 'user', content: prompt }],
    };
    if (model.startsWith('openai/gpt-oss')) body.reasoning_effort = 'low';
    for (let attempt = 0; attempt < 2; attempt++) {
      const r = await fetch('https://api.groq.com/openai/v1/chat/completions', {
        method: 'POST', headers: { Authorization: `Bearer ${key}`, 'Content-Type': 'application/json' }, body: JSON.stringify(body),
      });
      if (r.status === 429) {                       // per-minute limit: wait once if the wait is short
        const wait = Number(r.headers.get('retry-after')) || 0;
        if (attempt === 0 && wait > 0 && wait <= 20) { await new Promise((ok) => setTimeout(ok, wait * 1000)); continue; }
        return { ok: false, status: 429, error: 'quota' };
      }
      const txt = await r.text();
      if (!r.ok) {
        last = { ok: false, status: r.status, error: txt.slice(0, 300) };
        if ((r.status === 400 || r.status === 404) && /model/i.test(txt)) break;   // model retired or unknown: next one
        if (r.status === 400 && /json/i.test(txt)) break;                         // could not produce JSON: next one
        return last;
      }
      const d = parseModelJson(txt);
      const content = d?.choices?.[0]?.message?.content ?? '';
      const out = parseModelJson(content);
      if (out) return { ok: true, data: out, model };
      last = { ok: false, status: 502, error: 'the model did not return JSON' };
      break;
    }
  }
  return last;
}

if (typeof Deno !== 'undefined' && Deno.serve) Deno.serve(async (req: Request) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: cors });
  const url = Deno.env.get('SUPABASE_URL'), anon = Deno.env.get('SUPABASE_ANON_KEY'), svc = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY');
  const groqKey = Deno.env.get('GROQ_API_KEY');
  if (!groqKey) return json({ error: 'GROQ_API_KEY is not set on the server' }, 500);
  const models = [Deno.env.get('GROQ_TEXT_MODEL'), ...MODELS].filter((m, i, a) => m && a.indexOf(m) === i) as string[];

  const userClient = createClient(url, anon, { global: { headers: { Authorization: req.headers.get('Authorization') ?? '' } } });
  const { data: u } = await userClient.auth.getUser();
  if (!u?.user) return json({ error: 'Not signed in' }, 401);

  let storyId = '', lang = 'el';
  try {
    const body = await req.json();
    storyId = String(body.story_id || '');
    if (LANG_NAMES[body.language]) lang = body.language;
  } catch { /* handled below */ }
  if (!/^[0-9a-f-]{36}$/i.test(storyId)) return json({ error: 'story_id required' }, 400);

  const admin = createClient(url, svc);
  const { data: profile } = await admin.from('profiles').select('role').eq('user_id', u.user.id).single();
  if (profile?.role !== 'annotator') return json({ error: 'Only annotators can ask for suggestions' }, 403);

  let media: any[] | null = null;
  const full = await admin.from('story_media').select('id,kind,position,title,about,recorded_at,period,lat,lon').eq('story_id', storyId).order('position');
  if (full.error) media = (await admin.from('story_media').select('id,kind,position').eq('story_id', storyId).order('position')).data;
  else media = full.data;
  if (!media || !media.length) return json({ error: 'Story not found or has no files' }, 404);
  const { data: trs } = await admin.from('media_transcripts').select('media_id,transcript_segments(idx,text)').in('media_id', media.map((m) => m.id));

  const files: FileInfo[] = media.map((m, i) => ({
    key: 'F' + (i + 1), id: m.id, kind: m.kind,
    details: [m.title && `title: ${m.title}`, m.about && `identity/about: ${m.about}`, m.period && `time: ${m.period}`, m.recorded_at && `recorded: ${m.recorded_at}`,
      m.lat != null && m.lon != null && `location: ${(+m.lat).toFixed(4)}, ${(+m.lon).toFixed(4)}`].filter(Boolean).join('; '),
  }));
  const keyOf = new Map(files.map((f) => [f.id, f.key]));
  const lines: Line[] = [], lineOf = new Map<string, string>();
  for (const tr of trs || []) {
    const k = keyOf.get(tr.media_id); if (!k) continue;
    for (const g of (tr.transcript_segments || []).sort((a: any, b: any) => a.idx - b.idx)) {
      const text = String(g.text || '').trim(); if (!text) continue;
      lines.push({ key: k, idx: g.idx, text }); lineOf.set(k + '#' + g.idx, text);
    }
  }
  lines.sort((a, b) => (a.key === b.key ? a.idx - b.idx : Number(a.key.slice(1)) - Number(b.key.slice(1))));
  const chunks = lines.length ? chunkLines(lines) : [[]];

  const terms: any[] = []; let model = '', partial = false, done = 0;
  for (let i = 0; i < chunks.length; i++) {
    const r = await callGroq(groqKey, models, buildPrompt(lang, files, chunks[i], i === 0));
    if (!r.ok) {
      if (!done) return json({ error: r.status === 429 ? 'The free AI quota is used up for now. Try again later.' : `AI service error (${r.status}): ${r.error}` }, r.status === 429 ? 429 : 502);
      partial = true; break;
    }
    done++; model = r.model || model;
    terms.push(...validate(r.data, files, lineOf));
    if (terms.length >= MAX_TERMS) break;
  }
  return json({ ok: true, model, chunks: chunks.length, done, partial, linesTotal: lines.length, terms: terms.slice(0, MAX_TERMS) });
});

export { norm, sameTok, wordsInLine, chunkLines, buildPrompt, parseModelJson, validate, callGroq };
