-- run after listing_reports.sql and user_blocks.sql; safe to rerun

begin;

-- keep completed posts and existing bookings usable during the upgrade
do $$
begin
  if not exists (select 1 from information_schema.columns
      where table_schema = 'public' and table_name = 'listings' and column_name = 'moderation_status') then
    alter table public.listings add column moderation_status text not null default 'approved'
      check (moderation_status in ('pending', 'approved', 'rejected'));
  end if;
end;
$$;

alter table public.listings alter column moderation_status set default 'approved';
alter table public.listings add column if not exists moderation_reason text;
alter table public.listings add column if not exists moderation_version integer not null default 1;
alter table public.listings add column if not exists moderated_at timestamptz;
create index if not exists listings_moderation_queue_idx on public.listings(moderation_status, created_at);
create index if not exists listings_owner_created_idx on public.listings(posted_by, created_at);
create index if not exists listings_photo_idx on public.listings(photo_url) where photo_url is not null;
create index if not exists listing_reports_open_listing_idx on public.listing_reports(listing_id)
  where status in ('pending', 'in_review');

-- photos must be downloaded through the checked storage api
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('listing-photos', 'listing-photos', false, 5242880,
  array['image/jpeg', 'image/png', 'image/webp', 'image/heic'])
on conflict (id) do update set public = false, file_size_limit = 5242880,
  allowed_mime_types = excluded.allowed_mime_types;

create or replace function public.listing_has_reviewable_photo(p_owner uuid, p_path text)
returns boolean language sql stable security definer
set search_path = public
as $$
  with photo as (
    select split_part(regexp_replace(p_path,
      '^https?://[^/]+/storage/v1/object/(public|authenticated|sign)/listing-photos/', ''), '?', 1) as path
  )
  select coalesce(photo.path ~ ('^' || p_owner::text || '/[0-9a-f-]{36}\.jpg$'), false)
    and exists (select 1 from storage.objects o
      where o.bucket_id = 'listing-photos' and o.name = photo.path
        and coalesce(o.metadata->>'mimetype', '') = 'image/jpeg') from photo;
$$;
revoke all on function public.listing_has_reviewable_photo(uuid, text) from public, anon, authenticated;

-- compare provider notes without treating booking details as new public content
create or replace function public.listing_provider_note(p_contact text)
returns text language plpgsql immutable
set search_path = public
as $$
begin
  return coalesce((p_contact::jsonb)->>'providerNote', '');
exception when invalid_text_representation then
  return coalesce(p_contact, '');
end;
$$;
revoke all on function public.listing_provider_note(text) from public;

create or replace function public.listing_provider_content(p_contact text)
returns jsonb language plpgsql immutable
set search_path = public
as $$
begin
  return coalesce(p_contact::jsonb, '{}'::jsonb) - array[
    'consumerDropOffAddress', 'consumerDropOffLatitude', 'consumerDropOffLongitude', 'reservedPackageCount'];
exception when invalid_text_representation then
  return to_jsonb(coalesce(p_contact, ''));
end;
$$;
revoke all on function public.listing_provider_content(text) from public;

-- only suspicious text needs a person to review it
create or replace function public.listing_needs_review(p_title text, p_notes text, p_contact text)
returns boolean language sql immutable
set search_path = public
as $$
  select (coalesce(p_title, '') || ' ' || coalesce(p_notes, '') || ' ' || coalesce(p_contact, ''))
    ~* '(https?://|www[.]|[$][[:digit:]]|(^|[^[:alnum:]_])(venmo|cashapp|paypal|zelle|bitcoin|crypto|payment|pago|págame|porn|porno|nudes|desnudos|cocaine|cocaína|meth|drogas|weapon|armas|suicide)([^[:alnum:]_]|$))';
$$;
revoke all on function public.listing_needs_review(text, text, text) from public;

create or replace function public.guard_listing_moderation()
returns trigger language plpgsql security definer
set search_path = public
as $$
declare
  client_request boolean := coalesce(auth.role() in ('authenticated', 'anon'), false);
  content_changed boolean := false;
