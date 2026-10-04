-- Transcripts and vocabulary annotations. Run in the Supabase SQL editor after
-- schema.sql. Safe to run again: it replaces its own policies.
--
-- Everything is written straight from the page by the story's owner, so no
-- server function or paid API key is needed. Everyone can read transcripts and
-- approved annotations; only the story owner can create, review or delete them.

create table if not exists public.media_transcripts (
  id         uuid primary key default gen_random_uuid(),
  media_id   uuid not null unique references public.story_media(id) on delete cascade,
  language   text,
  status     text not null default 'done' check (status in ('pending', 'done', 'error')),
  error      text,
  text       text not null default '',
  created_at timestamptz not null default now()
);

create table if not exists public.transcript_segments (
  id            uuid primary key default gen_random_uuid(),
  transcript_id uuid not null references public.media_transcripts(id) on delete cascade,
  idx           integer not null,
  start_s       real not null,
  end_s         real not null,
  text          text not null check (char_length(text) <= 1000),
  unique (transcript_id, idx)
);

-- Word timings for each transcript line: [{"w": "word", "s": start_seconds, "e": end_seconds}, ...]
alter table public.transcript_segments add column if not exists words jsonb;
alter table public.transcript_segments drop constraint if exists transcript_segments_words_check;
alter table public.transcript_segments add  constraint transcript_segments_words_check check (words is null or jsonb_typeof(words) = 'array');

create table if not exists public.annotations (
  id          uuid primary key default gen_random_uuid(),
  media_id    uuid not null references public.story_media(id) on delete cascade,
  segment_idx integer,
  start_s     real,
  end_s       real,
  mention     text not null default '',
  kind        text not null check (kind in ('person', 'place', 'event', 'object', 'material', 'concept')),
  vocabulary  text not null check (vocabulary in ('aat', 'tgn', 'ulan', 'wikidata', 'geonames')),
  term_uri    text not null check (term_uri ~ '^https?://'),
  label       text not null,
  description text not null default '',
  status      text not null default 'suggested' check (status in ('suggested', 'approved', 'rejected')),
  source      text not null default 'user',
  approved_by uuid references auth.users(id),
  approved_at timestamptz,
  created_at  timestamptz not null default now()
);

-- Older versions only allowed 'ai' and 'user'; 'auto' marks heuristic transcript suggestions
-- and 'clip' marks on-device image-match suggestions.
alter table public.annotations drop constraint if exists annotations_source_check;
alter table public.annotations add  constraint annotations_source_check check (source in ('ai', 'user', 'auto', 'clip'));

-- Image annotations: optional area as fractions (0-1) of the image width/height.
alter table public.annotations add column if not exists region_x real;
alter table public.annotations add column if not exists region_y real;
alter table public.annotations add column if not exists region_w real;
alter table public.annotations add column if not exists region_h real;
alter table public.annotations drop constraint if exists annotations_region_check;
alter table public.annotations add  constraint annotations_region_check check (
  (region_x is null and region_y is null and region_w is null and region_h is null)
  or (region_x between 0 and 1 and region_y between 0 and 1 and region_w > 0 and region_h > 0
      and region_x + region_w <= 1.0001 and region_y + region_h <= 1.0001)
);

create index if not exists annotations_media_idx on public.annotations(media_id);

alter table public.media_transcripts   enable row level security;
alter table public.transcript_segments enable row level security;
alter table public.annotations         enable row level security;

-- True when the signed-in user owns the story that this media belongs to.
create or replace function public.owns_media(mid uuid) returns boolean
language sql stable security invoker as $$
  select exists (
    select 1 from public.story_media m join public.stories s on s.id = m.story_id
    where m.id = mid and s.user_id = auth.uid()
  );
$$;

drop policy if exists "transcripts are public"          on public.media_transcripts;
drop policy if exists "owners write transcripts"        on public.media_transcripts;
drop policy if exists "owners update transcripts"       on public.media_transcripts;
drop policy if exists "owners delete transcripts"       on public.media_transcripts;
create policy "transcripts are public"    on public.media_transcripts for select using (true);
create policy "owners write transcripts"  on public.media_transcripts for insert to authenticated with check (public.owns_media(media_id));
create policy "owners update transcripts" on public.media_transcripts for update to authenticated using (public.owns_media(media_id)) with check (public.owns_media(media_id));
create policy "owners delete transcripts" on public.media_transcripts for delete to authenticated using (public.owns_media(media_id));

drop policy if exists "segments are public"      on public.transcript_segments;
drop policy if exists "owners write segments"    on public.transcript_segments;
drop policy if exists "owners delete segments"   on public.transcript_segments;
create policy "segments are public"    on public.transcript_segments for select using (true);
create policy "owners write segments"  on public.transcript_segments for insert to authenticated
  with check (exists (select 1 from public.media_transcripts t where t.id = transcript_id and public.owns_media(t.media_id)));
create policy "owners delete segments" on public.transcript_segments for delete to authenticated
  using (exists (select 1 from public.media_transcripts t where t.id = transcript_id and public.owns_media(t.media_id)));

drop policy if exists "approved annotations are public" on public.annotations;
drop policy if exists "owners add annotations"          on public.annotations;
drop policy if exists "owners review annotations"       on public.annotations;
drop policy if exists "owners delete annotations"       on public.annotations;
-- Everyone sees approved annotations; the owner also sees suggestions and rejections.
create policy "approved annotations are public" on public.annotations for select
  using (status = 'approved' or public.owns_media(media_id));
create policy "owners add annotations"    on public.annotations for insert to authenticated with check (public.owns_media(media_id));
create policy "owners review annotations" on public.annotations for update to authenticated using (public.owns_media(media_id)) with check (public.owns_media(media_id));
create policy "owners delete annotations" on public.annotations for delete to authenticated using (public.owns_media(media_id));
