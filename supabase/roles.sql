-- Roles, publishing and image-to-time links. Run in the Supabase SQL editor AFTER
-- schema.sql and annotations.sql. Safe to run again.
--
--   facilitator (default for every new account): collects stories and uploads them
--                as drafts. Cannot transcribe, annotate or publish.
--   annotator:   sees every story (drafts included), transcribes, annotates, links
--                images to moments of audio/video and publishes.
--   everyone else (not logged in): sees only published stories.
--
-- To make someone an annotator (they must have signed up first), run:
--   update public.profiles set role = 'annotator'
--   where user_id = (select id from auth.users where email = 'person@example.com');

-- ---------- profiles & roles ----------
create table if not exists public.profiles (
  user_id    uuid primary key references auth.users(id) on delete cascade,
  role       text not null default 'facilitator' check (role in ('facilitator', 'annotator')),
  created_at timestamptz not null default now()
);
alter table public.profiles enable row level security;

drop policy if exists "read own profile" on public.profiles;
create policy "read own profile" on public.profiles for select to authenticated using (user_id = auth.uid());
-- No insert/update/delete policies: roles can only be changed here, as the project owner.

create or replace function public.handle_new_user() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  insert into public.profiles (user_id) values (new.id) on conflict (user_id) do nothing;
  return new;
end $$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created after insert on auth.users
  for each row execute function public.handle_new_user();

-- Accounts that existed before roles were introduced become facilitators.
insert into public.profiles (user_id) select id from auth.users on conflict (user_id) do nothing;

create or replace function public.is_annotator() returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.profiles where user_id = auth.uid() and role = 'annotator');
$$;

-- Analytics viewers (see the analytics section at the end): independent of facilitator/annotator.
alter table public.profiles add column if not exists is_admin boolean not null default false;
create or replace function public.is_admin() returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.profiles where user_id = auth.uid() and is_admin);
$$;
grant execute on function public.is_admin() to anon, authenticated;

-- ---------- consent ----------
-- Before a facilitator can add a story, the participant consents on the facilitator's device; the app
-- generates a short code (WM-XXXX-XXXX) from the record's id. The participant signs a paper form that
-- carries the same code, which is how a signed form is matched to its story(ies).
create table if not exists public.consents (
  id                uuid primary key default gen_random_uuid(),
  code              text not null unique check (code ~ '^WM-[A-Z0-9]{4}-[A-Z0-9]{4}$'),
  user_id           uuid default auth.uid() references auth.users(id) on delete set null,
  statement_version text not null,
  lang              text,
  accepted          jsonb not null,
  created_at        timestamptz not null default now()
);
alter table public.consents enable row level security;
drop policy if exists "read own or all consents" on public.consents;
drop policy if exists "add own consent"          on public.consents;
create policy "read own or all consents" on public.consents for select to authenticated
  using (user_id = auth.uid() or public.is_annotator());
create policy "add own consent" on public.consents for insert to authenticated
  with check (user_id = auth.uid());
-- No update/delete policies: a consent record is permanent.

alter table public.stories add column if not exists consent_id uuid references public.consents(id) on delete restrict;

-- To find the story behind a paper form (run as the project owner):
--   select c.code, s.title, s.status, s.created_at
--   from public.consents c left join public.stories s on s.consent_id = c.id
--   where c.code = 'WM-XXXX-XXXX';

-- ---------- publishing ----------
do $$
begin
  if not exists (select 1 from information_schema.columns
                 where table_schema = 'public' and table_name = 'stories' and column_name = 'status') then
    alter table public.stories add column status text not null default 'draft' check (status in ('draft', 'published'));
    -- Stories that existed before publishing was introduced stay visible.
    update public.stories set status = 'published';
  end if;
end $$;

-- Only the status column can be updated, and (policy below) only by annotators.
revoke update on public.stories from anon, authenticated;
grant update (status) on public.stories to authenticated;

drop policy if exists "stories are public"    on public.stories;
drop policy if exists "owners insert stories" on public.stories;
drop policy if exists "owners update stories" on public.stories;
drop policy if exists "owners delete stories" on public.stories;
drop policy if exists "read visible stories"  on public.stories;
drop policy if exists "owners add drafts"     on public.stories;
drop policy if exists "annotators publish"    on public.stories;
drop policy if exists "owners delete own stories" on public.stories;
create policy "read visible stories" on public.stories for select
  using (status = 'published' or user_id = auth.uid() or public.is_annotator() or public.is_admin());