begin
  if client_request and (
      octet_length(coalesce(new.contact_instructions, '')) > 16000
      or char_length(coalesce(new.details, '')) > 1000
      or char_length(coalesce(new.quantity, '')) > 120
      or char_length(coalesce(new.pickup_address, '')) > 400) then
    raise exception 'moderation_content_too_large' using errcode = '22001';
  end if;
  if tg_op = 'UPDATE' then
    content_changed := row(new.title, new.pickup_notes, new.photo_url, new.area,
        new.pickup_address, new.latitude, new.longitude, new.category, new.quantity_size, new.pickup_type,
        public.listing_provider_content(new.contact_instructions))
      is distinct from row(old.title, old.pickup_notes, old.photo_url, old.area,
        old.pickup_address, old.latitude, old.longitude, old.category, old.quantity_size, old.pickup_type,
        public.listing_provider_content(old.contact_instructions));
    -- allow stock counts to change without accepting new unchecked text
    content_changed := content_changed
      or (new.details is distinct from old.details and not coalesce(new.details ~
        '^(dropoff_radius_meters=[0-9]+;)?packages_total=[0-9]+;packages_max=[0-9]+;packages_remaining=[0-9]+$', false))
      or (new.quantity is distinct from old.quantity and not coalesce(new.quantity ~
        '^[0-9]+ (package|packages|paquete|paquetes)( · (max [0-9]+ each|máx\.[ ]+[0-9]+ cada uno))?$', false));
    if client_request and (
        row(new.moderation_status, new.moderation_reason, new.moderation_version, new.moderated_at)
          is distinct from row(old.moderation_status, old.moderation_reason, old.moderation_version, old.moderated_at)
        or new.posted_by is distinct from old.posted_by
        or new.id is distinct from old.id or new.created_at is distinct from old.created_at) then
      raise exception 'moderation_server_only' using errcode = '42501';
    end if;
    if client_request and content_changed and old.moderation_status = 'approved' then
      raise exception 'moderation_content_locked' using errcode = '42501';
    end if;
    if client_request and old.moderation_status <> 'approved' and (
        new.claimed_by is not null or new.status in ('reserved', 'readyForPickup', 'ready_for_pickup', 'pickedUp', 'picked_up', 'collected')) then
      raise exception 'moderation_not_approved' using errcode = '42501';
    end if;
    if client_request and new.claimed_by is distinct from old.claimed_by
        and new.claimed_by is not null and new.pickup_deadline <= now() then
      raise exception 'moderation_listing_expired' using errcode = '42501';
    end if;
  end if;

  if tg_op = 'INSERT' or content_changed then
    if client_request then
      if auth.uid() is null or new.posted_by is distinct from auth.uid() then
        raise exception 'Authentication required' using errcode = '42501';
      end if;
      if char_length(trim(new.title)) not between 1 and 120
          or char_length(coalesce(new.pickup_notes, '')) > 1000
          or char_length(public.listing_provider_note(new.contact_instructions)) > 1000
          or char_length(coalesce(new.area, '')) > 200 then
        raise exception 'moderation_content_too_large' using errcode = '22001';
      end if;
      if not public.listing_has_reviewable_photo(new.posted_by, new.photo_url) then
        raise exception 'moderation_photo_required' using errcode = '22023';
      end if;
      if tg_op = 'INSERT' then
        if new.pickup_deadline <= now() or new.claimed_by is not null or new.status <> 'available' then
          raise exception 'moderation_invalid_submission' using errcode = '22023';
        end if;
        perform pg_advisory_xact_lock(hashtextextended(auth.uid()::text, 90319));
        if (select count(*) from public.listings where posted_by = auth.uid()
            and created_at > now() - interval '1 hour') >= 10 then
          raise exception 'moderation_rate_limited' using errcode = 'P0001';
        end if;
        new.created_at := now();
      end if;
    end if;
    new.moderation_status := case when public.listing_needs_review(
      new.title, new.pickup_notes, new.contact_instructions) then 'pending' else 'approved' end;
    new.moderation_reason := null;
    new.moderated_at := null;
    if tg_op = 'UPDATE' then
      new.moderation_version := old.moderation_version + 1;
    else
      new.moderation_version := 1;
    end if;
  end if;
  return new;
end;
$$;
revoke all on function public.guard_listing_moderation() from public;
drop trigger if exists guard_listing_moderation on public.listings;
create trigger guard_listing_moderation before insert or update on public.listings
  for each row execute function public.guard_listing_moderation();

alter table public.listings enable row level security;
drop policy if exists "Only approved listings are public" on public.listings;
create policy "Only approved listings are public" on public.listings as restrictive
  for select to authenticated
  using (moderation_status = 'approved' or posted_by = auth.uid() or claimed_by = auth.uid());
drop policy if exists "No unauthenticated listings" on public.listings;
create policy "No unauthenticated listings" on public.listings as restrictive
  for all to anon using (false) with check (false);

