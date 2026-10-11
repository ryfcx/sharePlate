-- pantry manager role, run whole file in sql editor
-- lets a device claim a pantry and post surplus under it
-- also lets manager mark it temporarily closed
-- claims use gcfd location id, not a supabase id
-- that id survives the daily dataset resync

--
-- listings, tag a listing as posted for a claimed pantry
--

alter table public.listings
  add column if not exists pantry_gcfd_location_id bigint;

--
-- pantry claims
--

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

-- primary key gives first come first served
-- second claim on same pantry fails with conflict
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

-- optional, enable realtime on pantry claims in dashboard
-- pushes closures and claims instantly instead of on next sync
