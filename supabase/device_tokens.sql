-- Device tokens for APNs push delivery.
-- Run in Supabase SQL editor, then deploy the Edge Function (see README_PUSH.md).

create table if not exists public.device_tokens (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  token text not null,
  platform text not null default 'ios',
  updated_at timestamptz not null default now(),
  unique (user_id, token)
);

create index if not exists device_tokens_user_id_idx on public.device_tokens(user_id);

alter table public.device_tokens enable row level security;

create policy "Users manage own device tokens"
  on public.device_tokens
  for all
  to authenticated
  using (user_id = auth.uid())
  with check (user_id = auth.uid());

grant select, insert, update, delete on public.device_tokens to authenticated;

-- Enable Realtime for handoff tables (Dashboard → Database → Publications → supabase_realtime).
alter publication supabase_realtime add table public.listings;
alter publication supabase_realtime add table public.listing_messages;

-- Optional: webhook triggers (configure in Dashboard → Database → Webhooks, or use pg_net).
-- Point both to: https://<project-ref>.supabase.co/functions/v1/send-handoff-push
--   1) listings UPDATE
--   2) listing_messages INSERT
