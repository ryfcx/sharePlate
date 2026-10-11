-- permanent lincoln park listings, run whole file once in sql editor
--
-- replaces old every minute rotation with 15 fixed lincoln park spots
-- these are neighbor donations, grocery spots, and restaurants
-- grocery and restaurant spots have 100 packages
-- neighbor donations are smaller and do not expire or move
-- hourly job puts one back if picked up or deleted
-- a listing being reserved is left alone

create extension if not exists pgcrypto;

alter table public.listings
  add column if not exists is_auto_donor boolean not null default false;

--
-- system poster, listings need a real auth user for posted by
--

do $$
declare
  v_user_id uuid := 'a15a0000-0000-4000-8000-000000000015';
  v_email text := 'shareplate.auto.donor@example.com';
begin
  if exists (select 1 from auth.users where id = v_user_id or email = v_email) then
    update auth.users
    set raw_user_meta_data = coalesce(raw_user_meta_data, '{}'::jsonb)
          || jsonb_build_object('display_name', 'Neighbor', 'shareplate_auto_donor', true)
    where id = v_user_id or email = v_email;
    return;
  end if;

  insert into auth.users (
    instance_id,
    id,
    aud,
    role,
    email,
    encrypted_password,
    email_confirmed_at,
    raw_app_meta_data,
    raw_user_meta_data,
    created_at,
    updated_at,
    confirmation_token,
    recovery_token,
    email_change_token_new,
    email_change
  ) values (
    '00000000-0000-0000-0000-000000000000',
    v_user_id,
    'authenticated',
    'authenticated',
    v_email,
    crypt('shareplate-auto-donor', gen_salt('bf')),
    now(),
    '{"provider":"email","providers":["email"]}'::jsonb,
    jsonb_build_object('display_name', 'Neighbor', 'shareplate_auto_donor', true),
    now(),
    now(),
    '',
    '',
    '',
    ''
  );

  insert into auth.identities (
    id,
    user_id,
    identity_data,
    provider,
    provider_id,
    last_sign_in_at,
    created_at,
    updated_at
  ) values (
    gen_random_uuid(),
    v_user_id,
    jsonb_build_object('sub', v_user_id::text, 'email', v_email),
    'email',
    v_user_id::text,
    now(),
    now(),
    now()
  );
end $$;

--
-- keep the 15 lincoln park spots in place
--

create or replace function public.maintain_donor_listings()
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_poster uuid;
  v_deadline constant timestamptz := '2099-01-01 00:00:00+00';
  v_row record;
  v_active boolean;
