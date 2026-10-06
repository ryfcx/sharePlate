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

grant select, insert, update, delete on public.listings to authenticated;
grant select, insert, update, delete on public.listings to service_role;

-- ---------------------------------------------------------------------------
-- Private reservation details — visible only to the reserver and provider
-- ---------------------------------------------------------------------------

create table if not exists public.listing_reservations (
  listing_id uuid primary key references public.listings(id) on delete cascade,
  reserver_id uuid not null references auth.users(id) on delete cascade,
  reserver_display_name text not null,
  provider_contact_instructions text,
  reserved_at timestamptz not null default now()
);

alter table public.listing_reservations
  add column if not exists provider_contact_instructions text;

alter table public.listing_reservations enable row level security;

drop policy if exists "Participants read reservation details" on public.listing_reservations;
create policy "Participants read reservation details"
  on public.listing_reservations for select to authenticated
  using (
    reserver_id = auth.uid()
    or exists (
      select 1
      from public.listings l
      where l.id = listing_id and l.posted_by = auth.uid()
    )
  );

grant select on public.listing_reservations to authenticated;
revoke insert, update, delete on public.listing_reservations from authenticated;

-- Records which consumers completed a pickup from a multi-package listing.
-- Consumers can read only their own history; the reserve RPC uses it to prevent
-- the same person from taking another allocation from the same listing.
create table if not exists public.listing_completions (
  listing_id uuid not null references public.listings(id) on delete cascade,
  consumer_id uuid not null references auth.users(id) on delete cascade,
  completed_at timestamptz not null default now(),
  primary key (listing_id, consumer_id)
);

alter table public.listing_completions enable row level security;

drop policy if exists "Consumers read own completed listings" on public.listing_completions;
create policy "Consumers read own completed listings"
  on public.listing_completions for select to authenticated
  using (consumer_id = auth.uid());

grant select on public.listing_completions to authenticated;
revoke insert, update, delete on public.listing_completions from authenticated;

-- ---------------------------------------------------------------------------
-- RPC helpers — constrain non-owner writes to handoff-specific columns
-- ---------------------------------------------------------------------------

