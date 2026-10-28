-- Roles, sites, the facilitator workflow, publishing and image-to-time links. Run in the Supabase SQL editor AFTER
-- schema.sql and annotations.sql. Safe to run again.
--
--   facilitator (default for every new account): belongs to one pilot site; records consents, creates stories and
--                fragments, prepares and runs the Digital Quilt workshops of that site. An account without a site
--                can do nothing yet.
--   annotator:   transcribes, annotates, links images to moments of audio/video and submits stories for validation
--                (stories that have left the workshop). Annotators without a site see every site.
--   validator:   an annotator who also publishes or returns stories.
--   admin:       manages sites, their questions, languages and accounts (admin page); sees everything.
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
-- Every account belongs to one pilot site (set on the admin page). A facilitator sees and acts only on the consents,
-- stories and workshops of that site. Annotators and admins without a site see every site.
create table if not exists public.sites (
  id         uuid primary key default gen_random_uuid(),
  name       text not null unique check (char_length(name) between 1 and 120),
  created_at timestamptz not null default now()
);
-- Each site's 5 fixed interview questions (one answer per story); a story records the question it answers.
create table if not exists public.site_questions (
  id       uuid primary key default gen_random_uuid(),
  site_id  uuid not null references public.sites(id) on delete cascade,
  position smallint not null check (position between 1 and 5),
  text     text not null check (char_length(text) between 1 and 500),
  unique (site_id, position)
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
alter table public.site_questions  enable row level security;
alter table public.story_languages enable row level security;
drop policy if exists "staff read sites"       on public.sites;
drop policy if exists "admins write sites"     on public.sites;
drop policy if exists "staff read questions"   on public.site_questions;
drop policy if exists "admins write questions" on public.site_questions;
drop policy if exists "staff read languages"   on public.story_languages;
drop policy if exists "admins write languages" on public.story_languages;
create policy "staff read sites"       on public.sites           for select to authenticated using (true);
create policy "admins write sites"     on public.sites           for all    to authenticated using (public.is_admin()) with check (public.is_admin());
create policy "staff read questions"   on public.site_questions  for select to authenticated using (true);
create policy "admins write questions" on public.site_questions  for all    to authenticated using (public.is_admin()) with check (public.is_admin());
create policy "staff read languages"   on public.story_languages for select to authenticated using (true);
create policy "admins write languages" on public.story_languages for all    to authenticated using (public.is_admin()) with check (public.is_admin());
revoke all on public.sites, public.site_questions, public.story_languages from anon;
grant select, insert, update, delete on public.sites, public.site_questions, public.story_languages to authenticated;

-- ---------- consent records ----------
-- The narrator signs a printed consent form that stays at the pilot site and is never uploaded. The facilitator records
-- the consent here: session date, place, narrator initials, licence, anonymity, whether the narrator reviews the story
-- before publication, and whether consent was given orally instead of a signature. The id is generated by the system;
-- nobody types or sees it. (Older records from the first version carry a WM-XXXX-XXXX code instead.)
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
-- Licence chosen with the narrator when the consent is given (consent page). Older consents have none (null).
alter table public.consents add column if not exists license text;
alter table public.consents drop constraint if exists consents_license_check;
alter table public.consents add constraint consents_license_check check (license is null or license in
  ('CC-BY-4.0', 'CC-BY-SA-4.0', 'CC-BY-NC-4.0', 'CC-BY-NC-SA-4.0', 'CC-BY-NC-ND-4.0', 'PROJECT-ONLY'));
alter table public.consents alter column code drop not null;
alter table public.consents alter column statement_version drop not null;
alter table public.consents alter column accepted drop not null;
alter table public.consents add column if not exists site_id         uuid references public.sites(id) on delete restrict;
alter table public.consents alter column site_id set default public.my_site();
alter table public.consents add column if not exists session_date    date;
alter table public.consents add column if not exists place           text;
alter table public.consents add column if not exists place_lat       double precision;
alter table public.consents add column if not exists place_lon       double precision;
alter table public.consents add column if not exists initials        text;
alter table public.consents add column if not exists anonymity       text;
alter table public.consents add column if not exists narrator_review boolean;
alter table public.consents add column if not exists oral_consent    boolean not null default false;
alter table public.consents add column if not exists status          text not null default 'active';
alter table public.consents add column if not exists withdrawn_at    timestamptz;
alter table public.consents drop constraint if exists consents_record_check;
alter table public.consents add constraint consents_record_check check (
  (place is null or char_length(place) between 1 and 200)
  and (initials is null or (char_length(initials) between 2 and 4 and initials !~ '[[:space:][:digit:]]'))
  and (anonymity is null or anonymity in ('full_name', 'first_name', 'anonymous'))
  and status in ('active', 'withdrawn')
  and ((place_lat is null) = (place_lon is null))
  and (place_lat is null or (place_lat between -90 and 90 and place_lon between -180 and 180))
  and (code is not null or (site_id is not null and session_date is not null and place is not null and initials is not null
                            and anonymity is not null and narrator_review is not null and license is not null)));
create index if not exists consents_site_idx on public.consents(site_id, session_date);

drop policy if exists "read site consents"             on public.consents;
drop policy if exists "facilitators add consents"      on public.consents;
drop policy if exists "facilitators withdraw consents" on public.consents;
create policy "read site consents" on public.consents for select to authenticated
  using (user_id = auth.uid() or public.is_admin() or (site_id is null and public.is_annotator())
         or (site_id is not null and public.sees_site(site_id)));
-- Only a facilitator creates consent records, for their own site; a record is permanent (only withdrawal, below).
create policy "facilitators add consents" on public.consents for insert to authenticated
  with check (public.is_facilitator() and user_id = auth.uid() and site_id = public.my_site()
              and status = 'active' and license is not null and code is null);
create policy "facilitators withdraw consents" on public.consents for update to authenticated
  using (public.is_facilitator() and site_id = public.my_site())
  with check (public.is_facilitator() and site_id = public.my_site() and status = 'withdrawn');
revoke update on public.consents from anon, authenticated;
grant update (status) on public.consents to authenticated;

-- The narrator's name (when not anonymous) is kept apart, readable only by the site's facilitators and admins.
create table if not exists public.consent_narrators (
  consent_id    uuid primary key references public.consents(id) on delete cascade,
  narrator_name text not null check (char_length(narrator_name) between 1 and 200)
);
alter table public.consent_narrators enable row level security;
drop policy if exists "facilitators read narrator names" on public.consent_narrators;
drop policy if exists "facilitators add narrator names"  on public.consent_narrators;
create policy "facilitators read narrator names" on public.consent_narrators for select to authenticated
  using (public.is_admin() or exists (select 1 from public.consents c where c.id = consent_narrators.consent_id
                                      and public.is_facilitator() and c.site_id = public.my_site()));
create policy "facilitators add narrator names" on public.consent_narrators for insert to authenticated
  with check (exists (select 1 from public.consents c where c.id = consent_narrators.consent_id and c.user_id = auth.uid()
                      and public.is_facilitator() and c.site_id = public.my_site() and c.anonymity <> 'anonymous'));
revoke all on public.consent_narrators from anon;
grant select, insert on public.consent_narrators to authenticated;

alter table public.stories add column if not exists consent_id uuid references public.consents(id) on delete restrict;

-- Every story carries the licence of its consent, copied by the database (not chosen again at upload).
alter table public.stories add column if not exists license text;
alter table public.stories alter column license drop not null;   -- (an earlier test version made it required)
alter table public.stories alter column license drop default;
alter table public.stories drop constraint if exists stories_license_check;
alter table public.stories add constraint stories_license_check check (license is null or license in
  ('CC-BY-4.0', 'CC-BY-SA-4.0', 'CC-BY-NC-4.0', 'CC-BY-NC-SA-4.0', 'CC-BY-NC-ND-4.0', 'PROJECT-ONLY'));
create or replace function public.story_license_from_consent() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if new.consent_id is not null then
    select c.license into new.license from public.consents c where c.id = new.consent_id;
  end if;
  return new;
end $$;
drop trigger if exists stories_license_from_consent on public.stories;
create trigger stories_license_from_consent before insert or update of consent_id on public.stories
  for each row execute function public.story_license_from_consent();
update public.stories s set license = c.license from public.consents c
  where c.id = s.consent_id and s.license is distinct from c.license;

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

-- ---------- validation: a validator approves stories and walks before they are published ----------
-- Make someone a validator (they also need the annotator role, to see and fix drafts):
--   update public.profiles set role = 'annotator', is_validator = true
--   where user_id = (select id from auth.users where email = 'validator@example.com');
alter table public.profiles add column if not exists is_validator boolean not null default false;
create or replace function public.is_validator() returns boolean language sql stable security definer set search_path = public as $$ select exists (select 1 from public.profiles where user_id = auth.uid() and is_validator) $$;
grant execute on function public.is_validator() to anon, authenticated;

-- ======================================================================================================================
-- ---------- facilitator workflow: stories, fragments, Digital Quilt workshops ----------
-- Story status: draft (facilitator) -> ready_for_workshop -> (workshop: every fragment confirmed) -> ready_for_annotation
--   -> submitted (annotator) -> published or returned (validator) -> submitted ...
-- withdrawn: at any status a facilitator of the site can withdraw a story, or its whole consent record; the story is then
-- hidden everywhere (admins still see it) and nothing about it can change any more. Every write is in audit_log.

-- One-time renaming of the earlier statuses (pending -> draft, draft (annotation) -> ready_for_annotation) and of the
-- earlier fragment details. Recorded in wm_migrations so that running this file again never repeats it.
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
end $$;
alter table public.stories drop constraint if exists stories_status_check;
alter table public.stories add constraint stories_status_check check (status in
  ('draft', 'ready_for_workshop', 'ready_for_annotation', 'submitted', 'returned', 'published', 'withdrawn'));
alter table public.stories alter column status set default 'draft';

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
create or replace function public.texts_ok(a text[], n integer) returns boolean
language sql immutable as $$
  select not exists (select 1 from unnest(a) x where x is null or char_length(x) not between 1 and n);
$$;

-- Story fields: the site, the question it answers (one of the site's 5), language or dialect, sensitive material,
-- where it came from (workshop_field: the facilitator website; ar: the AR app), the central location (lat/lon; for an area
-- also the polygon, lat/lon then being its centre), the workshop preparation pile and the narrator's review.
alter table public.stories add column if not exists site_id              uuid references public.sites(id) on delete restrict;
alter table public.stories alter column site_id set default public.my_site();
alter table public.stories add column if not exists question_id          uuid references public.site_questions(id) on delete restrict;
alter table public.stories add column if not exists language             text references public.story_languages(code) on update cascade;
alter table public.stories add column if not exists sensitive            boolean;
alter table public.stories add column if not exists source               text not null default 'workshop_field';
alter table public.stories add column if not exists area                 jsonb;
alter table public.stories add column if not exists workshop_bucket      text;
alter table public.stories add column if not exists withdrawn_at         timestamptz;
alter table public.stories add column if not exists narrator_reviewed_at timestamptz;
alter table public.stories add column if not exists updated_at           timestamptz not null default now();
alter table public.stories drop constraint if exists stories_workflow_check;
alter table public.stories add constraint stories_workflow_check check (
  source in ('workshop_field', 'ar')
  and (workshop_bucket is null or workshop_bucket in ('discuss', 'quick'))
  and (area is null or public.is_polygon(area))
  and (site_id is null or (question_id is not null and language is not null and sensitive is not null and consent_id is not null)));
create index if not exists stories_site_idx on public.stories(site_id, status);
create index if not exists stories_consent_idx on public.stories(consent_id);

-- Fragment fields. Title (= what) is required before the workshop. Who: several values. Where: a place name and/or a
-- point or an area. When: an exact date, an approximate text ("~1922", "summer 1965") or blank. For who, where and when:
-- stated by the narrator (locked in the workshop), inferred by the facilitator, or added at the workshop.
-- The original upload is stored as it is: sha256 computed by the browser, etag (MD5) and size taken from the storage
-- server when the fragment is saved. A thumbnail (photo/video) and a waveform (audio) are made for display.
-- patch_status is set in the workshop only: pending (grey) -> discussed (amber) -> confirmed (green).
alter table public.story_media add column if not exists who           text[];
alter table public.story_media add column if not exists area          jsonb;
alter table public.story_media add column if not exists when_kind     text;
alter table public.story_media add column if not exists when_date     date;
alter table public.story_media add column if not exists who_src       text not null default 'stated';
alter table public.story_media add column if not exists where_src     text not null default 'stated';
alter table public.story_media add column if not exists when_src      text not null default 'stated';
alter table public.story_media add column if not exists provenance    text;
alter table public.story_media add column if not exists sha256        text;
alter table public.story_media add column if not exists etag          text;
alter table public.story_media add column if not exists size_bytes    bigint;
alter table public.story_media add column if not exists mime          text;
alter table public.story_media add column if not exists original_name text;
alter table public.story_media add column if not exists thumb_path    text;
alter table public.story_media add column if not exists waveform      jsonb;
alter table public.story_media add column if not exists duration_s    real;
alter table public.story_media add column if not exists patch_status  text not null default 'pending';
alter table public.story_media add column if not exists created_at    timestamptz not null default now();
alter table public.story_media add column if not exists updated_at    timestamptz not null default now();
do $$
begin
  if not exists (select 1 from public.wm_migrations where name = 'fragment_fields_v2') then
    update public.story_media set who = array[btrim(about)] where who is null and coalesce(btrim(about), '') <> '';
    update public.story_media set when_kind = 'approx' where when_kind is null and coalesce(btrim(period), '') <> '';
    update public.story_media set title = what where coalesce(btrim(title), '') = '' and coalesce(btrim(what), '') <> '';
    insert into public.wm_migrations (name) values ('fragment_fields_v2');
  end if;
end $$;
alter table public.story_media drop constraint if exists story_media_fragment_check;
alter table public.story_media add constraint story_media_fragment_check check (
  (title is null or char_length(title) <= 200)
  and (who is null or (cardinality(who) <= 20 and public.texts_ok(who, 200)))
  and (place_name is null or char_length(place_name) <= 200)
  and ((lat is null) = (lon is null)) and (lat is null or (lat between -90 and 90 and lon between -180 and 180))
  and (area is null or public.is_polygon(area))
  and (when_kind is null or when_kind in ('exact', 'approx'))
  and (when_kind is distinct from 'exact' or when_date is not null)
  and (when_kind is distinct from 'approx' or char_length(coalesce(period, '')) between 1 and 120)
  and who_src in ('stated', 'inferred', 'workshop') and where_src in ('stated', 'inferred', 'workshop')
  and when_src in ('stated', 'inferred', 'workshop')
  and patch_status in ('pending', 'discussed', 'confirmed')
  and (sha256 is null or sha256 ~ '^[0-9a-f]{64}$')
  and (original_name is null or char_length(original_name) <= 255)
  and (waveform is null or jsonb_typeof(waveform) = 'array')) not valid;

-- Internal comment on a fragment: visible to the site's facilitators and to annotators/validators, never public.
-- Workshop disagreements are appended to it.
create table if not exists public.fragment_notes (
  media_id   uuid primary key references public.story_media(id) on delete cascade,
  body       text not null check (char_length(body) <= 8000),
  updated_by uuid default auth.uid() references auth.users(id) on delete set null,
  updated_at timestamptz not null default now()
);

-- ---------- workshops ----------
-- The facilitator sorts the site's ready stories (To discuss / Quick confirm), then creates a session with a date and the
-- chosen stories in order (and whether each narrator is invited). Started: the stories in it can only be changed through
-- the workshop actions below. Closed: unfinished stories stay ready_for_workshop for a next session.
create table if not exists public.workshops (
  id           uuid primary key default gen_random_uuid(),
  site_id      uuid not null default public.my_site() references public.sites(id) on delete restrict,
  session_date date not null,
  title        text check (title is null or char_length(title) <= 200),
  status       text not null default 'planned' check (status in ('planned', 'started', 'closed')),
  created_by   uuid default auth.uid() references auth.users(id) on delete set null,
  created_at   timestamptz not null default now(),
  started_at   timestamptz,
  closed_at    timestamptz
);
create table if not exists public.workshop_stories (
  workshop_id       uuid not null references public.workshops(id) on delete cascade,
  story_id          uuid not null references public.stories(id) on delete cascade,
  position          integer not null default 0,
  narrator_invited  boolean not null default false,
  narrator_present  boolean not null default false,
  narrator_reviewed boolean not null default false,
  primary key (workshop_id, story_id)
);
create index if not exists workshop_stories_story_idx on public.workshop_stories(story_id);
-- Versions: every change made in a workshop (field, old and new value, who, when, which session).
create table if not exists public.workshop_changes (
  id          bigserial primary key,
  workshop_id uuid references public.workshops(id) on delete set null,
  story_id    uuid,
  media_id    uuid,
  field       text not null,
  old_value   jsonb,
  new_value   jsonb,
  changed_by  uuid default auth.uid(),
  changed_at  timestamptz not null default now()
);
create index if not exists workshop_changes_story_idx on public.workshop_changes(story_id, changed_at);

-- ---------- helpers for the rules ----------
create or replace function public.in_running_workshop(sid uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.workshop_stories ws join public.workshops w on w.id = ws.workshop_id
                 where ws.story_id = sid and w.status = 'started');
$$;
-- Can the signed-in user change this story and its fragments now? A facilitator of its site, while the story is a draft or
-- ready for the workshop, and not while a workshop with it is running.
create or replace function public.can_edit_story(sid uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select public.is_facilitator()
     and exists (select 1 from public.stories s where s.id = sid and s.site_id = public.my_site() and s.status in ('draft', 'ready_for_workshop'))
     and not public.in_running_workshop(sid);
$$;
-- What still stops a draft from going to the workshop: 'consent' (no active consent), 'audio' (no audio fragment),
-- 'titles' (a fragment without a title).
create or replace function public.story_problems(sid uuid) returns text[]
language sql stable security definer set search_path = public as $$
  select array_remove(array[
    case when not exists (select 1 from public.stories s join public.consents c on c.id = s.consent_id
                          where s.id = sid and c.status = 'active') then 'consent' end,
    case when not exists (select 1 from public.story_media m where m.story_id = sid and m.kind = 'audio') then 'audio' end,
    case when exists (select 1 from public.story_media m where m.story_id = sid and coalesce(btrim(m.title), '') = '') then 'titles' end
  ], null);
$$;
revoke execute on function public.in_running_workshop(uuid), public.can_edit_story(uuid), public.story_problems(uuid) from public, anon;
grant execute on function public.in_running_workshop(uuid), public.can_edit_story(uuid), public.story_problems(uuid) to authenticated;

-- ---------- stories: who may read, add, change, delete ----------
drop policy if exists "read visible stories"          on public.stories;
drop policy if exists "facilitators add stories"      on public.stories;
drop policy if exists "facilitators edit stories"     on public.stories;
drop policy if exists "annotators publish"            on public.stories;
drop policy if exists "owners finish review"          on public.stories;
drop policy if exists "delete stories"                on public.stories;
-- Published: everyone. Withdrawn: admins only. Otherwise: the site's facilitators (every status); annotators once the
-- story has left the workshop; stories from before sites existed: their uploader and annotators.
create policy "read visible stories" on public.stories for select
  using (status = 'published' or public.is_admin()
    or (status <> 'withdrawn' and (
         (site_id is null and (user_id = auth.uid() or public.is_annotator()))
      or (site_id is not null and public.is_facilitator() and site_id = public.my_site())
      or (site_id is not null and public.is_annotator() and status in ('ready_for_annotation', 'submitted', 'returned') and public.sees_site(site_id)))));
-- No story without an active consent record of the same site; a new story is a draft.
create policy "facilitators add stories" on public.stories for insert to authenticated
  with check (public.is_facilitator() and user_id = auth.uid() and site_id = public.my_site() and status = 'draft'
    and exists (select 1 from public.consents c where c.id = stories.consent_id and c.site_id = stories.site_id and c.status = 'active'));
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
grant update (status, title, lat, lon, area, radius, question_id, language, sensitive, consent_id, workshop_bucket) on public.stories to authenticated;

-- The rules the policies cannot express: which status changes are allowed and who may make them, and that a story's
-- content changes only while the facilitators work on it. The SQL editor (no signed-in user) is not limited; the workshop
-- actions below set wm.workshop and check their own rules.
create or replace function public.guard_story() returns trigger
language plpgsql security definer set search_path = public as $$
declare
  fac boolean;
  via_ws boolean := coalesce(current_setting('wm.workshop', true), '') = 'on';
  probs text[];
begin
  if tg_op = 'INSERT' then
    new.updated_at := now();
    if auth.uid() is not null then
      new.workshop_bucket := null; new.withdrawn_at := null; new.narrator_reviewed_at := null;
      if new.site_id is not null and not exists (select 1 from public.site_questions q where q.id = new.question_id and q.site_id = new.site_id) then
        raise exception 'Choose one of the site''s questions' using errcode = '23514';
      end if;
    end if;
    return new;
  end if;
  -- the hard rule holds for everyone except the SQL editor
  if auth.uid() is not null and old.status = 'ready_for_workshop' and new.status = 'ready_for_annotation'
     and (not exists (select 1 from public.story_media m where m.story_id = old.id)
          or exists (select 1 from public.story_media m where m.story_id = old.id and m.patch_status <> 'confirmed')) then
    raise exception 'A story moves to annotation only when the workshop has confirmed all its fragments' using errcode = '42501';
  end if;
  if auth.uid() is null or via_ws then new.updated_at := now(); return new; end if;
  if old.status = 'withdrawn' then raise exception 'A withdrawn story cannot be changed' using errcode = '42501'; end if;
  fac := public.is_facilitator() and old.site_id is not distinct from public.my_site();
  if (new.title, new.lat, new.lon, new.area, new.radius, new.question_id, new.language, new.sensitive, new.consent_id, new.workshop_bucket)
     is distinct from (old.title, old.lat, old.lon, old.area, old.radius, old.question_id, old.language, old.sensitive, old.consent_id, old.workshop_bucket) then
    if not fac or old.status not in ('draft', 'ready_for_workshop') or public.in_running_workshop(old.id) then
      raise exception 'Only the site''s facilitators can change a story, and only until its workshop starts' using errcode = '42501';
    end if;
    if new.question_id is distinct from old.question_id
       and not exists (select 1 from public.site_questions q where q.id = new.question_id and q.site_id = old.site_id) then
      raise exception 'Choose one of the site''s questions' using errcode = '23514';
    end if;
    if new.consent_id is distinct from old.consent_id
       and not exists (select 1 from public.consents c where c.id = new.consent_id and c.site_id = old.site_id and c.status = 'active') then
      raise exception 'Choose an active consent record of this site' using errcode = '23514';
    end if;
  end if;
  if new.status is distinct from old.status then
    if new.status = 'withdrawn' then
      if not (fac or public.is_admin()) then raise exception 'Only the site''s facilitators can withdraw a story' using errcode = '42501'; end if;
      new.withdrawn_at := now();
    elsif old.status = 'draft' and new.status = 'ready_for_workshop' then
      if not fac then raise exception 'Only the site''s facilitators can send a story to the workshop' using errcode = '42501'; end if;
      probs := public.story_problems(old.id);
      if cardinality(probs) > 0 then
        raise exception 'Not ready for the workshop: %', array_to_string(probs, ', ') using errcode = '23514';
      end if;
    elsif old.status = 'ready_for_workshop' and new.status = 'draft' then
      if not fac or public.in_running_workshop(old.id) then
        raise exception 'Only the site''s facilitators can take a story back, and not during its workshop' using errcode = '42501';
      end if;
    elsif new.status = 'submitted' and old.status in ('ready_for_annotation', 'returned') then
      if not public.is_annotator() then raise exception 'Only an annotator can submit a story' using errcode = '42501'; end if;
    elsif new.status = 'ready_for_annotation' and old.status in ('submitted', 'published') then
      if not public.is_annotator() then raise exception 'Only an annotator can take a story back' using errcode = '42501'; end if;
    elsif old.status = 'submitted' and new.status in ('published', 'returned') then
      if not public.is_validator() then raise exception 'Only a validator can publish or return a story' using errcode = '42501'; end if;
    else
      raise exception 'This status change is not allowed (% -> %)', old.status, new.status using errcode = '42501';
    end if;
  end if;
  new.updated_at := now();
  return new;
end $$;
drop trigger if exists stories_status_guard on public.stories;
drop trigger if exists stories_review_edit  on public.stories;
drop trigger if exists stories_guard        on public.stories;
create trigger stories_guard before insert or update on public.stories for each row execute function public.guard_story();
drop function if exists public.check_story_status();

-- Withdrawing a consent record withdraws all its stories; a withdrawn record stays withdrawn.
create or replace function public.guard_consent() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if auth.uid() is null then return new; end if;
  if old.status = 'withdrawn' and new.status is distinct from old.status then
    raise exception 'A withdrawn consent record stays withdrawn' using errcode = '42501';
  end if;
  if new.status = 'withdrawn' and old.status <> 'withdrawn' then
    new.withdrawn_at := now();
    update public.stories set status = 'withdrawn' where consent_id = new.id and status <> 'withdrawn';
  end if;
  return new;
end $$;
drop trigger if exists consents_guard on public.consents;
create trigger consents_guard before update on public.consents for each row execute function public.guard_consent();

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
grant update (position, title, who, place_name, lat, lon, area, when_kind, when_date, period, recorded_at, who_src, where_src, when_src)
  on public.story_media to authenticated;

create or replace function public.guard_fragment() returns trigger
language plpgsql security definer set search_path = public as $$
declare via_ws boolean := coalesce(current_setting('wm.workshop', true), '') = 'on';
begin
  if tg_op = 'DELETE' then
    if auth.uid() is null or via_ws or not exists (select 1 from public.stories s where s.id = old.story_id) then return old; end if;  -- story deleted
    if not public.can_edit_story(old.story_id) then
      raise exception 'Fragments can be removed only by the site''s facilitators, until the workshop starts' using errcode = '42501';
    end if;
    return old;
  end if;
  if tg_op = 'INSERT' then
    new.created_at := now(); new.updated_at := now();
    new.provenance := case when new.kind in ('image', 'video') then 'own_or_family_item' end;
    -- the storage server's own fingerprint and size of the uploaded original
    select btrim(o.metadata->>'eTag', '"'), (o.metadata->>'size')::bigint into new.etag, new.size_bytes
      from storage.objects o where o.bucket_id = 'story-media' and o.name = new.path;
    if auth.uid() is null then return new; end if;
    new.patch_status := 'pending';
    if new.etag is null and new.size_bytes is null then
      raise exception 'Upload the file before adding the fragment' using errcode = '23514';
    end if;
    return new;
  end if;
  new.updated_at := now();
  if auth.uid() is null or via_ws then return new; end if;
  if (new.title, new.who, new.place_name, new.lat, new.lon, new.area, new.when_kind, new.when_date, new.period, new.recorded_at,
      new.who_src, new.where_src, new.when_src, new.about, new.what)
     is not distinct from (old.title, old.who, old.place_name, old.lat, old.lon, old.area, old.when_kind, old.when_date, old.period,
      old.recorded_at, old.who_src, old.where_src, old.when_src, old.about, old.what) then
    -- only the position: the site's facilitators while editable, annotators once the story is in annotation
    if public.can_edit_story(old.story_id) or (public.is_annotator() and exists (select 1 from public.stories s where s.id = old.story_id
         and s.status in ('ready_for_annotation', 'submitted', 'returned', 'published'))) then
      return new;
    end if;
    raise exception 'The order can be changed only by the site''s facilitators or, in annotation, by annotators' using errcode = '42501';
  end if;
  if not public.can_edit_story(old.story_id) then
    raise exception 'Only the site''s facilitators can change a fragment, and only until its workshop starts' using errcode = '42501';
  end if;
  return new;
end $$;
drop trigger if exists story_media_review_edit on public.story_media;
drop trigger if exists story_media_guard       on public.story_media;
create trigger story_media_guard before insert or update or delete on public.story_media for each row execute function public.guard_fragment();
drop function if exists public.check_review_edit();

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

-- ---------- workshops: who may read and prepare ----------
alter table public.workshops        enable row level security;
alter table public.workshop_stories enable row level security;
alter table public.workshop_changes enable row level security;
drop policy if exists "staff read workshops"           on public.workshops;
drop policy if exists "facilitators plan workshops"    on public.workshops;
drop policy if exists "facilitators run workshops"     on public.workshops;
drop policy if exists "facilitators delete workshops"  on public.workshops;
drop policy if exists "staff read workshop stories"    on public.workshop_stories;
drop policy if exists "facilitators fill workshops"    on public.workshop_stories;
drop policy if exists "staff read workshop changes"    on public.workshop_changes;
create policy "staff read workshops" on public.workshops for select to authenticated using (public.sees_site(site_id));
create policy "facilitators plan workshops" on public.workshops for insert to authenticated
  with check (public.is_facilitator() and site_id = public.my_site() and status = 'planned');
create policy "facilitators run workshops" on public.workshops for update to authenticated
  using (public.is_facilitator() and site_id = public.my_site()) with check (public.is_facilitator() and site_id = public.my_site());
create policy "facilitators delete workshops" on public.workshops for delete to authenticated
  using (public.is_facilitator() and site_id = public.my_site() and status = 'planned');
create policy "staff read workshop stories" on public.workshop_stories for select to authenticated
  using (exists (select 1 from public.workshops w where w.id = workshop_stories.workshop_id));
-- Stories are put in (and taken out of, reordered, narrator invited) only while the session is planned.
create policy "facilitators fill workshops" on public.workshop_stories for all to authenticated
  using (exists (select 1 from public.workshops w where w.id = workshop_stories.workshop_id
                 and public.is_facilitator() and w.site_id = public.my_site() and w.status = 'planned'))
  with check (exists (select 1 from public.workshops w join public.stories s on s.id = workshop_stories.story_id
                      where w.id = workshop_stories.workshop_id and public.is_facilitator() and w.site_id = public.my_site()
                        and w.status = 'planned' and s.site_id = w.site_id and s.status = 'ready_for_workshop'));
create policy "staff read workshop changes" on public.workshop_changes for select to authenticated
  using (public.is_admin() or exists (select 1 from public.stories s where s.id = workshop_changes.story_id));
revoke all on public.workshops, public.workshop_stories, public.workshop_changes from anon;
grant select, insert, delete on public.workshops, public.workshop_stories to authenticated;
grant update (session_date, title, status) on public.workshops to authenticated;
grant update (position, narrator_invited) on public.workshop_stories to authenticated;
grant select on public.workshop_changes to authenticated;

create or replace function public.guard_workshop() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if auth.uid() is null then return new; end if;
  if new.status is distinct from old.status then
    if not ((old.status = 'planned' and new.status = 'started') or (old.status = 'started' and new.status = 'closed')) then
      raise exception 'A workshop goes planned -> started -> closed' using errcode = '42501';
    end if;
    if new.status = 'started' then new.started_at := now(); else new.closed_at := now(); end if;
  elsif old.status <> 'planned' and (new.session_date, new.title) is distinct from (old.session_date, old.title) then
    raise exception 'Only a planned workshop can be changed' using errcode = '42501';
  end if;
  return new;
end $$;
drop trigger if exists workshops_guard on public.workshops;
create trigger workshops_guard before update on public.workshops for each row execute function public.guard_workshop();

-- ---------- workshop actions (presentation mode) ----------
-- Each action checks: a facilitator of the workshop's site, the workshop has started, the story is in it and still
-- ready_for_workshop. Fields stated by the narrator stay locked (a disagreement goes to the fragment's comment); media
-- cannot be changed. Every change is versioned in workshop_changes with the session and the time.
create or replace function public.ws_open(p_workshop uuid, p_story uuid) returns public.workshops
language plpgsql security definer set search_path = public as $$
declare w public.workshops;
begin
  select * into w from public.workshops where id = p_workshop;
  if w.id is null or not public.is_facilitator() or w.site_id is distinct from public.my_site() then
    raise exception 'Not a workshop of your site' using errcode = '42501';
  end if;
  if w.status <> 'started' then raise exception 'The workshop is not running' using errcode = '42501'; end if;
  if not exists (select 1 from public.workshop_stories ws join public.stories s on s.id = ws.story_id
                 where ws.workshop_id = p_workshop and ws.story_id = p_story and s.status = 'ready_for_workshop') then
    raise exception 'This story is not open in this workshop' using errcode = '42501';
  end if;
  perform set_config('wm.workshop', 'on', true);
  perform set_config('wm.workshop_id', p_workshop::text, true);
  return w;
end $$;
revoke execute on function public.ws_open(uuid, uuid) from public, anon, authenticated;

-- p_field 'who' (p_value: array of names), 'where' ({place_name, lat, lon, area}) or 'when' ({when_kind, when_date, period}).
create or replace function public.workshop_set_field(p_workshop uuid, p_media uuid, p_field text, p_value jsonb) returns void
language plpgsql security definer set search_path = public as $$
declare m public.story_media; w public.workshops; oldv jsonb;
begin
  select * into m from public.story_media where id = p_media;
  if m.id is null then raise exception 'No such fragment' using errcode = '42501'; end if;
  w := public.ws_open(p_workshop, m.story_id);
  if p_field = 'who' then
    if m.who_src = 'stated' and coalesce(cardinality(m.who), 0) > 0 then
      raise exception 'Stated by the narrator: locked in the workshop' using errcode = '42501';
    end if;
    oldv := to_jsonb(m.who);
    update public.story_media set who_src = 'workshop',
      who = (select array_agg(btrim(x)) from jsonb_array_elements_text(case when jsonb_typeof(p_value) = 'array' then p_value else '[]' end) x
             where btrim(x) <> '')
      where id = p_media;
  elsif p_field = 'where' then
    if m.where_src = 'stated' and (m.place_name is not null or m.lat is not null or m.area is not null) then
      raise exception 'Stated by the narrator: locked in the workshop' using errcode = '42501';
    end if;
    oldv := jsonb_build_object('place_name', m.place_name, 'lat', m.lat, 'lon', m.lon, 'area', m.area);
    update public.story_media set where_src = 'workshop',
      place_name = nullif(btrim(p_value->>'place_name'), ''),
      lat = (p_value->>'lat')::float8, lon = (p_value->>'lon')::float8,
      area = case when jsonb_typeof(p_value->'area') = 'object' then p_value->'area' end
      where id = p_media;
  elsif p_field = 'when' then
    if m.when_src = 'stated' and m.when_kind is not null then
      raise exception 'Stated by the narrator: locked in the workshop' using errcode = '42501';
    end if;
    oldv := jsonb_build_object('when_kind', m.when_kind, 'when_date', m.when_date, 'period', m.period);
    update public.story_media set when_src = 'workshop',
      when_kind = nullif(p_value->>'when_kind', ''),
      when_date = case when p_value->>'when_kind' = 'exact' then (p_value->>'when_date')::date end,
      period = case when p_value->>'when_kind' = 'approx' then nullif(btrim(p_value->>'period'), '') end
      where id = p_media;
  else
    raise exception 'Only who, where and when can be changed in the workshop' using errcode = '42501';
  end if;
  insert into public.workshop_changes (workshop_id, story_id, media_id, field, old_value, new_value)
  values (p_workshop, m.story_id, p_media, p_field, oldv, p_value);
end $$;

-- One click: pending -> discussed -> confirmed. When every fragment of the story is confirmed, the story moves on to
-- annotation (ready_for_annotation). Returns the story's status.
create or replace function public.workshop_set_patch(p_workshop uuid, p_media uuid, p_status text) returns text
language plpgsql security definer set search_path = public as $$
declare m public.story_media; w public.workshops; st text;
begin
  if p_status not in ('pending', 'discussed', 'confirmed') then raise exception 'Unknown patch status' using errcode = '22023'; end if;
  select * into m from public.story_media where id = p_media;
  if m.id is null then raise exception 'No such fragment' using errcode = '42501'; end if;
  w := public.ws_open(p_workshop, m.story_id);
  update public.story_media set patch_status = p_status where id = p_media;
  insert into public.workshop_changes (workshop_id, story_id, media_id, field, old_value, new_value)
  values (p_workshop, m.story_id, p_media, 'patch_status', to_jsonb(m.patch_status), to_jsonb(p_status));
  if not exists (select 1 from public.story_media x where x.story_id = m.story_id and x.patch_status <> 'confirmed') then
    update public.stories set status = 'ready_for_annotation' where id = m.story_id;
    insert into public.workshop_changes (workshop_id, story_id, field, old_value, new_value)
    values (p_workshop, m.story_id, 'status', '"ready_for_workshop"', '"ready_for_annotation"');
  end if;
  select status into st from public.stories where id = m.story_id;
  return st;
end $$;

-- A disagreement (or any remark) is appended to the fragment's comment, dated with the session.
create or replace function public.workshop_add_note(p_workshop uuid, p_media uuid, p_text text) returns void
language plpgsql security definer set search_path = public as $$
declare m public.story_media; w public.workshops; line text;
begin
  if coalesce(btrim(p_text), '') = '' then raise exception 'Write the note first' using errcode = '22023'; end if;
  select * into m from public.story_media where id = p_media;
  if m.id is null then raise exception 'No such fragment' using errcode = '42501'; end if;
  w := public.ws_open(p_workshop, m.story_id);
  line := '[' || to_char(w.session_date, 'YYYY-MM-DD') || '] ' || left(btrim(p_text), 2000);
  insert into public.fragment_notes (media_id, body) values (p_media, line)
  on conflict (media_id) do update set body = left(public.fragment_notes.body || E'\n' || line, 8000), updated_by = auth.uid(), updated_at = now();
  insert into public.workshop_changes (workshop_id, story_id, media_id, field, new_value)
  values (p_workshop, m.story_id, p_media, 'note', to_jsonb(line));
end $$;

-- Narrator present at the session, and "Reviewed by narrator" (only when the consent asks for the narrator's review and
-- the narrator is present).
create or replace function public.workshop_narrator(p_workshop uuid, p_story uuid, p_present boolean, p_reviewed boolean) returns void
language plpgsql security definer set search_path = public as $$
declare w public.workshops; wants boolean;
begin
  w := public.ws_open(p_workshop, p_story);
  select coalesce(c.narrator_review, false) into wants from public.stories s left join public.consents c on c.id = s.consent_id where s.id = p_story;
  if p_reviewed and not (p_present and wants) then
    raise exception 'Reviewed by narrator needs the narrator present and a consent that asks for the review' using errcode = '42501';
  end if;
  update public.workshop_stories set narrator_present = p_present, narrator_reviewed = p_reviewed
    where workshop_id = p_workshop and story_id = p_story;
  update public.stories set narrator_reviewed_at = case when p_reviewed then coalesce(narrator_reviewed_at, now()) end where id = p_story;
  insert into public.workshop_changes (workshop_id, story_id, field, new_value)
  values (p_workshop, p_story, 'narrator', jsonb_build_object('present', p_present, 'reviewed', p_reviewed));
end $$;
revoke execute on function public.workshop_set_field(uuid, uuid, text, jsonb), public.workshop_set_patch(uuid, uuid, text),
  public.workshop_add_note(uuid, uuid, text), public.workshop_narrator(uuid, uuid, boolean, boolean) from public, anon;
grant execute on function public.workshop_set_field(uuid, uuid, text, jsonb), public.workshop_set_patch(uuid, uuid, text),
  public.workshop_add_note(uuid, uuid, text), public.workshop_narrator(uuid, uuid, boolean, boolean) to authenticated;

-- ---------- audit log: every write (user, time, entity, action, previous value, what changed) ----------
create table if not exists public.audit_log (
  id          bigserial primary key,
  at          timestamptz not null default now(),
  user_id     uuid,
  entity      text not null,
  entity_id   text,
  action      text not null check (action in ('insert', 'update', 'delete')),
  previous    jsonb,
  changes     jsonb,
  workshop_id uuid
);
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
  insert into public.audit_log (user_id, entity, entity_id, action, previous, changes, workshop_id)
  values (auth.uid(), tg_table_name,
          coalesce(r->>'id', r->>'media_id', r->>'consent_id', r->>'code', r->>'user_id', (r->>'workshop_id') || '/' || (r->>'story_id')),
          lower(tg_op), prev, chg, nullif(current_setting('wm.workshop_id', true), '')::uuid);
  return case when tg_op = 'DELETE' then old else new end;
end $$;
do $$
declare t text;
begin
  foreach t in array array['sites', 'site_questions', 'story_languages', 'profiles', 'consents', 'consent_narrators', 'stories',
                           'story_media', 'fragment_notes', 'workshops', 'workshop_stories'] loop
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

-- Walks: an annotator submits a board as a walk; it is shown in the app (is_walk) only after a validator approves it.
alter table public.story_boards add column if not exists walk_status text not null default 'none';
alter table public.story_boards drop constraint if exists story_boards_walk_status_check;
alter table public.story_boards add constraint story_boards_walk_status_check check (walk_status in ('none', 'submitted', 'returned', 'approved'));
update public.story_boards set walk_status = 'approved' where is_walk and walk_status = 'none';
create or replace function public.check_walk_status() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if auth.uid() is not null and not public.is_validator() and (
       (new.is_walk and not coalesce(old.is_walk, false))
       or (new.walk_status is distinct from old.walk_status and new.walk_status in ('approved', 'returned'))) then
    raise exception 'Only a validator can approve or return a walk' using errcode = '42501';
  end if;
  return new;
end $$;
drop trigger if exists story_boards_walk_guard on public.story_boards;
create trigger story_boards_walk_guard before update on public.story_boards for each row execute function public.check_walk_status();
grant select (walk_status) on public.story_boards to anon;

-- History of submissions and decisions (with the validator's comments)
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
  with check (public.is_annotator() and user_id = auth.uid() and (action in ('submitted', 'withdrawn', 'unpublished') or public.is_validator()));
revoke all on public.reviews from anon;
grant select, insert on public.reviews to authenticated;

-- ---------- facilitator comments from the earlier review page (read by the facilitator and the annotation team) ----------
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
create policy "read story comments" on public.facilitator_comments for select to authenticated
  using (public.is_annotator() or public.is_admin()
         or exists (select 1 from public.stories s where s.id = facilitator_comments.story_id and s.user_id = auth.uid()));
-- (The earlier review page is replaced by the workshop; its comments stay readable, no new ones are added.)
revoke all on public.facilitator_comments from anon;
grant select on public.facilitator_comments to authenticated;

-- Make the API pick up new columns immediately (avoids "could not find the column ... in the schema cache")
notify pgrst, 'reload schema';
