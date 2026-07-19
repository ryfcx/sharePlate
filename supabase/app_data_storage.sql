-- Public Storage bucket for app reference data (currently: the GCFD food
-- locations database). Lets already-installed apps fetch fresh data without
-- a new build. Run this entire file in Supabase → SQL Editor.
--
-- Writes only ever come from foodAPI/gcfd_food_sync.py using the service
-- role key (bypasses RLS) — no client, anonymous or authenticated, can
-- write to this bucket. Reads are public because this data (food pantry
-- locations/hours) is already public information with no user data in it.

insert into storage.buckets (id, name, public)
values ('app-data', 'app-data', true)
on conflict (id) do update set public = true;

drop policy if exists "Public read app-data" on storage.objects;
create policy "Public read app-data"
  on storage.objects for select
  to public
  using (bucket_id = 'app-data');

-- No insert/update/delete policy is created on purpose: the service role key
-- used by the sync script bypasses RLS entirely, so client roles (anon,
-- authenticated) get read-only access.