drop function if exists public.reserve_listing(uuid, text, text, text, timestamptz);
create or replace function public.reserve_listing(
  p_listing_id uuid,
  p_details text,
  p_quantity text,
  p_contact_instructions text,
  p_reserved_until timestamptz,
  p_reserver_name text
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_provider_contact_instructions text;
begin
  if auth.uid() is null then
    raise exception 'Authentication required';
  end if;

  select contact_instructions
  into v_provider_contact_instructions
  from public.listings
  where id = p_listing_id
  for update;

  update public.listings
  set status = 'reserved',
      claimed_by = auth.uid(),
      reserved_until = least(p_reserved_until, pickup_deadline),
      contact_instructions = p_contact_instructions,
      details = p_details,
      quantity = p_quantity
  where id = p_listing_id
    and lower(status) = 'available'
    and claimed_by is null
    and posted_by <> auth.uid()
    and not exists (
      select 1
      from public.listing_completions c
      where c.listing_id = p_listing_id
        and c.consumer_id = auth.uid()
    )
    -- Legacy listings may have no package metadata. When an explicit remaining
    -- count exists, never let a stale or modified client reserve zero stock.
    and details !~ '(^|;)packages_remaining=0(;|$)';

  if not found then
    raise exception 'Listing is no longer available';
  end if;

  insert into public.listing_reservations (
    listing_id,
    reserver_id,
    reserver_display_name,
    provider_contact_instructions
  )
  values (
    p_listing_id,
    auth.uid(),
    left(coalesce(nullif(trim(p_reserver_name), ''), 'Neighbor'), 50),
    v_provider_contact_instructions
  )
  on conflict (listing_id) do update
  set reserver_id = excluded.reserver_id,
      reserver_display_name = excluded.reserver_display_name,
      provider_contact_instructions = excluded.provider_contact_instructions,
      reserved_at = now();
end;
$$;

create or replace function public.release_listing_reservation(
  p_listing_id uuid,
  p_details text,
  p_quantity text,
  p_contact_instructions text,
  p_waitlist_user_ids uuid[]
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_claimed_by uuid;
  v_status text;
begin
  if auth.uid() is null then
    raise exception 'Authentication required';
  end if;

  select claimed_by, lower(status)
  into v_claimed_by, v_status
  from public.listings
  where id = p_listing_id
  for update;

  if not found then
    raise exception 'Listing not found';
  end if;

  if v_claimed_by is distinct from auth.uid() then
    raise exception 'Only the reserver can release this reservation';
  end if;

  if v_status not in ('reserved', 'ready_for_pickup') then
    raise exception 'Listing does not have an active reservation';
  end if;

  update public.listings
  set status = 'available',
      claimed_by = null,
      reserved_until = null,
      contact_instructions = p_contact_instructions,
      details = p_details,
      quantity = p_quantity,
      waitlist_user_ids = coalesce(p_waitlist_user_ids, '{}'::uuid[])
  where id = p_listing_id;

  delete from public.listing_reservations where listing_id = p_listing_id;
end;
$$;

create or replace function public.complete_listing_handoff(p_listing_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_posted_by uuid;
  v_claimed_by uuid;
  v_details text;
  v_provider_contact_instructions text;
  v_remaining integer;
begin
  select l.posted_by,
         l.claimed_by,
         l.details,
         r.provider_contact_instructions
  into v_posted_by,
       v_claimed_by,
       v_details,
       v_provider_contact_instructions
  from public.listings l
  left join public.listing_reservations r on r.listing_id = l.id
  where l.id = p_listing_id
  for update of l;

  if not found then
    raise exception 'Listing not found';
  end if;

  if v_posted_by <> auth.uid() and v_claimed_by is distinct from auth.uid() then
    raise exception 'Not a participant on this listing';
  end if;

  if v_claimed_by is not null then
    insert into public.listing_completions (listing_id, consumer_id)
    values (p_listing_id, v_claimed_by)
    on conflict (listing_id, consumer_id) do nothing;
  end if;

  v_remaining := coalesce(
    ((regexp_match(v_details, '(^|;)packages_remaining=([0-9]+)(;|$)'))[2])::integer,
    0
  );

  if v_claimed_by is not null and v_remaining > 0 then
    -- Finish only this consumer's allocation. Remaining packages immediately
    -- become available to other consumers under the original provider details.
    update public.listings
    set status = 'available',
        claimed_by = null,
        reserved_until = null,
        contact_instructions = v_provider_contact_instructions
    where id = p_listing_id;
  else
    -- No stock remains, or the provider is closing an unreserved listing.
    update public.listings
    set status = 'picked_up',
        claimed_by = null,
        reserved_until = null,
        contact_instructions = null,
        pickup_deadline = now() - interval '1 minute'
    where id = p_listing_id;
  end if;

  delete from public.listing_reservations where listing_id = p_listing_id;
end;
$$;

-- Backward-compatible name used by older app builds.
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
begin
  perform public.complete_listing_handoff(p_listing_id);
end;
$$;

revoke all on function public.reserve_listing(uuid, text, text, text, timestamptz, text) from public;
revoke all on function public.release_listing_reservation(uuid, text, text, text, uuid[]) from public;
revoke all on function public.complete_listing_handoff(uuid) from public;
revoke all on function public.reopen_listing_after_partial_handoff(uuid, text, text, text, timestamptz) from public;
grant execute on function public.reserve_listing(uuid, text, text, text, timestamptz, text) to authenticated;
grant execute on function public.release_listing_reservation(uuid, text, text, text, uuid[]) to authenticated;
grant execute on function public.complete_listing_handoff(uuid) to authenticated;
grant execute on function public.reopen_listing_after_partial_handoff(uuid, text, text, text, timestamptz) to authenticated;

-- Enable Realtime so open consumer apps see new posts immediately.
do $$
begin
  alter publication supabase_realtime add table public.listings;
exception
  when duplicate_object then null;
end $$;
