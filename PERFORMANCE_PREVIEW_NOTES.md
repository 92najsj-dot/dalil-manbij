# Dalil Manbij performance preview

Branch: `perf/resource-optimization-preview-20261104`

## Included changes
- Service worker caches up to 40 public `manbij-images` image responses per device. Original Storage objects are not changed or deleted.
- Service worker caches only anonymous GET responses from an explicit allowlist of public directory tables for 30 seconds, with a 6-hour stale fallback on errors. Authenticated requests, favorites, personal ads, and admin endpoints bypass this cache.
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


## Database and traffic findings
- Live row estimates at inspection: `site_visit_events` 19,438; `admin_audit_log` 72; `listings` 25; `businesses` 3; `local_offers` 1; `wanted_requests` 0. No speculative indexes were added to tiny content tables. Existing `site_visit_events_visitor_created_idx` supports the dedupe lookup.
- RLS is enabled on `site_visit_events`, `listings`, `businesses`, `local_offers`, `wanted_requests`, `admin_audit_log`, `blocked_users`, and `reports`. The public analytics RPC remains a narrow SECURITY DEFINER endpoint with a fixed search path and a strict event/section allowlist.
- Logs show many requests from local Manbij mobile networks. Do not block Turk Telekom traffic wholesale. M247/OVH traffic should be verified before any IP or ASN restriction.
- Supabase REST and Storage requests originate directly from the browser to `*.supabase.co`; Cloudflare Pages WAF rules alone will not protect those direct API calls. A separate, tested API proxy/rate-limit design would be required before imposing broad traffic controls.
