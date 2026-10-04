-- Walking Memory backend. Run once in the Supabase SQL editor.
-- Everyone (logged in or not) can READ stories. Only logged-in users can
-- publish, and each user can only change or delete their own stories.

-- Safety guard: this file is for first-time setup only. Once roles.sql has been applied, running it again
-- would restore the old, weaker security rules (e.g. make drafts public). Use roles.sql for later updates.
do $$
begin
  if to_regclass('public.profiles') is not null then
    raise exception 'Roles are already installed. Do not re-run this file (it would weaken the security rules); run roles.sql instead.';
  end if;
end $$;

create table if not exists public.stories (
  id          uuid primary key default gen_random_uuid(),
  user_id     uuid not null default auth.uid() references auth.users(id) on delete cascade,
  title       text not null check (char_length(title) between 1 and 120),
  lat         double precision not null check (lat between -90 and 90),
  lon         double precision not null check (lon between -180 and 180),
  radius      integer not null default 40 check (radius between 10 and 200),
  author_name text not null default '' check (char_length(author_name) <= 60),
  created_at  timestamptz not null default now()
);

create table if not exists public.story_media (
  id        uuid primary key default gen_random_uuid(),
  story_id  uuid not null references public.stories(id) on delete cascade,
  kind      text not null check (kind in ('image', 'video', 'audio')),
  path      text not null,
  position  integer not null default 0
);

create index if not exists story_media_story_idx on public.story_media(story_id);

alter table public.stories     enable row level security;
alter table public.story_media enable row level security;

create policy "stories are public"       on public.stories for select using (true);
create policy "owners insert stories"    on public.stories for insert to authenticated with check (user_id = auth.uid());
create policy "owners update stories"    on public.stories for update to authenticated using (user_id = auth.uid()) with check (user_id = auth.uid());
create policy "owners delete stories"    on public.stories for delete to authenticated using (user_id = auth.uid());

create policy "media is public"          on public.story_media for select using (true);
create policy "owners insert media"      on public.story_media for insert to authenticated
  with check (exists (select 1 from public.stories s where s.id = story_id and s.user_id = auth.uid()));
create policy "owners delete media"      on public.story_media for delete to authenticated
  using (exists (select 1 from public.stories s where s.id = story_id and s.user_id = auth.uid()));

-- Public bucket for the uploaded files (50 MB each, images/video/audio only).
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('story-media', 'story-media', true, 52428800, array['image/*', 'video/*', 'audio/*'])
on conflict (id) do update
  set public = excluded.public,
      file_size_limit = excluded.file_size_limit,
      allowed_mime_types = excluded.allowed_mime_types;

-- Files live under <user id>/<story id>/<n>.<ext>; users may only write inside their own folder.
create policy "media files are public" on storage.objects for select using (bucket_id = 'story-media');
create policy "owners upload files"    on storage.objects for insert to authenticated
  with check (bucket_id = 'story-media' and (storage.foldername(name))[1] = auth.uid()::text);
create policy "owners delete files"    on storage.objects for delete to authenticated
  using (bucket_id = 'story-media' and (storage.foldername(name))[1] = auth.uid()::text);
