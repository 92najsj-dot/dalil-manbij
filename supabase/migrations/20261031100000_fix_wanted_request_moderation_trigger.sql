-- Prevent the legacy wanted_requests trigger from overwriting the consolidated moderation decision.
-- The aa_moderate_new_wanted_requests trigger remains the single moderation authority.
DROP TRIGGER IF EXISTS wanted_requests_auto_moderation ON public.wanted_requests;
