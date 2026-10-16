-- Optional public display names for advertisers.
-- The table contains only the public display name and auth user ID.
create table if not exists public.public_profiles (
  user_id uuid primary key references auth.users(id) on delete cascade,
  display_name text null check (
    display_name is null or (
      char_length(btrim(display_name)) between 2 and 40
      and display_name !~ '[[:cntrl:]]'
    )
  ),
  updated_at timestamptz not null default now()
);

alter table public.public_profiles enable row level security;

drop policy if exists "Public can read display names" on public.public_profiles;
create policy "Public can read display names"
  on public.public_profiles for select
  to anon, authenticated
  using (true);

drop policy if exists "Users can insert their own display name" on public.public_profiles;
create policy "Users can insert their own display name"
  on public.public_profiles for insert
  to authenticated
  with check (auth.uid() = user_id);

drop policy if exists "Users can update their own display name" on public.public_profiles;
create policy "Users can update their own display name"
  on public.public_profiles for update
  to authenticated
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);

grant select on public.public_profiles to anon, authenticated;
grant insert, update on public.public_profiles to authenticated;
