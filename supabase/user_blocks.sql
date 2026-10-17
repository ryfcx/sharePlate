-- run after listings_rls.sql in the supabase sql editor

begin;

create table if not exists public.user_blocks (
  blocker_id uuid not null references auth.users(id) on delete cascade,
  blocked_id uuid not null references auth.users(id) on delete cascade,
  display_name text not null default 'Neighbor' check (char_length(display_name) <= 50),
  created_at timestamptz not null default now(),
  primary key (blocker_id, blocked_id),
  check (blocker_id <> blocked_id)
);

create index if not exists user_blocks_blocked_id_idx on public.user_blocks(blocked_id);
alter table public.user_blocks enable row level security;

drop policy if exists "Users read own blocks" on public.user_blocks;
create policy "Users read own blocks" on public.user_blocks
  for select to authenticated using (blocker_id = auth.uid());
drop policy if exists "Users add own blocks" on public.user_blocks;
create policy "Users add own blocks" on public.user_blocks
  for insert to authenticated with check (blocker_id = auth.uid());
drop policy if exists "Users update own blocks" on public.user_blocks;
create policy "Users update own blocks" on public.user_blocks
  for update to authenticated using (blocker_id = auth.uid())
  with check (blocker_id = auth.uid());
drop policy if exists "Users remove own blocks" on public.user_blocks;
create policy "Users remove own blocks" on public.user_blocks
  for delete to authenticated using (blocker_id = auth.uid());

grant select, insert, update, delete on public.user_blocks to authenticated;
grant select on public.user_blocks to service_role;
revoke all on public.user_blocks from anon;

-- check both directions without exposing another person's block list
create or replace function public.users_are_blocked(first_user uuid, second_user uuid)
returns boolean
language sql stable security definer
set search_path = public
as $$
  select (auth.uid() in (first_user, second_user) or auth.role() = 'service_role')
    and exists (
      select 1 from public.user_blocks b
      where (b.blocker_id = first_user and b.blocked_id = second_user)
         or (b.blocker_id = second_user and b.blocked_id = first_user)
    );
$$;
revoke all on function public.users_are_blocked(uuid, uuid) from public;
grant execute on function public.users_are_blocked(uuid, uuid) to authenticated, service_role;

-- keep current handoffs accessible so they can still be finished
drop policy if exists "Hide blocked listings" on public.listings;
create policy "Hide blocked listings" on public.listings as restrictive
  for select to authenticated
  using (
    posted_by = auth.uid()
    or claimed_by = auth.uid()
    or not public.users_are_blocked(auth.uid(), posted_by)
  );

-- triggers also protect reservations made through security definer rpcs
create or replace function public.prevent_blocked_reservation()
returns trigger
language plpgsql security definer
set search_path = public
as $$
begin
  if new.claimed_by is null then return new; end if;
  if tg_op = 'UPDATE' then
    if new.claimed_by is not distinct from old.claimed_by then return new; end if;
  end if;
  if exists (
    select 1 from public.user_blocks b
    where (b.blocker_id = new.posted_by and b.blocked_id = new.claimed_by)
       or (b.blocker_id = new.claimed_by and b.blocked_id = new.posted_by)
  ) then
    raise exception 'This reservation is unavailable.' using errcode = '42501';
  end if;
  return new;
end;
$$;
revoke all on function public.prevent_blocked_reservation() from public;
drop trigger if exists prevent_blocked_reservation on public.listings;
create trigger prevent_blocked_reservation
  before insert or update of claimed_by on public.listings
  for each row execute function public.prevent_blocked_reservation();

create or replace function public.can_message_listing(target_listing_id uuid)
returns boolean
language sql stable security definer
set search_path = public
as $$
  select exists (
    select 1 from public.listings l
    where l.id = target_listing_id
      and auth.uid() in (l.posted_by, l.claimed_by)
      and not exists (
        select 1 from public.user_blocks b
        where (b.blocker_id = l.posted_by and b.blocked_id = l.claimed_by)
           or (b.blocker_id = l.claimed_by and b.blocked_id = l.posted_by)
      )
  );
$$;
revoke all on function public.can_message_listing(uuid) from public;
grant execute on function public.can_message_listing(uuid) to authenticated;

create or replace function public.prevent_blocked_message()
returns trigger
language plpgsql security definer
set search_path = public
as $$
begin
  if exists (
    select 1 from public.listings l
    join public.user_blocks b
      on (b.blocker_id = l.posted_by and b.blocked_id = l.claimed_by)
      or (b.blocker_id = l.claimed_by and b.blocked_id = l.posted_by)
    where l.id = new.listing_id
  ) then
    raise exception 'Messages are unavailable.' using errcode = '42501';
  end if;
  return new;
end;
$$;
revoke all on function public.prevent_blocked_message() from public;

-- messaging is optional; apply these protections when its table exists
do $$
begin
  if to_regclass('public.listing_messages') is not null then
    execute 'drop trigger if exists prevent_blocked_message on public.listing_messages';
    execute 'create trigger prevent_blocked_message before insert on public.listing_messages
      for each row execute function public.prevent_blocked_message()';
    execute 'drop policy if exists "Blocked users cannot read messages" on public.listing_messages';
    execute 'create policy "Blocked users cannot read messages" on public.listing_messages as restrictive
      for select to authenticated using (public.can_message_listing(listing_id))';
    execute 'drop policy if exists "Blocked users cannot send messages" on public.listing_messages';
    execute 'create policy "Blocked users cannot send messages" on public.listing_messages as restrictive
      for insert to authenticated with check (public.can_message_listing(listing_id))';
  end if;
end;
$$;

commit;