-- this small public signal removes cached posts without exposing their content
create table if not exists public.listing_visibility (
  listing_id uuid primary key references public.listings(id) on delete cascade,
  moderation_status text not null check (moderation_status in ('pending', 'approved', 'rejected')),
  updated_at timestamptz not null default now()
);
alter table public.listing_visibility enable row level security;
revoke all on public.listing_visibility from public, anon, authenticated;
grant select on public.listing_visibility to authenticated;
grant all on public.listing_visibility to service_role;
drop policy if exists "Read listing visibility" on public.listing_visibility;
create policy "Read listing visibility" on public.listing_visibility for select to authenticated using (true);

create or replace function public.publish_listing_visibility()
returns trigger language plpgsql security definer
set search_path = public
as $$
begin
  if tg_op = 'INSERT' or new.moderation_status is distinct from old.moderation_status then
    insert into public.listing_visibility(listing_id, moderation_status)
      values (new.id, new.moderation_status)
      on conflict (listing_id) do update set moderation_status = excluded.moderation_status, updated_at = now();
  end if;
  return new;
end;
$$;
revoke all on function public.publish_listing_visibility() from public;
drop trigger if exists publish_listing_visibility on public.listings;
create trigger publish_listing_visibility after insert or update on public.listings
  for each row execute function public.publish_listing_visibility();
insert into public.listing_visibility(listing_id, moderation_status)
  select id, moderation_status from public.listings
  on conflict (listing_id) do update set moderation_status = excluded.moderation_status, updated_at = now();

-- release ordinary posts left waiting by an earlier manual-review setup
update public.listings set moderation_status = 'approved', moderation_reason = null
where moderation_status = 'pending'
  and pickup_deadline > now()
  and status = 'available'
  and not public.listing_needs_review(title, pickup_notes, contact_instructions)
  and public.listing_has_reviewable_photo(posted_by, photo_url);

do $$
begin
  if exists (select 1 from pg_publication where pubname = 'supabase_realtime') then
    if not exists (select 1 from pg_publication_tables where pubname = 'supabase_realtime'
        and schemaname = 'public' and tablename = 'listing_visibility') then
      alter publication supabase_realtime add table public.listing_visibility;
    end if;
  end if;
  if to_regprocedure('public.account_can_use_app()') is not null then
    drop policy if exists "Deleted accounts cannot access data" on public.listing_visibility;
    create policy "Deleted accounts cannot access data" on public.listing_visibility as restrictive
      for select to authenticated using (public.account_can_use_app());
  end if;
end;
$$;

create or replace function public.can_read_listing_photo(p_path text)
returns boolean language sql stable security definer
set search_path = public
as $$
  select auth.uid() is not null and (
    split_part(p_path, '/', 1) = auth.uid()::text
    or exists (select 1 from public.listings l
      where l.moderation_status = 'approved' and (
        l.photo_url = p_path or l.photo_url like '%/listing-photos/' || p_path)
      and not public.users_are_blocked(auth.uid(), l.posted_by))
  );
$$;
revoke all on function public.can_read_listing_photo(text) from public, anon;
grant execute on function public.can_read_listing_photo(text) to authenticated;

create or replace function public.listing_photo_is_attached(p_path text)
returns boolean language sql stable security definer
set search_path = public
as $$
  select exists (select 1 from public.listings l
    where l.photo_url = p_path or l.photo_url like '%/listing-photos/' || p_path);
$$;
revoke all on function public.listing_photo_is_attached(text) from public, anon;
grant execute on function public.listing_photo_is_attached(text) to authenticated;

drop policy if exists "Review listing photos before sharing" on storage.objects;
create policy "Review listing photos before sharing" on storage.objects as restrictive for select to authenticated
  using (bucket_id <> 'listing-photos' or public.can_read_listing_photo(name));
drop policy if exists "No anonymous listing photos" on storage.objects;
create policy "No anonymous listing photos" on storage.objects as restrictive for all to anon
  using (bucket_id <> 'listing-photos') with check (bucket_id <> 'listing-photos');
drop policy if exists "Upload own listing photos" on storage.objects;
create policy "Upload own listing photos" on storage.objects for insert to authenticated
  with check (bucket_id = 'listing-photos' and name ~ ('^' || auth.uid()::text || '/[0-9a-f-]{36}\.jpg$'));
drop policy if exists "Listing photos need an owner" on storage.objects;
create policy "Listing photos need an owner" on storage.objects as restrictive for insert to authenticated
  with check (bucket_id <> 'listing-photos' or (
    name ~ ('^' || auth.uid()::text || '/[0-9a-f-]{36}\.jpg$')
    and not public.listing_photo_is_attached(name)));
