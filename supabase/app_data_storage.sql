-- public storage bucket for app reference data like food locations
-- lets installed apps fetch fresh data without a new build
-- run whole file in sql editor
--
-- writes only come from sync script with service role key
-- no client can write to this bucket
-- reads are public because pantry info has no user data

insert into storage.buckets (id, name, public)
values ('app-data', 'app-data', true)
on conflict (id) do update set public = true;

drop policy if exists "Public read app-data" on storage.objects;
create policy "Public read app-data"
  on storage.objects for select
  to public
  using (bucket_id = 'app-data');

-- no write policy on purpose, service key bypasses rls
-- so client roles stay read only
