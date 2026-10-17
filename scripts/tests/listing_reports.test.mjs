import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import test from 'node:test';

const { PGlite } = await import(process.env.PGLITE_MODULE || '@electric-sql/pglite');
const migration = await readFile(new URL('../../supabase/listing_reports.sql', import.meta.url), 'utf8');
const provider = '10000000-0000-4000-8000-000000000001';
const consumer = '20000000-0000-4000-8000-000000000002';
const listing = n => `40000000-0000-4000-8000-${String(n).padStart(12, '0')}`;

async function setup() {
  const db = new PGlite();
  await db.exec(`
    create role authenticated;
    create role anon;
    create role service_role bypassrls;
    create schema auth;
    create table auth.users (id uuid primary key);
    create function auth.uid() returns uuid language sql stable as
      $$ select nullif(current_setting('request.jwt.claim.sub', true), '')::uuid $$;
    grant usage on schema auth to authenticated, anon, service_role;
    insert into auth.users values ('${provider}'), ('${consumer}');
    create table public.listings (
      id uuid primary key, posted_by uuid not null, title text, details text,
      photo_url text, pickup_notes text, created_at timestamptz default now(),
      pickup_address text, contact_instructions text
    );
    insert into public.listings (id, posted_by, title, details, photo_url, pickup_notes,
      pickup_address, contact_instructions)
      select ('40000000-0000-4000-8000-' || lpad(n::text,12,'0'))::uuid, '${provider}',
      'Bread ' || n, 'Fresh bread', 'https://example.org/bread.jpg', 'Contains wheat',
      'Private address', 'Private handoff details'
      from generate_series(1,12) as n;
  `);
  await db.exec(migration);
  return db;
}

async function asUser(db, id = consumer, role = 'authenticated') {
  await db.exec(`reset role; set role ${role};
    select set_config('request.jwt.claim.sub', '${id}', false);`);
}

async function submit(db, id = listing(1), reason = 'unsafeFood', notes = 'Please review') {
  const result = await db.query('select public.submit_listing_report($1, $2, $3) as id', [id, reason, notes]);
  return result.rows[0].id;
}

test('reports reach the private queue with stable ids and server evidence', async () => {
  const db = await setup();
  try {
    // migrations can be rerun without losing reports
    await db.exec(migration);
    await asUser(db);
    const receipt = await submit(db);
    assert.match(receipt, /^[0-9a-f-]{36}$/);
    assert.equal(await submit(db, listing(1), 'spam', 'retry'), receipt);
    await assert.rejects(db.query('select * from public.listing_reports'), /permission denied/);
    await assert.rejects(db.query("update public.listing_reports set status = 'dismissed'"), /permission denied/);
    await assert.rejects(db.query('delete from public.listing_reports'), /permission denied/);
    await assert.rejects(db.query('insert into public.listing_reports (listing_id, reporter_id) values ($1, $2)', [listing(2), provider]), /permission denied/);

    await db.exec('reset role');
    const rows = (await db.query('select * from public.listing_reports')).rows;
    assert.equal(rows.length, 1);
    assert.equal(rows[0].listing_id, listing(1));
    assert.equal(rows[0].reporter_id, consumer);
    assert.equal(rows[0].reported_user_id, provider);
    assert.equal(rows[0].status, 'pending');
    assert.equal(rows[0].reason, 'unsafeFood');
    assert.equal(rows[0].notes, 'Please review');
    assert.equal(rows[0].listing_snapshot.title, 'Bread 1');
    assert.equal(rows[0].listing_snapshot.photo_url, 'https://example.org/bread.jpg');
    assert.equal(rows[0].listing_snapshot.pickup_address, undefined);
    assert.equal(rows[0].listing_snapshot.contact_instructions, undefined);
    await db.query('delete from public.listings where id = $1', [listing(1)]);
    assert.equal((await db.query('select * from public.listing_reports')).rows.length, 1);
    await asUser(db);
    assert.equal(await submit(db), receipt);
    await db.exec('reset role');
    await db.query('delete from auth.users where id = $1', [consumer]);
    assert.equal((await db.query('select reporter_id from public.listing_reports')).rows[0].reporter_id, null);
  } finally { await db.close(); }
});

test('invalid reports are rejected and account throttling does not break retries', async () => {
  const db = await setup();
  try {
    await asUser(db, '', 'anon');
    await assert.rejects(submit(db), /permission denied/);
    await asUser(db, '');
    await assert.rejects(submit(db), /Authentication required/);
    await asUser(db, provider);
    await assert.rejects(submit(db), /report_own_listing/);
    await asUser(db);
    await assert.rejects(submit(db, listing(99)), /report_listing_unavailable/);
    await assert.rejects(submit(db, listing(1), 'invented'), /Invalid report reason/);
    await assert.rejects(submit(db, listing(1), null), /Invalid report reason/);
    await assert.rejects(submit(db, listing(1), 'spam', 'x'.repeat(1001)), /report_notes_too_long/);
    const receipt = await submit(db, listing(1), 'spam', '   ');
    for (let n = 2; n <= 10; n++) await submit(db, listing(n));
    await assert.rejects(submit(db, listing(11)), /report_rate_limited/);
    assert.equal(await submit(db, listing(1)), receipt);
    await db.exec('reset role');
    assert.equal((await db.query('select notes from public.listing_reports where id = $1', [receipt])).rows[0].notes, null);
    await db.query("update public.listing_reports set created_at = now() - interval '2 hours'");
    await asUser(db);
    assert.ok(await submit(db, listing(11)));
  } finally { await db.close(); }
});

test('moderators can review reports without making the queue public', async () => {
  const db = await setup();
  try {
    await asUser(db);
    const receipt = await submit(db);
    await asUser(db, '', 'service_role');
    await db.query("update public.listing_reports set status = 'in_review' where id = $1", [receipt]);
    await db.query("update public.listing_reports set status = 'resolved', moderator_notes = 'Reviewed' where id = $1", [receipt]);
    const row = (await db.query('select * from public.listing_reports where id = $1', [receipt])).rows[0];
    assert.equal(row.status, 'resolved');
    assert.ok(row.reviewed_at);
    await db.query("update public.listing_reports set status = 'pending' where id = $1", [receipt]);
    assert.equal((await db.query('select reviewed_at from public.listing_reports where id = $1', [receipt])).rows[0].reviewed_at, null);
    await db.exec('reset role');
    assert.equal((await db.query('select * from public.listings')).rows.length, 12);
    await asUser(db, provider);
    await assert.rejects(db.query('select reporter_id, notes from public.listing_reports'), /permission denied/);
  } finally { await db.close(); }
});