drop policy if exists "Read reviewed or own listing photos" on storage.objects;
create policy "Read reviewed or own listing photos" on storage.objects for select to authenticated
  using (bucket_id = 'listing-photos' and public.can_read_listing_photo(name));
drop policy if exists "Listing photos cannot be overwritten" on storage.objects;
create policy "Listing photos cannot be overwritten" on storage.objects as restrictive for update to authenticated
  using (bucket_id <> 'listing-photos') with check (bucket_id <> 'listing-photos');
drop policy if exists "Keep attached listing photos" on storage.objects;
create policy "Keep attached listing photos" on storage.objects as restrictive for delete to authenticated
  using (bucket_id <> 'listing-photos' or (
    split_part(name, '/', 1) = auth.uid()::text and not public.listing_photo_is_attached(name)));
drop policy if exists "Remove unattached listing photos" on storage.objects;
create policy "Remove unattached listing photos" on storage.objects for delete to authenticated
  using (bucket_id = 'listing-photos' and split_part(name, '/', 1) = auth.uid()::text
    and not public.listing_photo_is_attached(name));

-- use this function from the sql editor or a trusted server, never the app
create or replace function public.moderate_listing(
  p_listing_id uuid, p_decision text, p_expected_version integer, p_reason text default null
)
returns void language plpgsql security definer
set search_path = public
as $$
declare
  listing public.listings%rowtype;
begin
  if p_decision is null or p_decision not in ('approved', 'rejected') or p_expected_version is null then
    raise exception 'Invalid moderation decision';
  end if;
  if p_decision = 'rejected' and nullif(trim(p_reason), '') is null then
    raise exception 'A short explanation is required';
  end if;
  if char_length(p_reason) > 1000 then raise exception 'Explanation is too long'; end if;
  select * into listing from public.listings where id = p_listing_id for update;
  if not found then raise exception 'Listing not found'; end if;
  if listing.moderation_version <> p_expected_version then
    raise exception 'Listing changed; review the latest text and photo';
  end if;
  if p_decision = 'approved' then
    if listing.pickup_deadline <= now() then raise exception 'Listing has expired'; end if;
    if not public.listing_has_reviewable_photo(listing.posted_by, listing.photo_url) then
      raise exception 'A private uploaded photo is required';
    end if;
  end if;
  update public.listings set moderation_status = p_decision,
    moderation_reason = case when p_decision = 'rejected' then trim(p_reason) else null end,
    moderated_at = now() where id = p_listing_id;
  update public.listing_reports set status = case when p_decision = 'rejected' then 'resolved' else 'dismissed' end,
    moderator_notes = coalesce(nullif(trim(p_reason), ''), 'Reviewed listing and photo'), reviewed_at = now()
    where listing_id = p_listing_id and status in ('pending', 'in_review');
end;
$$;
revoke all on function public.moderate_listing(uuid, text, integer, text) from public, anon, authenticated;
grant execute on function public.moderate_listing(uuid, text, integer, text) to service_role;

-- only moderators can read this queue and its private notes
create or replace view public.listing_moderation_queue as
select l.id, l.title, l.details, l.pickup_notes, l.contact_instructions, l.photo_url, l.posted_by,
  l.created_at, l.pickup_deadline, l.moderation_status, l.moderation_version, l.moderation_reason,
  (select count(*) from public.listing_reports r
    where r.listing_id = l.id and r.status in ('pending', 'in_review')) as open_reports
from public.listings l
where (l.moderation_status = 'pending' and l.pickup_deadline > now())
  or exists (select 1 from public.listing_reports r
    where r.listing_id = l.id and r.status in ('pending', 'in_review'));
revoke all on public.listing_moderation_queue from public, anon, authenticated;
grant select on public.listing_moderation_queue to service_role;

-- stop messages on content that has been removed, including older app builds
create or replace function public.guard_moderated_listing_message()
returns trigger language plpgsql security definer
set search_path = public
as $$
begin
  if auth.role() = 'authenticated' and not exists (
      select 1 from public.listings where id = new.listing_id and moderation_status = 'approved') then
    raise exception 'moderation_not_approved' using errcode = '42501';
  end if;
  return new;
end;
$$;
revoke all on function public.guard_moderated_listing_message() from public;
do $$
begin
  if to_regclass('public.listing_messages') is not null then
    drop trigger if exists guard_moderated_listing_message on public.listing_messages;
    create trigger guard_moderated_listing_message before insert or update on public.listing_messages
      for each row execute function public.guard_moderated_listing_message();
  end if;
end;
$$;

commit;
