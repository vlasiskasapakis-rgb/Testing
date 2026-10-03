-- Transcripts and vocabulary annotations. Run once in the Supabase SQL editor,
-- after schema.sql. Transcripts and AI suggestions are written by the
-- annotate-media Edge Function (service role); people can only change the
-- review status of annotations on their own stories.

create table if not exists public.media_transcripts (
  id         uuid primary key default gen_random_uuid(),
  media_id   uuid not null unique references public.story_media(id) on delete cascade,
  language   text,
  status     text not null default 'pending' check (status in ('pending', 'done', 'error')),
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
  text          text not null,
  unique (transcript_id, idx)
);

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
  source      text not null default 'ai' check (source in ('ai', 'user')),
  approved_by uuid references auth.users(id),
  approved_at timestamptz,
  created_at  timestamptz not null default now()
);

create index if not exists annotations_media_idx on public.annotations(media_id);

alter table public.media_transcripts   enable row level security;
alter table public.transcript_segments enable row level security;
alter table public.annotations         enable row level security;

create policy "transcripts are public" on public.media_transcripts   for select using (true);
create policy "segments are public"    on public.transcript_segments for select using (true);

-- Everyone sees approved annotations; the story owner also sees suggestions and rejections.
create policy "approved annotations are public" on public.annotations for select
  using (
    status = 'approved'
    or exists (
      select 1 from public.story_media m join public.stories s on s.id = m.story_id
      where m.id = media_id and s.user_id = auth.uid()
    )
  );

create policy "owners review annotations" on public.annotations for update to authenticated
  using (exists (select 1 from public.story_media m join public.stories s on s.id = m.story_id
                 where m.id = media_id and s.user_id = auth.uid()))
  with check (exists (select 1 from public.story_media m join public.stories s on s.id = m.story_id
                      where m.id = media_id and s.user_id = auth.uid()));

create policy "owners delete annotations" on public.annotations for delete to authenticated
  using (exists (select 1 from public.story_media m join public.stories s on s.id = m.story_id
                 where m.id = media_id and s.user_id = auth.uid()));
