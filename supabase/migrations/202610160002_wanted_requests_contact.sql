-- Optional public contact method for wanted requests.
-- The phone number is displayed only when the requester chooses to provide it.
alter table public.wanted_requests
  add column if not exists contact_phone text;

comment on column public.wanted_requests.contact_phone is
  'Optional WhatsApp contact supplied by the requester; shown publicly only when provided.';