create policy "owners add drafts" on public.stories for insert to authenticated
  with check (
    user_id = auth.uid() and status = 'draft'
    and consent_id is not null
    and exists (select 1 from public.consents c where c.id = consent_id and c.user_id = auth.uid())
  );
create policy "annotators publish" on public.stories for update to authenticated
  using (public.is_annotator()) with check (public.is_annotator());
create policy "owners delete own stories" on public.stories for delete to authenticated
  using (user_id = auth.uid() or public.is_annotator());   -- annotators may delete any story (annotation website)

-- ---------- media rows inherit the visibility of their story ----------
drop policy if exists "media is public"      on public.story_media;
drop policy if exists "read visible media"   on public.story_media;
create policy "read visible media" on public.story_media for select
  using (exists (select 1 from public.stories s where s.id = story_media.story_id));
-- "owners insert media" / "owners delete media" from schema.sql stay as they are.

-- Annotators who delete a story also remove its uploaded files from storage.
drop policy if exists "annotators delete files" on storage.objects;
create policy "annotators delete files" on storage.objects for delete to authenticated
  using (bucket_id = 'story-media' and public.is_annotator());

-- Reordering recordings: the owner of a story or an annotator may change the position of its media (nothing else).
drop policy if exists "reorder media" on public.story_media;
create policy "reorder media" on public.story_media for update to authenticated
  using (public.is_annotator() or exists (select 1 from public.stories s where s.id = story_media.story_id and s.user_id = auth.uid()))
  with check (public.is_annotator() or exists (select 1 from public.stories s where s.id = story_media.story_id and s.user_id = auth.uid()));
revoke update on public.story_media from authenticated;
grant update (position) on public.story_media to authenticated;

-- Word timings for each transcript line: [{"w": "word", "s": start_seconds, "e": end_seconds}, ...]
alter table public.transcript_segments add column if not exists words jsonb;
alter table public.transcript_segments drop constraint if exists transcript_segments_words_check;
alter table public.transcript_segments add  constraint transcript_segments_words_check check (words is null or jsonb_typeof(words) = 'array');

-- Annotation columns added after the first release (so this file alone brings an older database up to date).
alter table public.annotations drop constraint if exists annotations_source_check;
alter table public.annotations add  constraint annotations_source_check check (source in ('ai', 'user', 'auto', 'clip'));
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

-- Image annotations can be tied to a moment of the story: which audio/video, and when (start_s/end_s on that recording).
alter table public.annotations add column if not exists av_media_id uuid references public.story_media(id) on delete cascade;
alter table public.annotations drop constraint if exists annotations_av_time_check;
alter table public.annotations add  constraint annotations_av_time_check check (
  av_media_id is null or (start_s is not null and end_s is not null and end_s > start_s)
);
create index if not exists annotations_av_idx on public.annotations(av_media_id);

-- ---------- transcripts, segments, annotations: annotators write ----------
drop policy if exists "transcripts are public"    on public.media_transcripts;
drop policy if exists "owners write transcripts"  on public.media_transcripts;
drop policy if exists "owners update transcripts" on public.media_transcripts;
drop policy if exists "owners delete transcripts" on public.media_transcripts;
drop policy if exists "read visible transcripts"  on public.media_transcripts;
drop policy if exists "annotators write transcripts" on public.media_transcripts;
create policy "read visible transcripts" on public.media_transcripts for select
  using (exists (select 1 from public.story_media m where m.id = media_transcripts.media_id));
create policy "annotators write transcripts" on public.media_transcripts for all to authenticated
  using (public.is_annotator()) with check (public.is_annotator());

drop policy if exists "segments are public"    on public.transcript_segments;
drop policy if exists "owners write segments"  on public.transcript_segments;
drop policy if exists "owners delete segments" on public.transcript_segments;
drop policy if exists "read visible segments"  on public.transcript_segments;
drop policy if exists "annotators write segments" on public.transcript_segments;
create policy "read visible segments" on public.transcript_segments for select
  using (exists (select 1 from public.media_transcripts t where t.id = transcript_segments.transcript_id));
create policy "annotators write segments" on public.transcript_segments for all to authenticated
  using (public.is_annotator()) with check (public.is_annotator());

drop policy if exists "approved annotations are public" on public.annotations;
drop policy if exists "owners add annotations"          on public.annotations;
drop policy if exists "owners review annotations"       on public.annotations;
drop policy if exists "owners delete annotations"       on public.annotations;
drop policy if exists "read visible annotations"        on public.annotations;
drop policy if exists "annotators write annotations"    on public.annotations;
-- Is this media part of a published story (or one the signed-in user owns)? SECURITY DEFINER, so the answer does not
-- depend on the caller's own access to story_media/stories (a chain of nested row-level checks that can silently hide rows).
create or replace function public.media_is_public(mid uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from public.story_media m join public.stories s on s.id = m.story_id
    where m.id = mid and (s.status = 'published' or s.user_id = auth.uid())
  );
