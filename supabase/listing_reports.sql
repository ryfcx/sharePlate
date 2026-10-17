-- run once in the supabase sql editor; safe to rerun

begin;

-- keep evidence if a listing is removed during moderation
create table if not exists public.listing_reports (
  id uuid primary key default gen_random_uuid(),
  listing_id uuid not null,
  reporter_id uuid references auth.users(id) on delete set null,
  reported_user_id uuid references auth.users(id) on delete set null,
  reason text not null check (reason in ('spam', 'fake', 'unsafeFood', 'inappropriate')),
  notes text check (char_length(notes) <= 1000),
  listing_snapshot jsonb not null,
  status text not null default 'pending'
    check (status in ('pending', 'in_review', 'resolved', 'dismissed')),
  moderator_notes text check (char_length(moderator_notes) <= 2000),
  created_at timestamptz not null default now(),
  reviewed_at timestamptz,
  unique (reporter_id, listing_id)
);

create index if not exists listing_reports_queue_idx on public.listing_reports(status, created_at);
create index if not exists listing_reports_reporter_time_idx on public.listing_reports(reporter_id, created_at);
alter table public.listing_reports enable row level security;

-- reports are private; the app can only submit through the checked rpc
revoke all on public.listing_reports from public, anon, authenticated;
grant select, update, delete on public.listing_reports to service_role;

create or replace function public.submit_listing_report(
  p_listing_id uuid,
  p_reason text,
  p_notes text default null
)
returns uuid
language plpgsql security definer
set search_path = public
as $$
declare
  v_reporter uuid := auth.uid();
  v_listing record;
  v_report_id uuid;
  v_notes text := nullif(trim(p_notes), '');
begin
  if v_reporter is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;
  if p_reason is null or p_reason not in ('spam', 'fake', 'unsafeFood', 'inappropriate') then
    raise exception 'Invalid report reason' using errcode = '22023';
  end if;
  if char_length(v_notes) > 1000 then
    raise exception 'report_notes_too_long' using errcode = '22001';
  end if;

  -- serialize submissions by this account, including retries
  perform pg_advisory_xact_lock(hashtextextended(v_reporter::text, 90317));
  select id into v_report_id from public.listing_reports
    where reporter_id = v_reporter and listing_id = p_listing_id;
  if found then return v_report_id; end if;

  select id, posted_by, title, details, photo_url, pickup_notes, created_at
    into v_listing from public.listings where id = p_listing_id;
  if not found then
    raise exception 'report_listing_unavailable' using errcode = 'P0001';
  end if;
  if v_listing.posted_by = v_reporter then
    raise exception 'report_own_listing' using errcode = 'P0001';
  end if;
  if (select count(*) from public.listing_reports
      where reporter_id = v_reporter and created_at > now() - interval '1 hour') >= 10 then
    raise exception 'report_rate_limited' using errcode = 'P0001';
  end if;

  insert into public.listing_reports (
    listing_id, reporter_id, reported_user_id, reason, notes, listing_snapshot
  ) values (
    v_listing.id, v_reporter, v_listing.posted_by, p_reason, v_notes,
    jsonb_build_object(
      'title', v_listing.title,
      'details', v_listing.details,
      'photo_url', v_listing.photo_url,
      'pickup_notes', v_listing.pickup_notes,
      'created_at', v_listing.created_at
    )
  ) returning id into v_report_id;
  return v_report_id;
end;
$$;

revoke all on function public.submit_listing_report(uuid, text, text) from public, anon;
grant execute on function public.submit_listing_report(uuid, text, text) to authenticated;

create or replace function public.stamp_report_review()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  if new.status is distinct from old.status then
    new.reviewed_at := case when new.status in ('resolved', 'dismissed') then now() else null end;
  end if;
  return new;
end;
$$;
revoke all on function public.stamp_report_review() from public;
drop trigger if exists stamp_report_review on public.listing_reports;
create trigger stamp_report_review before update of status on public.listing_reports
  for each row execute function public.stamp_report_review();

commit;
