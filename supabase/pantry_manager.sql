-- Pantry manager role — run this entire file in Supabase → SQL Editor.
-- Lets a device claim a GCFD directory pantry, post surplus listings under
-- it, and mark it temporarily closed. Claims are keyed by the GCFD dataset's
-- own stable location id (see GCFDDatabase.Location.locationID), not a
-- Supabase-generated id, since that's the only identifier that survives the
-- daily GCFD dataset resync.

-- ---------------------------------------------------------------------------
-- listings: tag a listing as posted on behalf of a claimed pantry
-- ---------------------------------------------------------------------------

alter table public.listings
  add column if not exists pantry_gcfd_location_id bigint;

-- ---------------------------------------------------------------------------
-- pantry_claims
-- ---------------------------------------------------------------------------

create table if not exists public.pantry_claims (
  gcfd_location_id bigint primary key,
  pantry_name text not null,
  claimed_by uuid not null references auth.users(id) on delete cascade,
  claimed_at timestamptz not null default now(),
  is_temporarily_closed boolean not null default false,
  closed_note text
);

alter table public.pantry_claims enable row level security;

drop policy if exists "Anyone reads pantry claims" on public.pantry_claims;
create policy "Anyone reads pantry claims"
  on public.pantry_claims for select to authenticated
  using (true);

-- The primary key on gcfd_location_id already enforces "first come, first
-- served" — a second claim on the same pantry fails with a conflict.
drop policy if exists "Claim an unclaimed pantry" on public.pantry_claims;
create policy "Claim an unclaimed pantry"
  on public.pantry_claims for insert to authenticated
  with check (claimed_by = auth.uid());

drop policy if exists "Manager updates own pantry claim" on public.pantry_claims;
create policy "Manager updates own pantry claim"
  on public.pantry_claims for update to authenticated
  using (claimed_by = auth.uid())
  with check (claimed_by = auth.uid());

drop policy if exists "Manager releases own pantry claim" on public.pantry_claims;
create policy "Manager releases own pantry claim"
  on public.pantry_claims for delete to authenticated
  using (claimed_by = auth.uid());

grant select, insert, update, delete on public.pantry_claims to authenticated;

-- Optional: Database → Replication → enable Realtime on public.pantry_claims
-- if you want closures/claims to push to other devices instantly instead of
-- on next foreground/launch sync.