$$;
grant execute on function public.media_is_public(uuid) to anon, authenticated;
grant execute on function public.is_annotator() to anon, authenticated;

create policy "read visible annotations" on public.annotations for select
  using (public.is_annotator() or (status = 'approved' and public.media_is_public(media_id)));
create policy "annotators write annotations" on public.annotations for all to authenticated
  using (public.is_annotator()) with check (public.is_annotator());

-- ---------- images linked to moments of audio/video ----------
create table if not exists public.media_links (
  id             uuid primary key default gen_random_uuid(),
  story_id       uuid not null references public.stories(id) on delete cascade,
  image_media_id uuid not null references public.story_media(id) on delete cascade,
  av_media_id    uuid not null references public.story_media(id) on delete cascade,
  start_s        real not null check (start_s >= 0),
  end_s          real not null,
  created_at     timestamptz not null default now(),
  check (end_s > start_s)
);
create index if not exists media_links_story_idx on public.media_links(story_id);
alter table public.media_links enable row level security;

drop policy if exists "read visible links"     on public.media_links;
drop policy if exists "annotators write links" on public.media_links;
create policy "read visible links" on public.media_links for select
  using (exists (select 1 from public.stories s where s.id = media_links.story_id));
create policy "annotators write links" on public.media_links for all to authenticated
  using (public.is_annotator())
  with check (
    public.is_annotator()
    and exists (select 1 from public.story_media i where i.id = image_media_id and i.story_id = media_links.story_id and i.kind = 'image')
    and exists (select 1 from public.story_media a where a.id = av_media_id and a.story_id = media_links.story_id and a.kind in ('audio', 'video'))
  );

-- Per-file details entered by the facilitator: title, identity (who/what), date recorded, period it refers to, location
alter table public.story_media add column if not exists title text;
alter table public.story_media add column if not exists about text;
alter table public.story_media add column if not exists recorded_at date;
alter table public.story_media add column if not exists period text;
alter table public.story_media add column if not exists lat double precision;
alter table public.story_media add column if not exists lon double precision;

-- Why a suggested term was proposed (confidence and evidence from the transcript, details and location)
alter table public.annotations add column if not exists reason text;

-- Where a term on a transcript line took place (optional; filled from Wikidata when known, or picked on the map by an annotator)
alter table public.annotations add column if not exists lat double precision;
alter table public.annotations add column if not exists lon double precision;
alter table public.annotations drop constraint if exists annotations_geo_check;
alter table public.annotations add  constraint annotations_geo_check check (
  (lat is null) = (lon is null) and (lat is null or (lat between -90 and 90 and lon between -180 and 180)));

-- ---------- analytics ----------
-- Who may see the analytics website: accounts with is_admin = true (independent of facilitator/annotator).
--   update public.profiles set is_admin = true
--   where user_id = (select id from auth.users where email = 'you@example.com');

-- 1) Story consumption in the app. visitor_id is a random id kept in the visitor's browser (no name, e-mail or IP).
create table if not exists public.story_views (
  id         bigserial primary key,
  created_at timestamptz not null default now(),
  visitor_id uuid not null,
  user_id    uuid,
  story_id   uuid not null references public.stories(id) on delete cascade,
  media_id   uuid references public.story_media(id) on delete cascade,
  event      text not null check (event in ('open', 'play', 'complete')),
  via        text check (via in ('ar', 'map', 'list', 'nearest'))
);
-- 'walk' = opened from the "next stop" card while following a walk
alter table public.story_views drop constraint if exists story_views_via_check;
alter table public.story_views add  constraint story_views_via_check check (via in ('ar', 'map', 'list', 'nearest', 'walk'));
create index if not exists story_views_story_idx on public.story_views(story_id, created_at);
create index if not exists story_views_time_idx  on public.story_views(created_at);
alter table public.story_views enable row level security;
drop policy if exists "anyone records views" on public.story_views;
create policy "anyone records views" on public.story_views for insert to anon, authenticated
  with check ((user_id is null or user_id = auth.uid()) and exists (select 1 from public.stories s where s.id = story_id));
drop policy if exists "admins read views" on public.story_views;
create policy "admins read views" on public.story_views for select to authenticated using (public.is_admin());
grant insert on public.story_views to anon, authenticated;
grant select on public.story_views to authenticated;
grant usage on sequence public.story_views_id_seq to anon, authenticated;

