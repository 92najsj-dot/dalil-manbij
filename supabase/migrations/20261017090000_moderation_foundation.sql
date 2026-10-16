-- Dalil Manbij moderation foundation (preview branch only).
-- This migration is intentionally NOT applied to the live Supabase project.
-- Account-level review mode persists independently of post text, edits, and deletions.

create table if not exists public.user_moderation_state (
  user_id uuid primary key references auth.users(id) on delete cascade,
  manual_review_required boolean not null default false,
  violation_count integer not null default 0 check (violation_count >= 0),
  last_violation_at timestamptz,
  last_violation_reason text,
  updated_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.moderation_events (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  content_type text not null check (content_type in ('listing', 'business', 'wanted_request')),
  content_id uuid,
  event_type text not null check (event_type in ('flagged', 'sent_to_review', 'approved', 'rejected', 'review_mode_enabled', 'review_mode_disabled')),
  reason text,
  details jsonb not null default '{}'::jsonb,
  actor_user_id uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now()
);

create index if not exists moderation_events_user_created_idx
  on public.moderation_events (user_id, created_at desc);
create index if not exists moderation_events_content_idx
  on public.moderation_events (content_type, content_id);

alter table public.user_moderation_state enable row level security;
alter table public.moderation_events enable row level security;

-- Only admins may read these tables. No client-side INSERT/UPDATE policies are
-- intentionally provided, so users cannot remove their own review flag.
drop policy if exists "Admins read moderation state" on public.user_moderation_state;
create policy "Admins read moderation state"
  on public.user_moderation_state for select to authenticated
  using ((auth.jwt() -> 'app_metadata' ->> 'role') = 'admin');

drop policy if exists "Admins read moderation events" on public.moderation_events;
create policy "Admins read moderation events"
  on public.moderation_events for select to authenticated
  using ((auth.jwt() -> 'app_metadata' ->> 'role') = 'admin');

-- Writes must be added through trusted server-side moderation/admin functions,
-- not direct client requests.
