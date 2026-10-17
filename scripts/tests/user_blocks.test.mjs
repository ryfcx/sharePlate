import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import test from 'node:test';

// run with pglite installed in a temporary folder
const { PGlite } = await import(process.env.PGLITE_MODULE || '@electric-sql/pglite');
const migration = await readFile(new URL('../../supabase/user_blocks.sql', import.meta.url), 'utf8');
const provider = '10000000-0000-4000-8000-000000000001';
const consumer = '20000000-0000-4000-8000-000000000002';
const other = '30000000-0000-4000-8000-000000000003';
const available = '40000000-0000-4000-8000-000000000004';
const active = '50000000-0000-4000-8000-000000000005';

async function setup(messages = true) {
  const db = new PGlite();
  await db.exec(`
    create role authenticated;
    create role anon;
    create role service_role bypassrls;
    create schema auth;
    create table auth.users (id uuid primary key);
    create function auth.uid() returns uuid language sql stable as
      $$ select nullif(current_setting('request.jwt.claim.sub', true), '')::uuid $$;
    create function auth.role() returns text language sql stable as
      $$ select current_setting('request.jwt.claim.role', true) $$;
    grant usage on schema auth to authenticated, anon, service_role;
    insert into auth.users values ('${provider}'), ('${consumer}'), ('${other}');
    create table public.listings (id uuid primary key, posted_by uuid not null,
      claimed_by uuid, status text not null default 'available');
    alter table public.listings enable row level security;
    create policy read_listings on public.listings for select to authenticated using (true);
    create policy update_listings on public.listings for update to authenticated using (true) with check (true);
    grant select, update on public.listings to authenticated;
    insert into public.listings values
      ('${available}', '${provider}', null, 'available'),
      ('${active}', '${provider}', '${consumer}', 'reserved');
    create function public.test_reserve(target uuid) returns void
      language sql security definer set search_path = public as
      $$ update public.listings set claimed_by = auth.uid(), status = 'reserved' where id = target $$;
    grant execute on function public.test_reserve(uuid) to authenticated;
  `);
  if (messages) {
    await db.exec(`
      create table public.listing_messages (listing_id uuid, sender_id uuid, body text);
      alter table public.listing_messages enable row level security;
      create policy participants_read on public.listing_messages for select to authenticated using (true);
      create policy participants_send on public.listing_messages for insert to authenticated with check (true);
      grant select, insert on public.listing_messages to authenticated;
    `);
  }
  await db.exec(migration);
  return db;
}

async function asUser(db, id) {
  await db.exec(`reset role; set role authenticated;
    select set_config('request.jwt.claim.sub', '${id}', false);
    select set_config('request.jwt.claim.role', 'authenticated', false);`);
}

test('blocks protect listings, reservations and messages in both directions', async () => {
  const db = await setup();
  try {
    await asUser(db, consumer);
    await db.query('insert into public.listing_messages values ($1, $2, $3)', [active, consumer, 'On my way']);
    await asUser(db, provider);
    await db.query('insert into public.user_blocks (blocker_id, blocked_id) values ($1, $2)', [provider, consumer]);
    await assert.rejects(db.query('insert into public.user_blocks (blocker_id, blocked_id) values ($1, $1)', [provider]), /check constraint/);
    assert.equal((await db.query('select * from public.user_blocks')).rows.length, 1);
    assert.equal((await db.query('select * from public.listings')).rows.length, 2);

    await asUser(db, consumer);
    assert.equal((await db.query('select * from public.user_blocks')).rows.length, 0);
    await assert.rejects(db.query('insert into public.user_blocks (blocker_id, blocked_id) values ($1, $2)', [provider, other]), /row-level security/);
    assert.deepEqual((await db.query('select id from public.listings')).rows.map(r => r.id), [active]);
    await assert.rejects(db.query('select public.test_reserve($1)', [available]), /reservation is unavailable/);
    assert.equal((await db.query('select * from public.listing_messages')).rows.length, 0);
    await assert.rejects(db.query('insert into public.listing_messages values ($1, $2, $3)', [active, consumer, 'On my way']), /Messages are unavailable|row-level security/);

    await asUser(db, other);
    assert.equal((await db.query('select * from public.listings')).rows.length, 2);
    // unrelated users cannot inspect a private block relationship
    assert.equal((await db.query('select public.users_are_blocked($1, $2) as blocked', [provider, consumer])).rows[0].blocked, false);

    await asUser(db, provider);
    // blocking does not cancel or prevent finishing an existing handoff
    await db.query("update public.listings set status = 'pickedUp' where id = $1", [active]);
    assert.equal((await db.query('select status from public.listings where id = $1', [active])).rows[0].status, 'pickedUp');
    await db.query('delete from public.user_blocks where blocked_id = $1', [consumer]);
    await asUser(db, consumer);
    assert.equal((await db.query('select * from public.listings')).rows.length, 2);
    await db.query('select public.test_reserve($1)', [available]);
    await db.query('insert into public.listing_messages values ($1, $2, $3)', [available, consumer, 'On my way']);

    // a consumer's block also prevents contact and new reservations
    await db.query('update public.listings set claimed_by = null where id = $1', [available]);
    await db.query('insert into public.user_blocks (blocker_id, blocked_id) values ($1, $2)', [consumer, provider]);
    await assert.rejects(db.query('select public.test_reserve($1)', [available]), /reservation is unavailable/);
    await asUser(db, provider);
    await assert.rejects(db.query('insert into public.listing_messages values ($1, $2, $3)', [active, provider, 'Ready']), /Messages are unavailable|row-level security/);
    // removing only one side cannot undo the other person's block
    await db.query('delete from public.user_blocks where blocked_id = $1', [consumer]);
    assert.equal((await db.query('select public.users_are_blocked($1, $2) as blocked', [provider, consumer])).rows[0].blocked, true);
  } finally {
    await db.close();
  }
});

test('migration can run twice and does not require messaging', async () => {
  const db = await setup(false);
  try {
    await db.exec(migration);
    await asUser(db, provider);
    await db.query('insert into public.user_blocks (blocker_id, blocked_id) values ($1, $2)', [provider, consumer]);
    await asUser(db, consumer);
    await assert.rejects(db.query('select public.test_reserve($1)', [available]), /reservation is unavailable/);
  } finally {
    await db.close();
  }
});