-- 2) Annotators' corrections. Term changes are recorded by a trigger (cannot be skipped by the page);
--    transcript saves are recorded by the annotation website with the number of corrected words/lines.
create table if not exists public.annotation_activity (
  id         bigserial primary key,
  created_at timestamptz not null default now(),
  user_id    uuid default auth.uid(),
  user_name  text,
  story_id   uuid,          -- no foreign keys: the history stays when a story is deleted
  media_id   uuid,
  kind       text not null check (kind in ('transcript_save', 'term_approve', 'term_reject', 'term_undo',
                                           'term_add', 'term_edit', 'term_delete', 'note_add', 'note_delete')),
  source     text,
  amount     integer not null default 1,
  detail     jsonb
);
create index if not exists annotation_activity_time_idx on public.annotation_activity(created_at);
alter table public.annotation_activity enable row level security;
drop policy if exists "annotators record activity" on public.annotation_activity;
create policy "annotators record activity" on public.annotation_activity for insert to authenticated
  with check (public.is_annotator() and user_id = auth.uid() and kind = 'transcript_save');
drop policy if exists "admins read activity" on public.annotation_activity;
create policy "admins read activity" on public.annotation_activity for select to authenticated using (public.is_admin());
grant insert, select on public.annotation_activity to authenticated;
grant usage on sequence public.annotation_activity_id_seq to authenticated;

create or replace function public.log_annotation_change() returns trigger
language plpgsql security definer set search_path = public as $$
declare
  r public.annotations; k text; mkind text; sid uuid; uname text;
begin
  if auth.uid() is null then                                       -- not a person using the website
    return coalesce(new, old);
  end if;
  r := coalesce(new, old);
  if tg_op = 'INSERT' then
    if new.source <> 'user' then return new; end if;              -- machine suggestions are not corrections
  elsif tg_op = 'DELETE' then
    if old.source = 'auto' and old.status = 'suggested' then return old; end if;   -- replaced suggestions
  end if;
  select m.kind, m.story_id into mkind, sid from public.story_media m where m.id = r.media_id;
  if mkind is null then return coalesce(new, old); end if;          -- the file itself is being deleted (story removed)
  if tg_op = 'INSERT' then
    k := case when mkind = 'image' then 'note_add' else 'term_add' end;
  elsif tg_op = 'DELETE' then
    k := case when mkind = 'image' then 'note_delete' else 'term_delete' end;
  elsif old.status is distinct from new.status then
    k := case new.status when 'approved' then 'term_approve' when 'rejected' then 'term_reject' else 'term_undo' end;
  elsif (old.start_s, old.end_s, old.kind, old.region_x, old.region_y, old.region_w, old.region_h, old.lat, old.lon)
        is distinct from (new.start_s, new.end_s, new.kind, new.region_x, new.region_y, new.region_w, new.region_h, new.lat, new.lon) then
    k := 'term_edit';
  else
    return new;
  end if;
  select coalesce(u.raw_user_meta_data->>'display_name', split_part(u.email, '@', 1)) into uname from auth.users u where u.id = auth.uid();
  insert into public.annotation_activity (user_id, user_name, story_id, media_id, kind, source, detail)
  values (auth.uid(), uname, sid, r.media_id, k, r.source, jsonb_build_object('term', r.label, 'term_uri', r.term_uri));
  return coalesce(new, old);
end $$;
drop trigger if exists annotations_activity on public.annotations;
create trigger annotations_activity after insert or update or delete on public.annotations
  for each row execute function public.log_annotation_change();

-- ---------- expert comments on transcript lines (annotation website), shown to everyone who can see the story ----------
create table if not exists public.transcript_comments (
  id          uuid primary key default gen_random_uuid(),
  media_id    uuid not null references public.story_media(id) on delete cascade,
  segment_idx integer,
  start_s     real,
  end_s       real,
  body        text not null check (char_length(body) between 1 and 2000),
  author_name text,
  created_by  uuid default auth.uid() references auth.users(id) on delete set null,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now()
);
create index if not exists transcript_comments_media_idx on public.transcript_comments(media_id);
alter table public.transcript_comments enable row level security;
drop policy if exists "read visible comments"       on public.transcript_comments;
drop policy if exists "annotators write comments"   on public.transcript_comments;
create policy "read visible comments" on public.transcript_comments for select
  using (public.is_annotator() or public.media_is_public(media_id));
create policy "annotators write comments" on public.transcript_comments for all to authenticated
  using (public.is_annotator()) with check (public.is_annotator());
