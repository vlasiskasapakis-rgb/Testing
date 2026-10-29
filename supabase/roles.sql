-- Roles, sites, the facilitator workflow, publishing and image-to-time links. Run in the Supabase SQL editor AFTER
-- schema.sql and annotations.sql. Safe to run again.
--
--   facilitator (default for every new account): belongs to one pilot site; creates testimonies, their stories and
--                the stories' fragments for that site, and goes through each testimony with the community (community
--                validation).
--                An account without a site can do nothing yet.
--   annotator:   transcribes, annotates and links images to moments of audio/video in the stories of testimonies the
--                community has validated, marks each story as annotated, and makes the final export of a testimony,
--                which publishes its stories. Also publishes walks. Annotators without a site see every site.
--                (There are no validators any more.)
--   admin:       manages sites, languages and accounts (admin page); sees everything.
--   everyone else (not logged in): sees only published stories.
--
-- Accounts are created by an admin (Supabase dashboard: Authentication > Users > Add user); the admin page then sets
-- each account's site and role. To make the first admin, run:
--   update public.profiles set is_admin = true
--   where user_id = (select id from auth.users where email = 'you@example.com');

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

-- ---------- pilot sites ----------
-- Every account belongs to one pilot site (set on the admin page). A facilitator sees and acts only on the testimonies
-- and stories of that site. Annotators and admins without a site see every site.
create table if not exists public.sites (
  id         uuid primary key default gen_random_uuid(),
  name       text not null unique check (char_length(name) between 1 and 120),
  created_at timestamptz not null default now()
);
-- Languages and dialects offered for stories (an admin can add dialects on the admin page).
create table if not exists public.story_languages (
  code     text primary key check (code ~ '^[a-z0-9-]{2,40}$'),
  label    text not null check (char_length(label) between 1 and 120),
  position smallint not null default 100
);
insert into public.story_languages (code, label, position) values
  ('el', 'Ελληνικά', 1), ('en', 'English', 2), ('fr', 'Français', 3), ('it', 'Italiano', 4)
on conflict (code) do nothing;
alter table public.profiles add column if not exists site_id uuid references public.sites(id) on delete set null;

create or replace function public.my_site() returns uuid
language sql stable security definer set search_path = public as $$
  select site_id from public.profiles where user_id = auth.uid();
$$;
-- A facilitator who belongs to a site.
create or replace function public.is_facilitator() returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.profiles where user_id = auth.uid() and role = 'facilitator' and site_id is not null);
$$;
-- May the signed-in staff member see records of this site? Admins: every site. Annotators: their site, or every site
-- when they have none. Facilitators: only their own site.
create or replace function public.sees_site(sid uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.profiles p where p.user_id = auth.uid() and (
    p.is_admin or (p.role = 'annotator' and (p.site_id is null or p.site_id = sid)) or (p.role = 'facilitator' and p.site_id = sid)));
$$;
-- (visitors need them too: the read rules of published stories call them; for a visitor they return nothing / false)
grant execute on function public.my_site(), public.is_facilitator(), public.sees_site(uuid) to anon, authenticated;

alter table public.sites           enable row level security;
alter table public.story_languages enable row level security;
drop policy if exists "staff read sites"       on public.sites;
drop policy if exists "admins write sites"     on public.sites;
drop policy if exists "staff read languages"   on public.story_languages;
drop policy if exists "admins write languages" on public.story_languages;
create policy "staff read sites"       on public.sites           for select to authenticated using (true);
create policy "admins write sites"     on public.sites           for all    to authenticated using (public.is_admin()) with check (public.is_admin());
create policy "staff read languages"   on public.story_languages for select to authenticated using (true);
create policy "admins write languages" on public.story_languages for all    to authenticated using (public.is_admin()) with check (public.is_admin());
revoke all on public.sites, public.story_languages from anon;
grant select, insert, update, delete on public.sites, public.story_languages to authenticated;

