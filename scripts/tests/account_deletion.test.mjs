import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import test from 'node:test';

const { PGlite } = await import(process.env.PGLITE_MODULE || '@electric-sql/pglite');
const migration = await readFile(new URL('../../supabase/account_deletion.sql', import.meta.url), 'utf8');
const target = '10000000-0000-4000-8000-000000000001';
const donor = '20000000-0000-4000-8000-000000000002';
const other = '30000000-0000-4000-8000-000000000003';
const owned = '40000000-0000-4000-8000-000000000001';
const reserved = '40000000-0000-4000-8000-000000000002';
const expired = '40000000-0000-4000-8000-000000000003';
const untouched = '40000000-0000-4000-8000-000000000004';
const job = '50000000-0000-4000-8000-000000000001';

async function setup() {
  const db = new PGlite();
  await db.exec(`
    create role authenticated;
    create role anon;
    create role service_role bypassrls;
    create schema auth;
    create schema storage;
    create table auth.users(id uuid primary key);
    create function auth.uid() returns uuid language sql stable as
      $$ select nullif(current_setting('request.jwt.claim.sub', true), '')::uuid $$;
    create function auth.role() returns text language sql stable as
      $$ select current_setting('request.jwt.claim.role', true) $$;
    grant usage on schema auth, storage to authenticated, anon, service_role;
    grant select, delete on auth.users to service_role;
    create table storage.objects(bucket_id text, name text, owner_id text, owner uuid);
    alter table storage.objects enable row level security;
    create policy storage_access on storage.objects for all to authenticated using (true) with check (true);
    grant select, insert, delete on storage.objects to authenticated, service_role;
    insert into auth.users values ('${target}'), ('${donor}'), ('${other}');
    create table public.listings(
      id uuid primary key, posted_by uuid references auth.users(id), claimed_by uuid references auth.users(id),
      status text, details text, title text, contact_instructions text,
      pickup_deadline timestamptz, reserved_until timestamptz, waitlist_user_ids uuid[] default '{}'
    );
    create table public.listing_reservations(listing_id uuid references public.listings(id),
      reserver_id uuid references auth.users(id), provider_contact_instructions text);
    create table public.listing_completions(listing_id uuid references public.listings(id),
      consumer_id uuid references auth.users(id));
    create table public.listing_messages(listing_id uuid references public.listings(id), sender_id uuid references auth.users(id));
    create table public.pantry_claims(claimed_by uuid references auth.users(id));
    create table public.device_tokens(user_id uuid references auth.users(id));
    create table public.user_blocks(blocker_id uuid references auth.users(id), blocked_id uuid references auth.users(id));
    create table public.listing_reports(listing_id uuid, reporter_id uuid references auth.users(id), reported_user_id uuid references auth.users(id));
    insert into public.listings values
      ('${owned}', '${target}', '${other}', 'reserved', 'packages_total=5;packages_remaining=4', 'Owned', '{}', now()+interval '1 hour', now()+interval '1 hour', '{}'),
      ('${reserved}', '${donor}', '${target}', 'readyForPickup', 'packages_total=10;packages_remaining=5', 'Reserved',
        '{"reservedPackageCount":3,"consumerDropOffAddress":"Private home","consumerDropOffLatitude":41.9,"consumerDropOffLongitude":-87.6}', now()+interval '1 hour', now()+interval '1 hour', '{}'),
      ('${expired}', '${donor}', '${target}', 'reserved', 'packages_total=2;packages_remaining=0', 'Expired',
        '{"reservedPackageCount":2}', now()-interval '1 hour', now()-interval '1 hour', '{}'),
      ('${untouched}', '${donor}', null, 'available', 'packages_total=10;packages_remaining=7', 'Untouched', '{}',
        now()+interval '1 hour', null, array['${target}'::uuid,'${other}'::uuid]);
    insert into public.listing_reservations values
      ('${owned}', '${other}', '{}'), ('${reserved}', '${target}', '{"meetupAddress":"Donor porch","instructionsPublished":true}'),
      ('${expired}', '${target}', 'old non-json instructions');
    insert into public.listing_completions values ('${owned}', '${other}'), ('${untouched}', '${target}');
    insert into public.listing_messages values ('${owned}', '${other}'), ('${reserved}', '${target}'), ('${untouched}', '${other}');
    insert into public.pantry_claims values ('${target}'), ('${donor}');
    insert into public.device_tokens values ('${target}'), ('${donor}');
    insert into public.user_blocks values ('${target}', '${other}'), ('${other}', '${target}'), ('${other}', '${donor}');
    insert into public.listing_reports values ('${owned}', '${other}', '${target}'),
      ('${reserved}', '${target}', '${donor}'), ('${untouched}', '${other}', '${donor}');
    insert into storage.objects values
      ('listing-photos', '${target}/photo.jpg', null, null),
      ('listing-photos', 'legacy.jpg', '', '${target}'),
      ('listing-photos', '${donor}/photo.jpg', '${donor}', null),
      ('app-data', 'gcfd_food.db', '${donor}', null);
  `);
  for (const table of ['listings','listing_reservations','listing_completions','listing_messages',
    'pantry_claims','device_tokens','user_blocks','listing_reports']) {
    await db.exec(`alter table public.${table} enable row level security;
      create policy fixture_access on public.${table} for all to authenticated using (true) with check (true);
      grant select, insert, update, delete on public.${table} to authenticated, service_role;`);
  }
  await db.exec(migration);
  await db.query("insert into public.account_deletion_requests(request_id,secret_hash,user_id) values ($1,$2,$3)", [job, 'a'.repeat(64), target]);
  return db;
}

