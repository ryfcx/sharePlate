-- Listings RLS — run this entire file in Supabase → SQL Editor.
-- Fixes "new row violates row-level security policy" when marking picked up.

alter table public.listings enable row level security;

-- ---------------------------------------------------------------------------
-- Read / insert / delete
-- ---------------------------------------------------------------------------

drop policy if exists "Authenticated read listings" on public.listings;
create policy "Authenticated read listings"
  on public.listings for select to authenticated
  using (true);

drop policy if exists "Users insert own listings" on public.listings;
create policy "Users insert own listings"
  on public.listings for insert to authenticated
  with check (posted_by = auth.uid());

drop policy if exists "Poster deletes own listings" on public.listings;
create policy "Poster deletes own listings"
  on public.listings for delete to authenticated
  using (posted_by = auth.uid());

-- ---------------------------------------------------------------------------
-- Update — split into focused policies (OR'd together)
-- ---------------------------------------------------------------------------

drop policy if exists "Participants update listings" on public.listings;
drop policy if exists "Anyone can claim available" on public.listings;
drop policy if exists "Listing handoff updates" on public.listings;
drop policy if exists "Poster updates own listings" on public.listings;
drop policy if exists "Claimer updates handoff" on public.listings;
drop policy if exists "Claim available listings" on public.listings;

-- Donor can always update their own row (complete, partial reopen, edit).
create policy "Poster updates own listings"
  on public.listings for update to authenticated
  using (posted_by = auth.uid())
  with check (posted_by = auth.uid());

-- Active picker can update while reserved; may complete (clears claimed_by).
create policy "Claimer updates handoff"
  on public.listings for update to authenticated
  using (claimed_by = auth.uid())
  with check (
    claimed_by = auth.uid()
    or claimed_by is null
    or lower(status) in ('picked_up', 'pickedup', 'collected', 'available', 'expired')
  );

-- Reserve an open listing.
create policy "Claim available listings"
  on public.listings for update to authenticated
  using (
    lower(status) = 'available'
    and claimed_by is null
    and posted_by <> auth.uid()
  )
  with check (
    claimed_by = auth.uid()
    and lower(status) in ('reserved', 'ready_for_pickup', 'ready_for_pickup')
  );

grant select, insert, update, delete on public.listings to authenticated;

-- ---------------------------------------------------------------------------
-- RPC helpers — bypass RLS safely for handoff completion (recommended path)
-- ---------------------------------------------------------------------------

create or replace function public.complete_listing_handoff(p_listing_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_posted_by uuid;
  v_claimed_by uuid;
begin
  select posted_by, claimed_by
  into v_posted_by, v_claimed_by
  from public.listings
  where id = p_listing_id
  for update;

  if not found then
    raise exception 'Listing not found';
  end if;

  if v_posted_by <> auth.uid() and v_claimed_by is distinct from auth.uid() then
    raise exception 'Not a participant on this listing';
  end if;

  update public.listings
  set status = 'picked_up',
      claimed_by = null,
      reserved_until = null,
      contact_instructions = null,
      pickup_deadline = now() - interval '1 minute'
  where id = p_listing_id;
end;
$$;

create or replace function public.reopen_listing_after_partial_handoff(
  p_listing_id uuid,
  p_details text,
  p_quantity text,
  p_contact_instructions text,
  p_pickup_deadline timestamptz
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_posted_by uuid;
  v_claimed_by uuid;
begin
  select posted_by, claimed_by
  into v_posted_by, v_claimed_by
  from public.listings
  where id = p_listing_id
  for update;

  if not found then
    raise exception 'Listing not found';
  end if;

  if v_posted_by <> auth.uid() and v_claimed_by is distinct from auth.uid() then
    raise exception 'Not a participant on this listing';
  end if;

  update public.listings
  set status = 'available',
      claimed_by = null,
      reserved_until = null,
      contact_instructions = p_contact_instructions,
      details = p_details,
      quantity = p_quantity,
      pickup_deadline = p_pickup_deadline
  where id = p_listing_id;
end;
$$;

revoke all on function public.complete_listing_handoff(uuid) from public;
revoke all on function public.reopen_listing_after_partial_handoff(uuid, text, text, text, timestamptz) from public;
grant execute on function public.complete_listing_handoff(uuid) to authenticated;
grant execute on function public.reopen_listing_after_partial_handoff(uuid, text, text, text, timestamptz) to authenticated;

-- Enable Realtime (Database → Replication) for:
--   public.listings
--   public.listing_messages
