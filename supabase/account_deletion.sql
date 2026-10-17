-- run in the supabase sql editor before deploying delete-account

begin;

create table if not exists public.account_deletion_requests (
  request_id uuid primary key,
  secret_hash text not null check (secret_hash ~ '^[0-9a-f]{64}$'),
  user_id uuid,
  status text not null default 'pending' check (status in ('pending', 'completed')),
  created_at timestamptz not null default now(),
  completed_at timestamptz,
  check ((status = 'pending' and user_id is not null) or (status = 'completed' and user_id is null))
);
create index if not exists account_deletion_user_idx on public.account_deletion_requests(user_id);
alter table public.account_deletion_requests enable row level security;
revoke all on public.account_deletion_requests from public, anon, authenticated;
grant select, insert, update, delete on public.account_deletion_requests to service_role;

create or replace function public.account_can_use_app()
returns boolean
language sql stable security definer
set search_path = public
as $$
  select auth.uid() is not null
    and exists (select 1 from auth.users where id = auth.uid())
    and not exists (
      select 1 from public.account_deletion_requests
      where user_id = auth.uid() and status = 'pending'
    );
$$;
revoke all on function public.account_can_use_app() from public;
grant execute on function public.account_can_use_app() to authenticated;

-- stop old app requests from adding data during or after deletion
create or replace function public.guard_account_write()
returns trigger
language plpgsql security definer
set search_path = public
as $$
begin
  if auth.role() = 'authenticated' and not public.account_can_use_app() then
    raise exception 'Account deletion is in progress' using errcode = '42501';
  end if;
  if auth.role() = 'authenticated' and tg_table_name = 'listings' and tg_op <> 'DELETE' then
    if exists (select 1 from public.account_deletion_requests
        where status = 'pending' and user_id in (new.posted_by, new.claimed_by)) then
      raise exception 'This listing is unavailable' using errcode = '42501';
    end if;
  end if;
  if tg_op = 'DELETE' then return old; end if;
  return new;
end;
$$;
revoke all on function public.guard_account_write() from public;

do $$
declare
  table_name text;