-- ---------- testimonies ----------
-- A testimony is one interview with one narrator, under one printed consent form, and holds stories (a story holds
-- fragments). The signed form stays at the pilot site; the system keeps:
--   the code printed in advance on the form (typed by the facilitator; capitals, 2 to 40 characters, unique);
--   what the narrator agreed to (all of it is needed): provide (give the story to the project), cut (the story may be cut
--   into fragments), comment (others may comment on it and add details), share (shown and shared under the chosen
--   licence), voluntary (taking part freely, can withdraw);
--   the licence; anonymity (yes: only the narrator's initials are kept; no: the name, which visitors see as credit);
--   the narrator; the date and place of the interview; its language or dialect.
-- An earlier version called this table "consents" (and stories.consent_id): renamed once, keeping everything in it.
do $$
begin
  if to_regclass('public.consents') is not null and to_regclass('public.testimonies') is null then
    alter table public.consents rename to testimonies;
  end if;
  if exists (select 1 from information_schema.columns where table_schema = 'public' and table_name = 'stories' and column_name = 'consent_id')
     and not exists (select 1 from information_schema.columns where table_schema = 'public' and table_name = 'stories' and column_name = 'testimony_id') then
    alter table public.stories rename column consent_id to testimony_id;
  end if;
end $$;
create table if not exists public.testimonies (
  id                uuid primary key default gen_random_uuid(),
  code              text not null unique,
  user_id           uuid default auth.uid() references auth.users(id) on delete set null,
  statement_version text,
  lang              text,
  accepted          jsonb,
  created_at        timestamptz not null default now()
);
alter table public.testimonies enable row level security;
alter table public.stories add column if not exists testimony_id uuid references public.testimonies(id) on delete restrict;
alter table public.testimonies add column if not exists license         text;
alter table public.testimonies add column if not exists site_id         uuid references public.sites(id) on delete restrict;
alter table public.testimonies alter column site_id set default public.my_site();
alter table public.testimonies add column if not exists status          text not null default 'draft';
alter table public.testimonies alter column status set default 'draft';
alter table public.testimonies add column if not exists withdrawn_at    timestamptz;
alter table public.testimonies add column if not exists title           text;   -- shown to visitors with its stories
alter table public.testimonies add column if not exists narrator        text;
alter table public.testimonies add column if not exists anonymous       boolean;
alter table public.testimonies add column if not exists interview_date  date;
alter table public.testimonies add column if not exists interview_place text;   -- no longer asked: each story has its place
alter table public.testimonies add column if not exists language        text references public.story_languages(code) on update cascade;
alter table public.testimonies add column if not exists updated_at      timestamptz not null default now();
alter table public.testimonies alter column statement_version drop not null;
alter table public.testimonies alter column accepted drop not null;
alter table public.testimonies drop constraint if exists consents_license_check;
alter table public.testimonies drop constraint if exists testimonies_license_check;
alter table public.testimonies add constraint testimonies_license_check check (license is null or license in
  ('CC-BY-4.0', 'CC-BY-SA-4.0', 'CC-BY-NC-4.0', 'CC-BY-NC-SA-4.0', 'CC-BY-NC-ND-4.0', 'PROJECT-ONLY'));
-- (columns of earlier versions)
alter table public.testimonies drop constraint if exists consents_record_check;
drop table if exists public.consent_narrators;
alter table public.testimonies drop column if exists session_date, drop column if exists place, drop column if exists place_lat,
  drop column if exists place_lon, drop column if exists initials, drop column if exists anonymity,
  drop column if exists narrator_review, drop column if exists oral_consent;
-- With anonymity only initials (e.g. "EK", "E.K.", "Ε.Κ."; Latin, Greek or Cyrillic letters, whatever the database locale),
-- otherwise a name.
alter table public.testimonies drop constraint if exists testimonies_fields_check;
alter table public.testimonies add constraint testimonies_fields_check check (
  (title is null or (char_length(title) between 1 and 120 and title = btrim(title)))
  and (narrator is null or char_length(narrator) between 1 and 200)
  and (interview_place is null or char_length(interview_place) between 1 and 200)
  and (narrator is null or anonymous is not true
       or narrator ~ '^[A-Za-zÀ-ÖØ-öø-ɏͰ-ϿЀ-ӿἀ-῾](\.? ?[A-Za-zÀ-ÖØ-öø-ɏͰ-ϿЀ-ӿἀ-῾]){0,3}\.?$'));
drop index if exists public.consents_site_idx;
create index if not exists testimonies_site_idx on public.testimonies(site_id, created_at);
-- The code: kept in capitals without extra spaces. (Rows of the earliest version without a code get one made here.)
create or replace function public.new_consent_code() returns text
language plpgsql volatile set search_path = public as $$
declare a text := 'ABCDEFGHJKMNPQRSTUVWXYZ23456789'; c text;
begin
  loop
    c := 'WM-';
    for i in 1..8 loop
      c := c || substr(a, 1 + floor(random() * length(a))::int, 1);
      if i = 4 then c := c || '-'; end if;
    end loop;
    exit when not exists (select 1 from public.testimonies where code = c);
  end loop;
  return c;
end $$;
create or replace function public.consent_code() returns trigger
language plpgsql set search_path = public as $$
begin
  new.code := upper(btrim(regexp_replace(new.code, '\s+', ' ', 'g')));
  return new;
end $$;
drop trigger if exists consents_code on public.testimonies;
drop trigger if exists testimonies_code on public.testimonies;
create trigger testimonies_code before insert on public.testimonies for each row execute function public.consent_code();
update public.testimonies set code = public.new_consent_code() where code is null;
alter table public.testimonies drop constraint if exists consents_code_check;
alter table public.testimonies drop constraint if exists testimonies_code_check;
alter table public.testimonies add constraint testimonies_code_check check (char_length(code) between 2 and 40 and code = btrim(code) and code !~ '[[:cntrl:]]');
alter table public.testimonies alter column code set not null;

drop policy if exists "read own or all consents"         on public.testimonies;
drop policy if exists "add own consent"                  on public.testimonies;
drop policy if exists "read site consents"               on public.testimonies;
drop policy if exists "facilitators add consents"        on public.testimonies;
drop policy if exists "facilitators withdraw consents"   on public.testimonies;
drop policy if exists "read site testimonies"            on public.testimonies;
drop policy if exists "facilitators add testimonies"     on public.testimonies;
drop policy if exists "facilitators edit testimonies"    on public.testimonies;
drop policy if exists "facilitators delete testimonies"  on public.testimonies;
create policy "read site testimonies" on public.testimonies for select to authenticated
  using (user_id = auth.uid() or public.is_admin() or (site_id is null and public.is_annotator())
         or (site_id is not null and public.sees_site(site_id)));
-- Only a facilitator creates a testimony, for their own site, with every field and every agreement; the code, the
-- agreements, the licence and the anonymity never change (a mistake: delete the empty testimony, or withdraw it).
create policy "facilitators add testimonies" on public.testimonies for insert to authenticated
  with check (public.is_facilitator() and user_id = auth.uid() and site_id = public.my_site() and status = 'draft'
              and title is not null and license is not null and anonymous is not null and narrator is not null
              and interview_date is not null and language is not null
              and accepted @> '{"provide": true, "cut": true, "comment": true, "share": true, "voluntary": true}'::jsonb);
create policy "facilitators edit testimonies" on public.testimonies for update to authenticated
  using (public.is_facilitator() and site_id = public.my_site())
  with check (public.is_facilitator() and site_id = public.my_site());
create policy "facilitators delete testimonies" on public.testimonies for delete to authenticated
  using (public.is_facilitator() and site_id = public.my_site() and status = 'draft');
revoke update on public.testimonies from anon, authenticated;
grant update (status, title, narrator, interview_date, language) on public.testimonies to authenticated;
grant select, insert, delete on public.testimonies to authenticated;

-- Every story carries the licence, the language and the title of its testimony, and the narrator's name when the
-- narrator is not anonymous (visitors see it as credit), copied by the database.
alter table public.stories add column if not exists license  text;
alter table public.stories add column if not exists testimony_title text;
alter table public.stories add column if not exists narrator text;
alter table public.stories alter column license drop not null;   -- (an earlier test version made it required)
alter table public.stories alter column license drop default;
alter table public.stories drop constraint if exists stories_license_check;
alter table public.stories add constraint stories_license_check check (license is null or license in
  ('CC-BY-4.0', 'CC-BY-SA-4.0', 'CC-BY-NC-4.0', 'CC-BY-NC-SA-4.0', 'CC-BY-NC-ND-4.0', 'PROJECT-ONLY'));
create or replace function public.story_from_testimony() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if new.testimony_id is not null then
    select t.license, coalesce(t.language, new.language), case when t.anonymous is false then t.narrator end, t.title
      into new.license, new.language, new.narrator, new.testimony_title
      from public.testimonies t where t.id = new.testimony_id;
  end if;
  return new;
end $$;
drop trigger if exists stories_license_from_consent on public.stories;
drop function if exists public.story_license_from_consent();
drop trigger if exists stories_from_testimony on public.stories;
create trigger stories_from_testimony before insert or update of testimony_id on public.stories
  for each row execute function public.story_from_testimony();

-- To find the testimony and stories behind a paper form (run as the project owner):
--   select t.code, t.narrator, t.status, s.title, s.status
--   from public.testimonies t left join public.stories s on s.testimony_id = t.id
--   where t.code = 'LES-0042';

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

-- Which columns can be updated, and by whom: see "facilitator workflow" below.

drop policy if exists "stories are public"    on public.stories;
drop policy if exists "owners insert stories" on public.stories;
drop policy if exists "owners update stories" on public.stories;
drop policy if exists "owners delete stories" on public.stories;
drop policy if exists "read visible stories"  on public.stories;
drop policy if exists "owners add drafts"     on public.stories;
drop policy if exists "annotators publish"    on public.stories;
drop policy if exists "owners delete own stories" on public.stories;
-- The story policies are created in the "facilitator workflow" section below.

-- ---------- media rows inherit the visibility of their story ----------
drop policy if exists "media is public"      on public.story_media;
drop policy if exists "read visible media"   on public.story_media;
create policy "read visible media" on public.story_media for select
  using (exists (select 1 from public.stories s where s.id = story_media.story_id));
-- Adding, changing and deleting media: see "facilitator workflow" below.
drop policy if exists "owners insert media" on public.story_media;
drop policy if exists "owners delete media" on public.story_media;

-- Annotators who delete a story also remove its uploaded files from storage.
drop policy if exists "annotators delete files" on storage.objects;
create policy "annotators delete files" on storage.objects for delete to authenticated
  using (bucket_id = 'story-media' and public.is_annotator());

drop policy if exists "reorder media" on public.story_media;

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
-- Who / what / where / when for each file: "about" holds who, "period" holds when (free text, e.g. "1965", "summer 1965", "the 1960s");
-- the place is a name (place_name) and, when the contributor can point it, a point on the map (lat, lon).
alter table public.story_media add column if not exists what text;
alter table public.story_media add column if not exists place_name text;

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

-- ---------- heritage objects in ECHOES that a story refers to (e.g. a church or an object documented by OCRA) ----------
create table if not exists public.story_heritage (
  id         uuid primary key default gen_random_uuid(),
  story_id   uuid not null references public.stories(id) on delete cascade,
  uri        text not null check (uri ~ '^https?://' and char_length(uri) <= 500),
  label      text check (label is null or char_length(label) <= 200),
  created_by uuid default auth.uid() references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  unique (story_id, uri)
);
alter table public.story_heritage enable row level security;
drop policy if exists "read visible heritage links" on public.story_heritage;
drop policy if exists "annotators write heritage links" on public.story_heritage;
create policy "read visible heritage links" on public.story_heritage for select using (exists (select 1 from public.stories s where s.id = story_heritage.story_id));
create policy "annotators write heritage links" on public.story_heritage for all to authenticated using (public.is_annotator()) with check (public.is_annotator());
revoke all on public.story_heritage from anon;
grant select (id, story_id, uri, label) on public.story_heritage to anon;
grant select, insert, update, delete on public.story_heritage to authenticated;

-- ---------- (an earlier version had validators who approved stories and walks; annotators now publish them) ----------
alter table public.profiles add column if not exists is_validator boolean not null default false;
create or replace function public.is_validator() returns boolean language sql stable security definer set search_path = public as $$ select exists (select 1 from public.profiles where user_id = auth.uid() and is_validator) $$;
grant execute on function public.is_validator() to anon, authenticated;

-- ======================================================================================================================
-- ---------- facilitator workflow: testimonies, stories, fragments, community validation ----------
-- Testimony status: draft (the facilitator adds its stories and their fragments) -> community_validation (the facilitator
--   goes through it with the community, who correct and complete it) -> validated. Its stories follow it: draft ->
--   community_validation -> ready_for_annotation, and then each story on its own: submitted (the annotator marks it as
--   annotated) -> published (the final export of its testimony, once all its stories are annotated). An annotator can
--   take a story back to annotation at any time.
-- withdrawn: at any status a facilitator of the site can withdraw a story, or its whole testimony; it is then hidden
-- everywhere (admins still see it) and nothing about it can change any more. Every write is in audit_log.

-- One-time renaming of earlier statuses, recorded in wm_migrations so that running this file again never repeats it:
--   v2: pending -> draft, draft (annotation) -> ready_for_annotation;  v3: ready_for_workshop -> community_validation.
create table if not exists public.wm_migrations (name text primary key, applied_at timestamptz not null default now());
alter table public.wm_migrations enable row level security;
revoke all on public.wm_migrations from anon, authenticated;
do $$
begin
  if not exists (select 1 from public.wm_migrations where name = 'story_status_v2') then
    alter table public.stories drop constraint if exists stories_status_check;
    update public.stories set status = case status when 'draft' then 'ready_for_annotation' else 'draft' end
      where status in ('draft', 'pending');
    insert into public.wm_migrations (name) values ('story_status_v2');
  end if;
  if not exists (select 1 from public.wm_migrations where name = 'story_status_v3') then
    alter table public.stories drop constraint if exists stories_status_check;
    update public.stories set status = 'community_validation' where status = 'ready_for_workshop';
    insert into public.wm_migrations (name) values ('story_status_v3');
  end if;
  -- no validators any more: a story an earlier validator returned goes back to annotation
  if not exists (select 1 from public.wm_migrations where name = 'no_validator_v5') then
    update public.stories set status = 'ready_for_annotation' where status = 'returned';
    insert into public.wm_migrations (name) values ('no_validator_v5');
  end if;
end $$;
alter table public.stories drop constraint if exists stories_status_check;
alter table public.stories add constraint stories_status_check check (status in
  ('draft', 'community_validation', 'ready_for_annotation', 'submitted', 'returned', 'published', 'withdrawn'));
alter table public.stories alter column status set default 'draft';
-- Testimonies of an earlier version were "active": their status now follows their stories.
alter table public.testimonies drop constraint if exists consents_status_check;
alter table public.testimonies drop constraint if exists testimonies_status_check;
update public.testimonies t set status = case
    when exists (select 1 from public.stories s where s.testimony_id = t.id and s.status in ('ready_for_annotation', 'submitted', 'returned', 'published')) then 'validated'
    when exists (select 1 from public.stories s where s.testimony_id = t.id and s.status = 'community_validation') then 'community_validation'
    else 'draft' end
  where t.status = 'active';
alter table public.testimonies add constraint testimonies_status_check check (status in ('draft', 'community_validation', 'validated', 'withdrawn'));

-- A GeoJSON polygon (one ring, [lon, lat] positions) for "an area" instead of a point.
create or replace function public.is_polygon(g jsonb) returns boolean
language sql immutable as $$
  select case when jsonb_typeof(g) = 'object' and g->>'type' = 'Polygon' and jsonb_typeof(g->'coordinates') = 'array'
                   and jsonb_array_length(g->'coordinates') = 1 and jsonb_typeof(g->'coordinates'->0) = 'array'
                   and jsonb_array_length(g->'coordinates'->0) between 4 and 200
    then not exists (
      select 1 from jsonb_array_elements(g->'coordinates'->0) p
      where not (case when jsonb_typeof(p) = 'array' and jsonb_array_length(p) = 2
                           and jsonb_typeof(p->0) = 'number' and jsonb_typeof(p->1) = 'number'
                      then (p->>0)::float8 between -180 and 180 and (p->>1)::float8 between -90 and 90
                      else false end))
    else false end;
$$;

-- Story fields: the site, its testimony, title, theme (the interview question), who, where (a place name and a point on the
-- map: lat/lon), when (free text in "period"), where it came from (workshop_field: the facilitator website; ar: the AR
-- app). Language, licence and narrator come from the testimony.
alter table public.stories add column if not exists site_id      uuid references public.sites(id) on delete restrict;
alter table public.stories alter column site_id set default public.my_site();
alter table public.stories add column if not exists theme        text;
alter table public.stories add column if not exists language     text references public.story_languages(code) on update cascade;
alter table public.stories add column if not exists sensitive    boolean;   -- (an earlier version)
alter table public.stories add column if not exists who          text;
alter table public.stories add column if not exists place_name   text;
alter table public.stories add column if not exists period       text;
alter table public.stories add column if not exists source       text not null default 'workshop_field';
alter table public.stories add column if not exists area         jsonb;
alter table public.stories add column if not exists withdrawn_at timestamptz;
alter table public.stories add column if not exists updated_at   timestamptz not null default now();
-- An earlier version chose one of 5 fixed questions per site: its text becomes the story's theme. Its workshop columns go.
do $$
begin
  if exists (select 1 from information_schema.columns where table_schema = 'public' and table_name = 'stories' and column_name = 'question_id') then
    execute 'update public.stories s set theme = q.text from public.site_questions q where q.id = s.question_id and s.theme is null';
  end if;
end $$;
alter table public.stories drop constraint if exists stories_workflow_check;
alter table public.stories drop column if exists question_id, drop column if exists workshop_bucket, drop column if exists narrator_reviewed_at;
drop table if exists public.site_questions;
alter table public.stories add constraint stories_workflow_check check (
  source in ('workshop_field', 'ar')
  and (theme is null or char_length(theme) <= 500)
  and (who is null or char_length(who) <= 600)
  and (place_name is null or char_length(place_name) <= 200)
  and (period is null or char_length(period) <= 200)
  and (narrator is null or char_length(narrator) <= 200)
  and (area is null or public.is_polygon(area))
  and (site_id is null or (theme is not null and language is not null and testimony_id is not null)));
create index if not exists stories_site_idx on public.stories(site_id, status);
drop index if exists public.stories_consent_idx;
create index if not exists stories_testimony_idx on public.stories(testimony_id);
-- During community validation each story is validated on its own (when the community agrees with it); the testimony goes
-- to annotation once all its stories are. Cleared when the testimony goes back to draft.
alter table public.stories add column if not exists community_validated_at timestamptz;
update public.stories s set license = t.license, language = coalesce(t.language, s.language),
    narrator = case when t.anonymous is false then t.narrator end, testimony_title = t.title
  from public.testimonies t
  where t.id = s.testimony_id and (s.license, s.language, s.narrator, s.testimony_title) is distinct from
        (t.license, coalesce(t.language, s.language), case when t.anonymous is false then t.narrator end, t.title);

-- Fragment fields: the file (its kind detected automatically), its order (position), and a caption for a photo or a
-- video. (Title, who, where and when of a fragment belong to an earlier version: they are now the story's.)
-- The original upload is stored as it is: sha256 computed by the browser, etag (MD5) and size taken from the storage
-- server when the fragment is saved. A thumbnail (photo/video) and a waveform (audio) are made for display.
alter table public.story_media add column if not exists who           text[];   -- made free text below
alter table public.story_media add column if not exists area          jsonb;
alter table public.story_media add column if not exists provenance    text;
alter table public.story_media add column if not exists caption       text;
alter table public.story_media add column if not exists sha256        text;
alter table public.story_media add column if not exists etag          text;
alter table public.story_media add column if not exists size_bytes    bigint;
alter table public.story_media add column if not exists mime          text;
alter table public.story_media add column if not exists original_name text;
alter table public.story_media add column if not exists thumb_path    text;
alter table public.story_media add column if not exists waveform      jsonb;
alter table public.story_media add column if not exists duration_s    real;
alter table public.story_media add column if not exists created_at    timestamptz not null default now();
alter table public.story_media add column if not exists updated_at    timestamptz not null default now();
do $$
begin
  if not exists (select 1 from public.wm_migrations where name = 'fragment_fields_v2') then
    update public.story_media set who = array[btrim(about)] where who is null and coalesce(btrim(about), '') <> '';
    update public.story_media set title = what where coalesce(btrim(title), '') = '' and coalesce(btrim(what), '') <> '';
    insert into public.wm_migrations (name) values ('fragment_fields_v2');
  end if;
end $$;
alter table public.story_media drop constraint if exists story_media_fragment_check;
-- An earlier version kept who as a list of names and when as an exact date or an approximate text: both become free text
-- (the names joined with commas; an exact date written as YYYY-MM-DD).
do $$
begin
  if exists (select 1 from information_schema.columns where table_schema = 'public' and table_name = 'story_media' and column_name = 'when_date') then
    execute $q$update public.story_media set period = to_char(when_date, 'YYYY-MM-DD') where when_kind = 'exact' and when_date is not null$q$;
  end if;
  if (select data_type from information_schema.columns where table_schema = 'public' and table_name = 'story_media' and column_name = 'who') = 'ARRAY' then
    alter table public.story_media alter column who type text using nullif(array_to_string(who, ', '), '');
  end if;
end $$;
alter table public.story_media drop column if exists when_kind, drop column if exists when_date;
-- (the workshop's patch status and "stated / inferred" marks of an earlier version are removed)
alter table public.story_media drop column if exists who_src, drop column if exists where_src, drop column if exists when_src,
  drop column if exists patch_status;
alter table public.story_media add constraint story_media_fragment_check check (
  (title is null or char_length(title) <= 200)
  and (who is null or char_length(who) <= 600)
  and (place_name is null or char_length(place_name) <= 200)
  and ((lat is null) = (lon is null)) and (lat is null or (lat between -90 and 90 and lon between -180 and 180))
  and (area is null or public.is_polygon(area))
  and (period is null or char_length(period) <= 200)
  and (sha256 is null or sha256 ~ '^[0-9a-f]{64}$')
  and (original_name is null or char_length(original_name) <= 255)
  and (waveform is null or jsonb_typeof(waveform) = 'array')
  and (caption is null or (char_length(caption) <= 500 and kind in ('image', 'video')))) not valid;
-- Once: a photo's or video's title becomes its caption, and the first who / where / when of a story's fragments become the
-- story's.
do $$
begin
  if not exists (select 1 from public.wm_migrations where name = 'testimony_v4') then
    update public.story_media set caption = btrim(title)
      where caption is null and kind in ('image', 'video') and coalesce(btrim(title), '') <> '' and char_length(btrim(title)) <= 500;
    update public.stories s set
      who        = coalesce(s.who,        (select m.who        from public.story_media m where m.story_id = s.id and coalesce(btrim(m.who), '') <> ''        order by m.position limit 1)),
      place_name = coalesce(s.place_name, (select m.place_name from public.story_media m where m.story_id = s.id and coalesce(btrim(m.place_name), '') <> '' order by m.position limit 1)),
      period     = coalesce(s.period,     (select m.period     from public.story_media m where m.story_id = s.id and coalesce(btrim(m.period), '') <> ''     order by m.position limit 1));
    insert into public.wm_migrations (name) values ('testimony_v4');
  end if;
end $$;
drop function if exists public.texts_ok(text[], integer);   -- (used by the list of names of an earlier version)

-- Internal comment on a fragment (e.g. what the community said): seen by the site's facilitators and by annotators,
-- never public.
create table if not exists public.fragment_notes (
  media_id   uuid primary key references public.story_media(id) on delete cascade,
  body       text not null check (char_length(body) <= 8000),
  updated_by uuid default auth.uid() references auth.users(id) on delete set null,
  updated_at timestamptz not null default now()
);

-- ---------- helpers for the rules ----------
-- Can the signed-in user change this story and its fragments now? A facilitator of its site, while the story is a draft
-- (with the community nothing is corrected: what the community says is written down as comments).
create or replace function public.can_edit_story(sid uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select public.is_facilitator()
     and exists (select 1 from public.stories s where s.id = sid and s.site_id = public.my_site() and s.status = 'draft');
$$;
-- What still stops a testimony from moving on: 'title' (it has none: older testimonies), 'stories' (it has none), and for
-- any of its stories 'theme' (no theme) or 'audio' (no audio fragment).
create or replace function public.story_problems(sid uuid) returns text[]
language sql stable security definer set search_path = public as $$
  select array_remove(array[
    case when not exists (select 1 from public.stories s where s.id = sid and coalesce(btrim(s.theme), '') <> '') then 'theme' end,
    case when not exists (select 1 from public.story_media m where m.story_id = sid and m.kind = 'audio') then 'audio' end
  ], null);
$$;
create or replace function public.testimony_problems(tid uuid) returns text[]
language sql stable security definer set search_path = public as $$
  select case when exists (select 1 from public.testimonies t where t.id = tid and t.title is not null) then '{}'::text[] else array['title'] end
    || case when not exists (select 1 from public.stories s where s.testimony_id = tid and s.status <> 'withdrawn') then array['stories']
    else (select coalesce(array_agg(distinct p order by p), '{}') from public.stories s, unnest(public.story_problems(s.id)) p
          where s.testimony_id = tid and s.status <> 'withdrawn') end;
$$;
revoke execute on function public.can_edit_story(uuid), public.story_problems(uuid), public.testimony_problems(uuid) from public, anon;
grant execute on function public.can_edit_story(uuid), public.story_problems(uuid), public.testimony_problems(uuid) to authenticated;

-- (an earlier version had workshop sessions; community validation replaces them)
drop function if exists public.workshop_set_field(uuid, uuid, text, jsonb);
drop function if exists public.workshop_set_patch(uuid, uuid, text);
drop function if exists public.workshop_add_note(uuid, uuid, text);
drop function if exists public.workshop_narrator(uuid, uuid, boolean, boolean);
drop function if exists public.ws_open(uuid, uuid);
drop table if exists public.workshop_changes, public.workshop_stories, public.workshops;
drop function if exists public.guard_workshop();
drop function if exists public.in_running_workshop(uuid);

-- ---------- stories: who may read, add, change, delete ----------
drop policy if exists "read visible stories"          on public.stories;
drop policy if exists "facilitators add stories"      on public.stories;
drop policy if exists "facilitators edit stories"     on public.stories;
drop policy if exists "annotators publish"            on public.stories;
drop policy if exists "owners finish review"          on public.stories;
drop policy if exists "delete stories"                on public.stories;
-- Published: everyone. The site's facilitators: every status (withdrawn too, so that they can withdraw). Withdrawn:
-- otherwise admins only. Annotators: once the community has validated it. Stories from before sites existed: their
-- uploader, and annotators once in annotation.
create policy "read visible stories" on public.stories for select
  using (status = 'published' or public.is_admin()
    or (site_id is not null and public.is_facilitator() and site_id = public.my_site())
    or (status <> 'withdrawn' and (
         (site_id is null and (user_id = auth.uid() or (public.is_annotator() and status in ('ready_for_annotation', 'submitted', 'returned'))))
      or (site_id is not null and public.is_annotator() and status in ('ready_for_annotation', 'submitted', 'returned') and public.sees_site(site_id)))));
-- No story outside a draft testimony of the same site.
create policy "facilitators add stories" on public.stories for insert to authenticated
  with check (public.is_facilitator() and user_id = auth.uid() and site_id = public.my_site() and status = 'draft'
    and exists (select 1 from public.testimonies t where t.id = stories.testimony_id and t.site_id = stories.site_id
                and t.status = 'draft'));
create policy "facilitators edit stories" on public.stories for update to authenticated
  using (public.is_facilitator() and site_id = public.my_site())
  with check (public.is_facilitator() and site_id = public.my_site());
create policy "annotators publish" on public.stories for update to authenticated
  using (public.is_annotator()) with check (public.is_annotator());
-- Deleting (instead of withdrawing) is for mistakes: a facilitator's draft, or an annotator's story already in annotation.
create policy "delete stories" on public.stories for delete to authenticated
  using (public.is_admin()
    or (public.is_facilitator() and site_id = public.my_site() and status = 'draft')
    or (public.is_annotator() and status in ('ready_for_annotation', 'submitted', 'returned', 'published')
        and (site_id is null or public.sees_site(site_id))));
revoke update on public.stories from anon, authenticated;
grant update (status, title, lat, lon, area, radius, theme, who, place_name, period, community_validated_at) on public.stories to authenticated;

-- The rules the policies cannot express: which status changes are allowed and who may make them, and that a story's
-- content changes only while it is a draft. The SQL editor (no signed-in user) is not limited.
create or replace function public.guard_story() returns trigger
language plpgsql security definer set search_path = public as $$
declare
  fac boolean;
  probs text[];
begin
  new.updated_at := now();
  if tg_op = 'INSERT' then
    if auth.uid() is not null then
      new.withdrawn_at := null;
      new.status := 'draft';
    end if;
    return new;
  end if;
  if auth.uid() is null then return new; end if;
  if old.status = 'withdrawn' then raise exception 'A withdrawn story cannot be changed' using errcode = '42501'; end if;
  fac := public.is_facilitator() and old.site_id is not distinct from public.my_site();
  if (new.title, new.lat, new.lon, new.area, new.radius, new.theme, new.who, new.place_name, new.period, new.testimony_id)
     is distinct from (old.title, old.lat, old.lon, old.area, old.radius, old.theme, old.who, old.place_name, old.period, old.testimony_id) then
    if not fac or old.status <> 'draft' then
      raise exception 'Only the site''s facilitators can change a story, while its testimony is a draft' using errcode = '42501';
    end if;
  end if;
  if new.community_validated_at is distinct from old.community_validated_at and pg_trigger_depth() < 2 then
    if not fac or old.status <> 'community_validation' or new.status <> old.status then
      raise exception 'Only the site''s facilitators can mark a story as validated by the community, while it is with the community' using errcode = '42501';
    end if;
    if new.community_validated_at is not null then new.community_validated_at := now(); end if;
  end if;
  if new.status is distinct from old.status then
    if new.status = 'withdrawn' then
      if not (fac or public.is_admin()) then raise exception 'Only the site''s facilitators can withdraw a story' using errcode = '42501'; end if;
      new.withdrawn_at := now();
    elsif (old.status = 'draft' and new.status = 'community_validation')
       or (old.status = 'community_validation' and new.status in ('ready_for_annotation', 'draft')) then
      -- only together with its testimony (the testimony's own rule calls this)
      if pg_trigger_depth() < 2 then
        raise exception 'A story moves on together with its testimony' using errcode = '42501';
      end if;
    elsif new.status = 'submitted' and old.status in ('ready_for_annotation', 'returned') then
      if not public.is_annotator() then raise exception 'Only an annotator can submit a story' using errcode = '42501'; end if;
    elsif new.status = 'ready_for_annotation' and old.status in ('submitted', 'published') then
      if not public.is_annotator() then raise exception 'Only an annotator can take a story back' using errcode = '42501'; end if;
    elsif old.status = 'submitted' and new.status = 'published' then
      -- the final export of its testimony
      if not public.is_annotator() then raise exception 'Only an annotator can publish a story (final export)' using errcode = '42501'; end if;
    else
      raise exception 'This status change is not allowed (% -> %)', old.status, new.status using errcode = '42501';
    end if;
  end if;
  return new;
end $$;
drop trigger if exists stories_status_guard on public.stories;
drop trigger if exists stories_review_edit  on public.stories;
drop trigger if exists stories_guard        on public.stories;
create trigger stories_guard before insert or update on public.stories for each row execute function public.guard_story();
drop function if exists public.check_story_status();

-- A testimony and its stories move on together. Its details (title, narrator, date, language) change only while it is a draft
-- (with the community nothing is corrected: what the community says is written down as comments on the stories; to change
-- something the facilitator takes it back to draft); withdrawing it withdraws all its stories; withdrawn stays withdrawn.
create or replace function public.guard_testimony() returns trigger
language plpgsql security definer set search_path = public as $$
declare
  fac boolean;
  probs text[];
begin
  new.updated_at := now();
  if tg_op = 'INSERT' then
    if auth.uid() is not null then new.status := 'draft'; new.withdrawn_at := null; end if;
    return new;
  end if;
  if auth.uid() is null then return new; end if;
  if old.status = 'withdrawn' then raise exception 'A withdrawn testimony cannot be changed' using errcode = '42501'; end if;
  fac := public.is_facilitator() and old.site_id is not distinct from public.my_site();
  if (new.title, new.narrator, new.interview_date, new.interview_place, new.language)
     is distinct from (old.title, old.narrator, old.interview_date, old.interview_place, old.language) then
    if not fac or old.status <> 'draft' then
      raise exception 'Only the site''s facilitators can change a testimony, while it is a draft' using errcode = '42501';
    end if;
    if new.title is null or new.narrator is null or new.interview_date is null or new.language is null then
      raise exception 'The title, the narrator, the date of the interview and the language are needed' using errcode = '23514';
    end if;
  end if;
  if new.status is distinct from old.status then
    if new.status = 'withdrawn' then
      if not (fac or public.is_admin()) then raise exception 'Only the site''s facilitators can withdraw a testimony' using errcode = '42501'; end if;
      new.withdrawn_at := now();
      update public.stories set status = 'withdrawn' where testimony_id = new.id and status <> 'withdrawn';
    elsif (old.status = 'draft' and new.status = 'community_validation') or (old.status = 'community_validation' and new.status = 'validated') then
      if not fac then raise exception 'Only the site''s facilitators can move a testimony on' using errcode = '42501'; end if;
      probs := public.testimony_problems(old.id);
      if new.status = 'validated' and exists (select 1 from public.stories s where s.testimony_id = old.id
           and s.status = 'community_validation' and s.community_validated_at is null) then
        probs := probs || array['community'];       -- every story validated by the community first
      end if;
      if cardinality(probs) > 0 then
        raise exception 'Not ready yet: %', array_to_string(probs, ', ') using errcode = '23514';
      end if;
      update public.stories set status = case new.status when 'validated' then 'ready_for_annotation' else 'community_validation' end,
          community_validated_at = case new.status when 'validated' then community_validated_at end
        where testimony_id = new.id and status = case new.status when 'validated' then 'community_validation' else 'draft' end;
    elsif old.status = 'community_validation' and new.status = 'draft' then
      if not fac then raise exception 'Only the site''s facilitators can take a testimony back' using errcode = '42501'; end if;
      update public.stories set status = 'draft', community_validated_at = null where testimony_id = new.id and status = 'community_validation';
    else
      raise exception 'This status change is not allowed (% -> %)', old.status, new.status using errcode = '42501';
    end if;
  end if;
  if new.status <> 'withdrawn' and (new.language, new.narrator, new.title) is distinct from (old.language, old.narrator, old.title) then
    update public.stories set language = new.language, narrator = case when new.anonymous is false then new.narrator end,
        testimony_title = new.title
      where testimony_id = new.id and status <> 'withdrawn';
  end if;
  return new;
end $$;
drop trigger if exists consents_guard on public.testimonies;
drop trigger if exists testimonies_guard on public.testimonies;
create trigger testimonies_guard before insert or update on public.testimonies for each row execute function public.guard_testimony();
drop function if exists public.guard_consent();

-- ---------- fragments: who may add, change, delete ----------
drop policy if exists "facilitators add fragments"    on public.story_media;
drop policy if exists "facilitators edit fragments"   on public.story_media;
drop policy if exists "annotators reorder fragments"  on public.story_media;
drop policy if exists "facilitators delete fragments" on public.story_media;
create policy "facilitators add fragments" on public.story_media for insert to authenticated
  with check (public.can_edit_story(story_id));
create policy "facilitators edit fragments" on public.story_media for update to authenticated
  using (public.can_edit_story(story_id)) with check (public.can_edit_story(story_id));
create policy "annotators reorder fragments" on public.story_media for update to authenticated
  using (public.is_annotator()) with check (public.is_annotator());
create policy "facilitators delete fragments" on public.story_media for delete to authenticated
  using (public.can_edit_story(story_id));
revoke update on public.story_media from anon, authenticated;
grant update (position, caption) on public.story_media to authenticated;

create or replace function public.guard_fragment() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if tg_op = 'DELETE' then
    if auth.uid() is null or not exists (select 1 from public.stories s where s.id = old.story_id) then return old; end if;  -- story deleted
    if not public.can_edit_story(old.story_id) then
      raise exception 'Fragments can be removed only by the site''s facilitators, while the story is a draft' using errcode = '42501';
    end if;
    return old;
  end if;
  new.updated_at := now();
  if tg_op = 'INSERT' then
    new.created_at := now();
    new.provenance := case when new.kind in ('image', 'video') then 'own_or_family_item' end;
    -- the storage server's own fingerprint and size of the uploaded original
    select btrim(o.metadata->>'eTag', '"'), (o.metadata->>'size')::bigint into new.etag, new.size_bytes
      from storage.objects o where o.bucket_id = 'story-media' and o.name = new.path;
    if auth.uid() is not null and new.etag is null and new.size_bytes is null then
      raise exception 'Upload the file before adding the fragment' using errcode = '23514';
    end if;
    return new;
  end if;
  if auth.uid() is null then return new; end if;
  if (new.caption, new.title, new.who, new.place_name, new.lat, new.lon, new.area, new.period, new.recorded_at, new.about, new.what)
     is not distinct from (old.caption, old.title, old.who, old.place_name, old.lat, old.lon, old.area, old.period, old.recorded_at, old.about, old.what) then
    -- only the position: the site's facilitators while editable, annotators once the story is in annotation
    if public.can_edit_story(old.story_id) or (public.is_annotator() and exists (select 1 from public.stories s where s.id = old.story_id
         and s.status in ('ready_for_annotation', 'submitted', 'returned', 'published'))) then
      return new;
    end if;
    raise exception 'The order can be changed only by the site''s facilitators or, in annotation, by annotators' using errcode = '42501';
  end if;
  if not public.can_edit_story(old.story_id) then
    raise exception 'Only the site''s facilitators can change a fragment, while the story is a draft' using errcode = '42501';
  end if;
  return new;
end $$;
drop trigger if exists story_media_review_edit on public.story_media;
drop trigger if exists story_media_guard       on public.story_media;
create trigger story_media_guard before insert or update or delete on public.story_media for each row execute function public.guard_fragment();
drop function if exists public.check_review_edit();

-- A facilitator who deletes a draft story or a fragment also removes its files: only files in their own folder that no
-- fragment uses any more.
create or replace function public.file_in_use(p text) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.story_media m where m.path = p or m.thumb_path = p);
$$;
revoke execute on function public.file_in_use(text) from public, anon;
grant execute on function public.file_in_use(text) to authenticated;
drop policy if exists "owners delete files" on storage.objects;   -- (earlier: any file of one's own, even in use)
drop policy if exists "facilitators delete unused files" on storage.objects;
create policy "facilitators delete unused files" on storage.objects for delete to authenticated
  using (bucket_id = 'story-media' and public.is_facilitator() and (storage.foldername(name))[1] = auth.uid()::text
         and not public.file_in_use(name));

-- Only staff can upload files, into their own folder.
drop policy if exists "owners upload files" on storage.objects;
create policy "owners upload files" on storage.objects for insert to authenticated
  with check (bucket_id = 'story-media' and (storage.foldername(name))[1] = auth.uid()::text
              and (public.is_facilitator() or public.is_annotator()));

-- ---------- fragment notes ----------
alter table public.fragment_notes enable row level security;
drop policy if exists "staff read fragment notes"         on public.fragment_notes;
drop policy if exists "facilitators write fragment notes" on public.fragment_notes;
create policy "staff read fragment notes" on public.fragment_notes for select to authenticated
  using ((public.is_facilitator() or public.is_annotator() or public.is_admin())
         and exists (select 1 from public.story_media m where m.id = fragment_notes.media_id));
create policy "facilitators write fragment notes" on public.fragment_notes for all to authenticated
  using (public.can_edit_story((select m.story_id from public.story_media m where m.id = fragment_notes.media_id)))
  with check (public.can_edit_story((select m.story_id from public.story_media m where m.id = fragment_notes.media_id)));
revoke all on public.fragment_notes from anon;
grant select, insert, update, delete on public.fragment_notes to authenticated;

-- ---------- audit log: every write (user, time, entity, action, previous value, what changed) ----------
create table if not exists public.audit_log (
  id          bigserial primary key,
  at          timestamptz not null default now(),
  user_id     uuid,
  entity      text not null,
  entity_id   text,
  action      text not null check (action in ('insert', 'update', 'delete')),
  previous    jsonb,
  changes     jsonb
);
alter table public.audit_log drop column if exists workshop_id;   -- an earlier version's workshops
create index if not exists audit_log_entity_idx on public.audit_log(entity, entity_id, at);
create index if not exists audit_log_time_idx on public.audit_log(at);
alter table public.audit_log enable row level security;
drop policy if exists "admins read audit log" on public.audit_log;
create policy "admins read audit log" on public.audit_log for select to authenticated using (public.is_admin());
revoke all on public.audit_log from anon, authenticated;
grant select on public.audit_log to authenticated;
create or replace function public.audit_row() returns trigger
language plpgsql security definer set search_path = public as $$
declare r jsonb; prev jsonb; chg jsonb;
begin
  r := case when tg_op = 'DELETE' then to_jsonb(old) else to_jsonb(new) end;
  if tg_op = 'INSERT' then chg := r;
  elsif tg_op = 'DELETE' then prev := r;
  else
    prev := to_jsonb(old);
    select jsonb_object_agg(n.key, n.value) into chg from jsonb_each(r) n where n.value is distinct from prev->n.key;
    if chg is null then return new; end if;
  end if;
  insert into public.audit_log (user_id, entity, entity_id, action, previous, changes)
  values (auth.uid(), tg_table_name, coalesce(r->>'id', r->>'media_id', r->>'consent_id', r->>'code', r->>'user_id'), lower(tg_op), prev, chg);
  return case when tg_op = 'DELETE' then old else new end;
end $$;
do $$
declare t text;
begin
  drop trigger if exists consents_audit on public.testimonies;
  foreach t in array array['sites', 'story_languages', 'profiles', 'testimonies', 'stories', 'story_media', 'fragment_notes'] loop
    execute format('drop trigger if exists %I on public.%I', t || '_audit', t);
    execute format('create trigger %I after insert or update or delete on public.%I for each row execute function public.audit_row()', t || '_audit', t);
  end loop;
end $$;

-- ---------- admin page: accounts, their site and role ----------
create or replace function public.admin_users() returns table (user_id uuid, email text, name text, role text, site_id uuid,
  is_admin boolean, is_validator boolean, created_at timestamptz, last_sign_in_at timestamptz)
language plpgsql stable security definer set search_path = public as $$
begin
  if not public.is_admin() then raise exception 'Admins only' using errcode = '42501'; end if;
  return query
    select u.id, u.email::text, coalesce(u.raw_user_meta_data->>'display_name', split_part(u.email::text, '@', 1)),
           p.role, p.site_id, coalesce(p.is_admin, false), coalesce(p.is_validator, false), u.created_at, u.last_sign_in_at
    from auth.users u left join public.profiles p on p.user_id = u.id
    order by u.email;
end $$;
create or replace function public.admin_set_user(p_user uuid, p_role text, p_site uuid, p_validator boolean, p_admin boolean) returns void
language plpgsql security definer set search_path = public as $$
begin
  if not public.is_admin() then raise exception 'Admins only' using errcode = '42501'; end if;
  if p_role not in ('facilitator', 'annotator') then raise exception 'Unknown role' using errcode = '22023'; end if;
  if p_user = auth.uid() and not p_admin then raise exception 'You cannot remove your own admin rights' using errcode = '42501'; end if;
  insert into public.profiles (user_id, role, site_id, is_validator, is_admin)
  values (p_user, p_role, p_site, coalesce(p_validator, false), coalesce(p_admin, false))
  on conflict (user_id) do update set role = excluded.role, site_id = excluded.site_id,
    is_validator = excluded.is_validator, is_admin = excluded.is_admin;
end $$;
revoke execute on function public.admin_users(), public.admin_set_user(uuid, text, uuid, boolean, boolean) from public, anon;
grant execute on function public.admin_users(), public.admin_set_user(uuid, text, uuid, boolean, boolean) to authenticated;

-- Walks: an annotator publishes a board as a walk; it is then shown in the app (is_walk). (An earlier version had
-- validators approve them first: walks still waiting for one go back to "not a walk".)
alter table public.story_boards add column if not exists walk_status text not null default 'none';
alter table public.story_boards drop constraint if exists story_boards_walk_status_check;
alter table public.story_boards add constraint story_boards_walk_status_check check (walk_status in ('none', 'submitted', 'returned', 'approved'));
update public.story_boards set walk_status = 'approved' where is_walk and walk_status = 'none';
update public.story_boards set walk_status = 'none' where walk_status in ('submitted', 'returned');
create or replace function public.check_walk_status() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if auth.uid() is not null and not public.is_annotator() and (
       (new.is_walk and not coalesce(old.is_walk, false))
       or (new.walk_status is distinct from old.walk_status and new.walk_status in ('approved', 'returned'))) then
    raise exception 'Only an annotator can publish a walk' using errcode = '42501';
  end if;
  return new;
end $$;
drop trigger if exists story_boards_walk_guard on public.story_boards;
create trigger story_boards_walk_guard before update on public.story_boards for each row execute function public.check_walk_status();
grant select (walk_status) on public.story_boards to anon;

-- History of status changes (annotated, reopened, final export; earlier validators' decisions)
create table if not exists public.reviews (
  id         uuid primary key default gen_random_uuid(),
  story_id   uuid references public.stories(id) on delete cascade,
  board_id   uuid references public.story_boards(id) on delete cascade,
  action     text not null check (action in ('submitted', 'withdrawn', 'returned', 'approved', 'unpublished')),
  message    text check (message is null or char_length(message) <= 4000),
  user_id    uuid default auth.uid() references auth.users(id) on delete set null,
  user_name  text,
  created_at timestamptz not null default now(),
  check ((story_id is null) <> (board_id is null))
);
create index if not exists reviews_story_idx on public.reviews(story_id, created_at);
create index if not exists reviews_board_idx on public.reviews(board_id, created_at);
alter table public.reviews enable row level security;
drop policy if exists "staff read reviews" on public.reviews;
drop policy if exists "staff add reviews"  on public.reviews;
create policy "staff read reviews" on public.reviews for select to authenticated using (public.is_annotator() or public.is_admin());
create policy "staff add reviews" on public.reviews for insert to authenticated
  with check (public.is_annotator() and user_id = auth.uid() and action in ('submitted', 'withdrawn', 'unpublished', 'approved'));
revoke all on public.reviews from anon;
grant select, insert on public.reviews to authenticated;

-- ---------- comments on a story's fragments: what the community said during community validation ----------
-- Written by the site's facilitators while the testimony is a draft or with the community, read by them and by the
-- annotators (and admins), never public. A facilitator can delete their own comment until the community has validated it.
-- (media_id: the fragment it is about; new comments always have one. Null: an earlier comment on the whole story.)
create table if not exists public.facilitator_comments (
  id         uuid primary key default gen_random_uuid(),
  story_id   uuid not null references public.stories(id) on delete cascade,
  media_id   uuid references public.story_media(id) on delete cascade,   -- null: about the whole story
  body       text not null check (char_length(body) between 1 and 4000),
  user_id    uuid default auth.uid() references auth.users(id) on delete set null,
  user_name  text check (user_name is null or char_length(user_name) <= 120),
  created_at timestamptz not null default now()
);
create index if not exists facilitator_comments_story_idx on public.facilitator_comments(story_id);
alter table public.facilitator_comments enable row level security;
drop policy if exists "read story comments" on public.facilitator_comments;
drop policy if exists "owners comment while reviewing" on public.facilitator_comments;
drop policy if exists "owners delete comments while reviewing" on public.facilitator_comments;
drop policy if exists "facilitators add story comments" on public.facilitator_comments;
drop policy if exists "facilitators delete own story comments" on public.facilitator_comments;
create policy "read story comments" on public.facilitator_comments for select to authenticated
  using (public.is_annotator() or public.is_admin()
         or exists (select 1 from public.stories s where s.id = facilitator_comments.story_id
                    and (s.user_id = auth.uid() or (public.is_facilitator() and s.site_id = public.my_site()))));
create policy "facilitators add story comments" on public.facilitator_comments for insert to authenticated
  with check (public.is_facilitator() and user_id = auth.uid()
              and exists (select 1 from public.stories s where s.id = facilitator_comments.story_id and s.site_id = public.my_site()
                          and s.status in ('draft', 'community_validation'))
              and exists (select 1 from public.story_media m where m.id = facilitator_comments.media_id
                          and m.story_id = facilitator_comments.story_id));
create policy "facilitators delete own story comments" on public.facilitator_comments for delete to authenticated
  using (public.is_facilitator() and user_id = auth.uid()
         and exists (select 1 from public.stories s where s.id = facilitator_comments.story_id and s.site_id = public.my_site()
                     and s.status in ('draft', 'community_validation')));
revoke all on public.facilitator_comments from anon, authenticated;
grant select, insert, delete on public.facilitator_comments to authenticated;
drop trigger if exists facilitator_comments_audit on public.facilitator_comments;
create trigger facilitator_comments_audit after insert or update or delete on public.facilitator_comments
  for each row execute function public.audit_row();

-- Make the API pick up new columns immediately (avoids "could not find the column ... in the schema cache")
notify pgrst, 'reload schema';
