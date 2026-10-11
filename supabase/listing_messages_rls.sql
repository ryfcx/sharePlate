-- listing messages rls, run after creating listing messages

alter table public.listing_messages enable row level security;

-- bypass listings rls when checking participation
create or replace function public.is_listing_message_participant(target_listing_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1
    from public.listings l
    where l.id = target_listing_id
      and (
        l.posted_by = auth.uid()
        or l.claimed_by = auth.uid()
      )
  );
$$;

revoke all on function public.is_listing_message_participant(uuid) from public;
grant execute on function public.is_listing_message_participant(uuid) to authenticated;

drop policy if exists "Participants read messages" on public.listing_messages;
create policy "Participants read messages"
  on public.listing_messages for select to authenticated
  using (public.is_listing_message_participant(listing_id));

drop policy if exists "Participants send messages" on public.listing_messages;
create policy "Participants send messages"
  on public.listing_messages for insert to authenticated
  with check (
    sender_id = auth.uid()
    and public.is_listing_message_participant(listing_id)
  );

grant select, insert on public.listing_messages to authenticated;
