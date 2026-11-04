# Dalil Manbij performance preview

Branch: `perf/resource-optimization-preview-20261104`

## Included changes
- Service worker caches up to 40 public `manbij-images` image responses per device. Original Storage objects are not changed or deleted.
- New guest listing uploads are optimized in the browser using the existing WebP optimizer and receive a one-year browser cache TTL on their unique object paths.
- Listing images use lazy loading, asynchronous decoding, and low fetch priority.
- Site analytics are queued and sent in batches of up to 20 events. The browser falls back to the existing single-event RPC until the batch migration is installed.
- Repeated section-click and search events are throttled in the browser and database.
- Existing single-event analytics RPC remains compatible with older deployed clients.

## Database migration
`supabase/migrations/20261104090000_analytics_batch_and_throttle.sql` is staged in this branch only. It has **not** been applied to the connected Supabase project.

## Safety
- No original images are deleted or overwritten.
- No production database schema or data has been changed.
- No production Pages deployment has been made.
- The connected Supabase Free organization is currently restricted for cached egress until the quota resets; full live API tests must wait until Supabase restores request serving.
- The Pages project has historically been deployed by direct upload and is not currently linked to this GitHub repository, so a Cloudflare preview deployment cannot be assumed from this branch push alone.

## Required verification before production
1. Deploy this branch to a separate Cloudflare Pages preview.
2. Apply the migration only to a dedicated staging Supabase project, not production.
3. Verify public image caching, new and existing guest listing uploads, and all analytics events.
4. Test registration/login, shops, listings, wanted requests, promotions, admin moderation, saved listings, WhatsApp, PWA and Android WebView image uploads.
5. Compare Storage egress and REST request counts over equivalent traffic windows.
6. Obtain explicit production approval before merging or deploying.