begin
  if not pg_try_advisory_lock(15015) then
    return;
  end if;

  begin
    select id into v_poster
    from auth.users
    where coalesce(raw_user_meta_data->>'shareplate_auto_donor', '') = 'true'
    order by created_at
    limit 1;

    if v_poster is null then
      raise exception 'Auto donor user is missing';
    end if;

    update public.listings
    set status = 'expired'
    where status = 'available'
      and claimed_by is null
      and pickup_deadline <= now()
      and posted_by is distinct from v_poster
      and not is_auto_donor;

    delete from public.listings
    where (is_auto_donor or posted_by = v_poster)
      and id not in (
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
      );

    for v_row in
      select *
      from (
        values
          (
            'a15a0001-0000-4000-8000-000000000001'::uuid,
            'Extra garden vegetables', 'other', 4, 'feeds3to5', 'porch',
            '2200 N Cannon Dr, Chicago', 41.9217, -87.6336,
            'Extra from a neighbor''s garden.', 'outside', null::integer
          ),
          (
            'a15a0001-0000-4000-8000-000000000002'::uuid,
            'Extra bakery bread', 'bakery', 100, 'feeds10plus', 'communityFridge',
            '2600 N Clark St, Chicago', 41.9304, -87.6432,
            'Wrapped loaves, ready to share.', 'curb', 1
          ),
          (
            'a15a0001-0000-4000-8000-000000000003'::uuid,
            'Armitage Pasta Kitchen', 'preparedMeals', 100, 'feeds10plus', 'lobby',
            '1000 W Armitage Ave, Chicago', 41.9184, -87.6488,
            'Restaurant surplus from tonight''s service.', 'outside', null
          ),
          (
            'a15a0001-0000-4000-8000-000000000004'::uuid,
            'Homemade cookies', 'other', 3, 'feeds3to5', 'meetOutside',
            '2300 N Seminary Ave, Chicago', 41.9238, -87.6554,
            'Baked this afternoon. A neighbor is sharing the extras.', 'outside', null
          ),
          (
            'a15a0001-0000-4000-8000-000000000005'::uuid,
            'Racine Taco Spot', 'preparedMeals', 100, 'feeds10plus', 'communityFridge',
            '1200 W Armitage Ave, Chicago', 41.9180, -87.6586,
            'Restaurant surplus. Tacos packed to go.', 'curb', 1
          ),
          (
            'a15a0001-0000-4000-8000-000000000006'::uuid,
            'Lakeview Noodle Shop', 'preparedMeals', 100, 'feeds10plus', 'frontDesk',
            '2400 N Lakeview Ave, Chicago', 41.9258, -87.6392,
            'Restaurant surplus. Noodle bowls, keep warm.', 'outside', null
          ),
          (
            'a15a0001-0000-4000-8000-000000000007'::uuid,
            'Leftover snacks', 'other', 2, 'feeds1to2', 'communityFridge',
            '1700 N Halsted St, Chicago', 41.9136, -87.6486,
            'Unopened snacks a neighbor can''t finish.', 'curb', 1
          ),
          (
            'a15a0001-0000-4000-8000-000000000008'::uuid,
            'Homemade vegetable soup', 'other', 2, 'feeds1to2', 'porch',
            '1550 N Larrabee St, Chicago', 41.9112, -87.6432,
            'A neighbor cooked extra. Keep refrigerated.', 'outside', null
          ),
          (
            'a15a0001-0000-4000-8000-000000000009'::uuid,
            'Day-old pastries', 'bakery', 100, 'feeds10plus', 'communityFridge',
            '2800 N Mildred Ave, Chicago', 41.9322, -87.6562,
            'Fine today. Please take a box.', 'curb', 1
          ),
          (
            'a15a0001-0000-4000-8000-000000000010'::uuid,
            'Harbor Sandwich House', 'preparedMeals', 100, 'feeds10plus', 'meetOutside',
            '2800 N Lake Shore Dr, Chicago', 41.9332, -87.6308,
            'Restaurant surplus. Sandwich trays from lunch service.', 'outside', null
          ),
          (
            'a15a0001-0000-4000-8000-000000000011'::uuid,
            'Extra kids'' lunches', 'other', 3, 'feeds1to2', 'porch',
            '2300 N Orchard St, Chicago', 41.9236, -87.6474,
            'Packed lunches a family is sharing.', 'outside', null
          ),
          (
            'a15a0001-0000-4000-8000-000000000012'::uuid,
            'Spare canned goods', 'other', 4, 'feeds3to5', 'communityFridge',
            '800 W Wrightwood Ave, Chicago', 41.9306, -87.6496,
            'Unopened cans from a neighbor''s cupboard.', 'curb', 1
          ),
          (
            'a15a0001-0000-4000-8000-000000000013'::uuid,
            'Bagels', 'bakery', 100, 'feeds10plus', 'lobby',
            '2200 N Larrabee St, Chicago', 41.9212, -87.6438,
            'Bagged this morning.', 'outside', null
          ),
          (
            'a15a0001-0000-4000-8000-000000000014'::uuid,
            'Clark Street Grill', 'preparedMeals', 100, 'feeds10plus', 'meetOutside',
            '1600 N Clark St, Chicago', 41.9116, -87.6318,
            'Restaurant surplus from the grill.', 'outside', null
          ),
          (
            'a15a0001-0000-4000-8000-000000000015'::uuid,
            'Yogurt cups', 'drinks', 100, 'feeds10plus', 'frontDesk',
            '1600 N Sedgwick St, Chicago', 41.9110, -87.6386,
            'Keep cold.', 'outside', null
          )
      ) as spot(
        id, title, category, packages, size, pickup_type,
        address, latitude, longitude, note, spot, radius_miles
      )
    loop
      select
        status in ('reserved', 'readyForPickup', 'ready_for_pickup')
        and claimed_by is not null
      into v_active
      from public.listings
      where id = v_row.id;

      v_active := coalesce(v_active, false);

      insert into public.listings (
        id,
        title,
        details,
        quantity,
        category,
        quantity_size,
        pickup_type,
        area,
        photo_url,
        pickup_address,
        latitude,
        longitude,
        pickup_deadline,
        pickup_notes,
        contact_instructions,
        status,
        posted_by,
        claimed_by,
        reserved_until,
        waitlist_user_ids,
        pantry_gcfd_location_id,
        is_auto_donor
      ) values (
        v_row.id,
        v_row.title,
        format(
          'packages_total=%s;packages_max=%s;packages_remaining=%s%s',
          v_row.packages,
          v_row.packages,
          v_row.packages,
          case
            when v_row.radius_miles is null then ''
            else format(';dropoff_radius_meters=%s', v_row.radius_miles * 1609)
          end
        ),
        case
          when v_row.packages = 1 then '1 package'
          else v_row.packages::text || ' packages'
        end,
        v_row.category,
        v_row.size,
        v_row.pickup_type,
        'Lincoln Park',
        null,
        v_row.address,
        v_row.latitude,
        v_row.longitude,
        v_deadline,
        v_row.note,
        jsonb_build_object(
          'meetupAddress', v_row.address,
          'handoffSpot', v_row.spot,
          'timeslot', '2099-01-01T00:00:00Z',
          'meetupLatitude', v_row.latitude,
          'meetupLongitude', v_row.longitude,
          'providerNote', v_row.note,
          'consumerDropOffAddress', '',
          'instructionsPublished', true
        )::text,
        'available',
        v_poster,
        null,
        null,
        '{}'::uuid[],
        null,
        true
      )
      on conflict (id) do update
      set
        title = excluded.title,
        details = case when v_active then public.listings.details else excluded.details end,
        quantity = excluded.quantity,
        category = excluded.category,
        quantity_size = excluded.quantity_size,
        pickup_type = excluded.pickup_type,
        area = excluded.area,
        pickup_address = excluded.pickup_address,
        latitude = excluded.latitude,
        longitude = excluded.longitude,
        pickup_deadline = excluded.pickup_deadline,
        pickup_notes = excluded.pickup_notes,
        contact_instructions = case
          when v_active then public.listings.contact_instructions
          else excluded.contact_instructions
        end,
        status = case when v_active then public.listings.status else 'available' end,
        claimed_by = case when v_active then public.listings.claimed_by else null end,
        reserved_until = case when v_active then public.listings.reserved_until else null end,
        is_auto_donor = true
      where public.listings.posted_by = v_poster
         or public.listings.is_auto_donor;
    end loop;

    perform pg_advisory_unlock(15015);
  exception
    when others then
      perform pg_advisory_unlock(15015);
      raise;
  end;
end;
$$;

revoke all on function public.maintain_donor_listings() from public;
grant execute on function public.maintain_donor_listings() to service_role;

-- stop the every minute rotation, checks hourly that 15 are still there

do $$
begin
  perform cron.unschedule('maintain-donor-listings');
exception
  when others then null;
end $$;

select cron.schedule(
  'maintain-donor-listings',
  '0 * * * *',
  $$select public.maintain_donor_listings();$$
);

select public.maintain_donor_listings();