async function asUser(db, id = target, role = 'authenticated') {
  await db.exec(`reset role; set role ${role}; select set_config('request.jwt.claim.sub','${id}',false);
    select set_config('request.jwt.claim.role','${role}',false);`);
}

test('deletion restores only reserved packages and erases personal data without deleting other donors', async () => {
  const db = await setup();
  try {
    await db.exec(migration);
    await asUser(db, '', 'service_role');
    const files = (await db.query('select * from public.account_deletion_photos($1)', [target])).rows;
    assert.equal(files.length, 2);
    assert.ok(files.every(file => file.name === 'legacy.jpg' || file.name.startsWith(target)));
    await db.query('select public.cleanup_account_data($1)', [target]);
    await db.query('select public.cleanup_account_data($1)', [target]);
    const remaining = (await db.query('select * from public.listings order by id')).rows;
    assert.equal(remaining.length, 3);
    const released = remaining.find(row => row.id === reserved);
    assert.equal(released.status, 'available');
    assert.equal(released.claimed_by, null);
    assert.equal(released.reserved_until, null);
    assert.equal(released.details, 'packages_total=10;packages_remaining=8');
    const contact = JSON.parse(released.contact_instructions);
    assert.equal(contact.meetupAddress, 'Donor porch');
    assert.equal(contact.consumerDropOffAddress, '');
    assert.equal(contact.consumerDropOffLatitude, null);
    assert.equal(contact.reservedPackageCount, null);
    assert.equal(remaining.find(row => row.id === expired).status, 'expired');
    const unaffected = remaining.find(row => row.id === untouched);
    assert.equal(unaffected.details, 'packages_total=10;packages_remaining=7');
    assert.deepEqual(unaffected.waitlist_user_ids, [other]);
    assert.equal((await db.query('select * from public.listing_reservations')).rows.length, 0);
    assert.equal((await db.query('select * from public.listing_completions')).rows.length, 0);
    assert.deepEqual((await db.query('select sender_id from public.listing_messages')).rows, [{sender_id: other}]);
    assert.deepEqual((await db.query('select * from public.device_tokens')).rows, [{user_id: donor}]);
    assert.deepEqual((await db.query('select * from public.pantry_claims')).rows, [{claimed_by: donor}]);
    assert.equal((await db.query('select * from public.user_blocks')).rows.length, 1);
    assert.deepEqual((await db.query('select * from public.listing_reports')).rows, [
      {listing_id: untouched, reporter_id: other, reported_user_id: donor}
    ]);
    // no remaining foreign keys stop the auth admin from deleting this account
    await db.query('delete from auth.users where id = $1', [target]);
    await asUser(db);
    assert.equal((await db.query('select public.account_can_use_app() as allowed')).rows[0].allowed, false);
    assert.equal((await db.query('select * from public.listings')).rows.length, 0);
  } finally { await db.close(); }
});

test('pending accounts and forged callers cannot write or run cleanup', async () => {
  const db = await setup();
  try {
    await asUser(db);
    await assert.rejects(db.query('select public.cleanup_account_data($1)', [donor]), /permission denied/);
    await assert.rejects(db.query('select public.account_deletion_photos($1)', [donor]), /permission denied/);
    await assert.rejects(db.query('select * from public.account_deletion_requests'), /permission denied/);
    await assert.rejects(db.query('insert into public.listings(id,posted_by) values ($1,$2)', [job, target]), /deletion is in progress/);
    await assert.rejects(db.query('insert into storage.objects(bucket_id,name) values ($1,$2)', ['listing-photos', `${target}/new.jpg`]), /row-level security/);
    await db.exec(`reset role; create function public.test_stale_rpc() returns void language sql security definer
      as $$ insert into public.listing_messages(listing_id,sender_id) values ('${untouched}', '${target}') $$;
      grant execute on function public.test_stale_rpc() to authenticated;`);
    await asUser(db);
    await assert.rejects(db.query('select public.test_stale_rpc()'), /deletion is in progress/);
    await asUser(db, donor);
    await assert.rejects(db.query('update public.listings set claimed_by = $1 where id = $2', [target, untouched]), /listing is unavailable/);
    await asUser(db, '', 'service_role');
    await assert.rejects(db.query('select public.cleanup_account_data($1)', [donor]), /Deletion request missing/);
  } finally { await db.close(); }
});

test('cleanup failure rolls reservation changes back for a safe retry', async () => {
  const db = await setup();
  try {
    await db.exec(`create function public.test_fail_delete() returns trigger language plpgsql as
      $$ begin raise exception 'temporary failure'; end $$;
      create trigger test_fail_delete before delete on public.listing_messages
      for each row execute function public.test_fail_delete();`);
    await asUser(db, '', 'service_role');
    await assert.rejects(db.query('select public.cleanup_account_data($1)', [target]), /temporary failure/);
    const row = (await db.query('select * from public.listings where id=$1',[reserved])).rows[0];
    assert.equal(row.claimed_by, target);
    assert.equal(row.details, 'packages_total=10;packages_remaining=5');
    assert.equal((await db.query('select * from public.listings where id=$1',[owned])).rows.length, 1);
  } finally { await db.close(); }
});