begin
  foreach table_name in array array[
    'listings', 'listing_reservations', 'listing_completions', 'listing_messages',
    'pantry_claims', 'device_tokens', 'user_blocks', 'listing_reports', 'listing_visibility'
  ] loop
    if to_regclass('public.' || table_name) is not null then
      execute format('drop policy if exists "Deleted accounts cannot access data" on public.%I', table_name);
      execute format('create policy "Deleted accounts cannot access data" on public.%I as restrictive
        for all to authenticated using (public.account_can_use_app())
        with check (public.account_can_use_app())', table_name);
      execute format('drop trigger if exists guard_account_write on public.%I', table_name);
      execute format('create trigger guard_account_write before insert or update or delete on public.%I
        for each row execute function public.guard_account_write()', table_name);
    end if;
  end loop;
end;
$$;

drop policy if exists "Deleted accounts cannot use storage" on storage.objects;
create policy "Deleted accounts cannot use storage" on storage.objects as restrictive
  for all to authenticated using (public.account_can_use_app())
  with check (public.account_can_use_app());

-- only the server can locate and delete a user's uploaded files
create or replace function public.account_deletion_photos(p_user_id uuid)
returns table(bucket_id text, name text)
language sql stable security definer
set search_path = public
as $$
  select o.bucket_id, o.name from storage.objects o
  where lower(coalesce(nullif(to_jsonb(o)->>'owner_id', ''), to_jsonb(o)->>'owner', '')) = p_user_id::text
     or (o.bucket_id = 'listing-photos' and lower(split_part(o.name, '/', 1)) = p_user_id::text)
  order by o.bucket_id, o.name limit 100;
$$;
revoke all on function public.account_deletion_photos(uuid) from public, anon, authenticated;
grant execute on function public.account_deletion_photos(uuid) to service_role;

create or replace function public.cleanup_account_data(p_user_id uuid)
returns void
language plpgsql security definer
set search_path = public
as $$
declare
  listing record;
  current_contact jsonb;
  provider_contact jsonb;
  original_contact text;
  total_packages integer;
  remaining_packages integer;
  reserved_packages integer;
  restored_details text;
  active_reservation boolean;
begin
  if auth.role() is distinct from 'service_role' then
    raise exception 'Server access required' using errcode = '42501';
  end if;
  if not exists (select 1 from public.account_deletion_requests
      where user_id = p_user_id and status = 'pending') then
    raise exception 'Deletion request missing';
  end if;
  perform pg_advisory_xact_lock(hashtextextended(p_user_id::text, 90318));

  for listing in select * from public.listings
    where claimed_by = p_user_id and posted_by <> p_user_id for update
  loop
    current_contact := '{}'::jsonb;
    provider_contact := '{}'::jsonb;
    begin
      current_contact := coalesce(listing.contact_instructions::jsonb, '{}'::jsonb);
    exception when invalid_text_representation then null;
    end;
    select provider_contact_instructions into original_contact
      from public.listing_reservations where listing_id = listing.id;
    begin
      provider_contact := coalesce(original_contact::jsonb, current_contact);
    exception when invalid_text_representation then provider_contact := current_contact;
    end;
    if jsonb_typeof(provider_contact) <> 'object' then provider_contact := '{}'::jsonb; end if;
    provider_contact := provider_contact || jsonb_build_object(
      'consumerDropOffAddress', '', 'consumerDropOffLatitude', null,
      'consumerDropOffLongitude', null, 'reservedPackageCount', null
    );

    active_reservation := lower(listing.status) in ('reserved', 'readyforpickup', 'ready_for_pickup');
    total_packages := coalesce(((regexp_match(listing.details, '(^|;)packages_total=([0-9]{1,9})(;|$)'))[2])::integer, 0);
    remaining_packages := coalesce(((regexp_match(listing.details, '(^|;)packages_remaining=([0-9]{1,9})(;|$)'))[2])::integer, 0);
    reserved_packages := case when active_reservation
      and (current_contact->>'reservedPackageCount') ~ '^[0-9]{1,9}$'
      then (current_contact->>'reservedPackageCount')::integer else 0 end;
    restored_details := listing.details;
    if total_packages > 0 and active_reservation then
      remaining_packages := least(total_packages, remaining_packages + reserved_packages);
      if restored_details ~ '(^|;)packages_remaining=' then
        restored_details := regexp_replace(restored_details, '(^|;)packages_remaining=[0-9]+',
          '\1packages_remaining=' || remaining_packages);
      else
        restored_details := concat_ws(';', nullif(restored_details, ''), 'packages_remaining=' || remaining_packages);
      end if;
    end if;

    update public.listings set claimed_by = null, reserved_until = null,
      status = case when active_reservation then
        case when pickup_deadline <= now() then 'expired' else 'available' end
        else status end,
      details = restored_details, contact_instructions = provider_contact::text
      where id = listing.id;
  end loop;

  if to_regclass('public.listing_reports') is not null then
    delete from public.listing_reports where reporter_id = p_user_id or reported_user_id = p_user_id
      or listing_id in (select id from public.listings where posted_by = p_user_id);
  end if;
  if to_regclass('public.listing_messages') is not null then
    delete from public.listing_messages where sender_id = p_user_id
      or listing_id in (select id from public.listings where posted_by = p_user_id);
  end if;
  delete from public.listing_reservations where reserver_id = p_user_id
    or listing_id in (select id from public.listings where posted_by = p_user_id);
  delete from public.listing_completions where consumer_id = p_user_id
    or listing_id in (select id from public.listings where posted_by = p_user_id);
  if to_regclass('public.pantry_claims') is not null then
    delete from public.pantry_claims where claimed_by = p_user_id;
  end if;
  if to_regclass('public.device_tokens') is not null then
    delete from public.device_tokens where user_id = p_user_id;
  end if;
  if to_regclass('public.user_blocks') is not null then
    delete from public.user_blocks where blocker_id = p_user_id or blocked_id = p_user_id;
  end if;
  update public.listings set waitlist_user_ids = array_remove(waitlist_user_ids, p_user_id)
    where p_user_id = any(waitlist_user_ids);
  delete from public.listings where posted_by = p_user_id;
end;
$$;
revoke all on function public.cleanup_account_data(uuid) from public, anon, authenticated;
grant execute on function public.cleanup_account_data(uuid) to service_role;

commit;