revoke all on public.transcript_comments from anon;
grant select (id, media_id, segment_idx, start_s, end_s, body, author_name, created_at, updated_at) on public.transcript_comments to anon;
grant select, insert, update, delete on public.transcript_comments to authenticated;

-- ---------- story links (connect/ page): boards where annotators place stories and connect them ----------
-- A board holds stories (with their position on the board) and directed links "this story, then that one".
create table if not exists public.story_boards (
  id          uuid primary key default gen_random_uuid(),
  title       text not null check (char_length(title) between 1 and 200),
  created_by  uuid default auth.uid() references auth.users(id) on delete set null,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now()
);
create table if not exists public.story_board_items (
  board_id    uuid not null references public.story_boards(id) on delete cascade,
  story_id    uuid not null references public.stories(id) on delete cascade,
  x           real not null default 0,
  y           real not null default 0,
  primary key (board_id, story_id)
);
-- Links can only join stories that are on the same board; removing a story from the board (or deleting the story) removes its links.
create table if not exists public.story_board_links (
  id          uuid primary key default gen_random_uuid(),
  board_id    uuid not null references public.story_boards(id) on delete cascade,
  from_story  uuid not null,
  to_story    uuid not null,
  label       text check (label is null or char_length(label) <= 200),
  created_by  uuid default auth.uid() references auth.users(id) on delete set null,
  created_at  timestamptz not null default now(),
  check (from_story <> to_story),
  unique (board_id, from_story, to_story),
  foreign key (board_id, from_story) references public.story_board_items(board_id, story_id) on delete cascade,
  foreign key (board_id, to_story)   references public.story_board_items(board_id, story_id) on delete cascade
);
create index if not exists story_board_links_board_idx on public.story_board_links(board_id);
alter table public.story_boards      enable row level security;
alter table public.story_board_items enable row level security;
alter table public.story_board_links enable row level security;
drop policy if exists "read boards"        on public.story_boards;
drop policy if exists "annotators boards"  on public.story_boards;
drop policy if exists "read board items"   on public.story_board_items;
drop policy if exists "annotators items"   on public.story_board_items;
drop policy if exists "read board links"   on public.story_board_links;
drop policy if exists "annotators links"   on public.story_board_links;
create policy "read boards"       on public.story_boards      for select to authenticated using (public.is_annotator() or public.is_admin());
create policy "annotators boards" on public.story_boards      for all    to authenticated using (public.is_annotator()) with check (public.is_annotator());
create policy "read board items"  on public.story_board_items for select to authenticated using (public.is_annotator() or public.is_admin());
create policy "annotators items"  on public.story_board_items for all    to authenticated using (public.is_annotator()) with check (public.is_annotator());
create policy "read board links"  on public.story_board_links for select to authenticated using (public.is_annotator() or public.is_admin());
create policy "annotators links"  on public.story_board_links for all    to authenticated using (public.is_annotator()) with check (public.is_annotator());
grant select, insert, update, delete on public.story_boards, public.story_board_items, public.story_board_links to authenticated;

-- Walks in the AR app: a board marked is_walk is shown to visitors as a walk (its stories in the order of the links).
-- Visitors only see published stories, so drafts on a walk are skipped in the app.
alter table public.story_boards add column if not exists is_walk boolean not null default false;
alter table public.story_boards add column if not exists description text;
alter table public.story_boards drop constraint if exists story_boards_description_check;
alter table public.story_boards add  constraint story_boards_description_check check (description is null or char_length(description) <= 1000);
drop policy if exists "visitors read walks"      on public.story_boards;
drop policy if exists "visitors read walk items" on public.story_board_items;
drop policy if exists "visitors read walk links" on public.story_board_links;
create policy "visitors read walks"      on public.story_boards      for select to anon, authenticated using (is_walk);
create policy "visitors read walk items" on public.story_board_items for select to anon, authenticated
  using (exists (select 1 from public.story_boards b where b.id = board_id and b.is_walk));
create policy "visitors read walk links" on public.story_board_links for select to anon, authenticated
  using (exists (select 1 from public.story_boards b where b.id = board_id and b.is_walk));
-- Visitors get only the columns the app needs (not who created a board or a link).
revoke all on public.story_boards, public.story_board_items, public.story_board_links from anon;
grant select (id, title, description, is_walk, created_at, updated_at) on public.story_boards to anon;
grant select (board_id, story_id, x, y) on public.story_board_items to anon;
grant select (id, board_id, from_story, to_story, label) on public.story_board_links to anon;

-- Make the API pick up new columns immediately (avoids "could not find the column ... in the schema cache")
notify pgrst, 'reload schema';
