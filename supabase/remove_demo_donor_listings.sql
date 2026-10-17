-- run once in the supabase sql editor to remove shareplate demo listings
-- and stop the scheduled donor listing generator.

do $$
declare
  scheduled_job record;
begin
  if to_regclass('cron.job') is not null then
    for scheduled_job in
      select jobid from cron.job where jobname = 'maintain-donor-listings'
    loop
      perform cron.unschedule(scheduled_job.jobid);
    end loop;
  end if;
end;
$$;

delete from public.listings as listing
where listing.id in (
    'a15a0001-0000-4000-8000-000000000001',
    'a15a0001-0000-4000-8000-000000000002',
    'a15a0001-0000-4000-8000-000000000003',
    'a15a0001-0000-4000-8000-000000000004',
    'a15a0001-0000-4000-8000-000000000005',
    'a15a0001-0000-4000-8000-000000000006',
    'a15a0001-0000-4000-8000-000000000007',
    'a15a0001-0000-4000-8000-000000000008',
    'a15a0001-0000-4000-8000-000000000009',
    'a15a0001-0000-4000-8000-000000000010',
    'a15a0001-0000-4000-8000-000000000011',
    'a15a0001-0000-4000-8000-000000000012',
    'a15a0001-0000-4000-8000-000000000013',
    'a15a0001-0000-4000-8000-000000000014',
    'a15a0001-0000-4000-8000-000000000015'
  )
  or listing.is_auto_donor = true
  or listing.details like '%demo_seed=shareplate_chicago_demo_v1%'
  or listing.posted_by in (
    select id
    from auth.users
    where coalesce(raw_user_meta_data->>'shareplate_auto_donor', '') = 'true'
       or coalesce(raw_user_meta_data->>'shareplate_demo_user', '') = 'true'
  );

drop function if exists public.maintain_donor_listings();
