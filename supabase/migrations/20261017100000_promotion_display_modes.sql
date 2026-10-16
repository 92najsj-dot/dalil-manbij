-- Promotion display modes for direct admin promotion of already-published content.
-- Apply to the preview database only after reviewing the branch.
alter table public.promotions
  add column if not exists display_mode text not null default 'featured'
  check (display_mode in ('featured', 'badge', 'banner', 'combined'));

comment on column public.promotions.display_mode is
  'featured: featured section; badge: original category badge; banner: main banner if content has an image; combined: all placements.';
