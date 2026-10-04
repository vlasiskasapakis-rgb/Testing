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
  using (status = 'published' or user_id = auth.uid() or public.is_annotator());
create policy "owners add drafts" on public.stories for insert to authenticated
  with check (
    user_id = auth.uid() and status = 'draft'
    and consent_id is not null
    and exists (select 1 from public.consents c where c.id = consent_id and c.user_id = auth.uid())
  );
create policy "annotators publish" on public.stories for update to authenticated
  using (public.is_annotator()) with check (public.is_annotator());
create policy "owners delete own stories" on public.stories for delete to authenticated
  using (user_id = auth.uid());

-- ---------- media rows inherit the visibility of their story ----------
drop policy if exists "media is public"      on public.story_media;
drop policy if exists "read visible media"   on public.story_media;
create policy "read visible media" on public.story_media for select
  using (exists (select 1 from public.stories s where s.id = story_media.story_id));
-- "owners insert media" / "owners delete media" from schema.sql stay as they are.

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
alter table public.story_media
  add column if not exists title       text,
  add column if not exists about       text,
  add column if not exists recorded_at date,
  add column if not exists period      text,
  add column if not exists lat         double precision,
  add column if not exists lon         double precision;

-- Make the API pick up new columns immediately (avoids "could not find the column ... in the schema cache")
notify pgrst, 'reload schema';
