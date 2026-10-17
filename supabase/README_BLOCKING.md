# User blocking

Run `user_blocks.sql` in the Supabase SQL Editor after the existing listing migrations. If you add the optional messaging table later, run this file again. It is safe to rerun.

Rebuild and install the app. Block user appears on food listings and active reservations. Unblock users in Activity → Settings → Blocked users.

If handoff push notifications are deployed, deploy the updated `send-handoff-push` function too:

```sh
supabase functions deploy send-handoff-push --project-ref fkcsgxywdpcdwdlhflgv
```

Blocking hides that user's listings and prevents new reservations and messages in either direction. Existing reservations remain available for completion or release. Blocking does not cancel a reservation or give providers a cancellation option.

Block records belong to the signed-in Supabase account. The app caches them for offline use. Other users cannot read or change your block list. Unblocking cannot undo a block placed by the other person.

The backend regression tests use a disposable PostgreSQL database through PGlite. Install it outside the app project and run:

```sh
npm install --prefix /tmp/shareplate-block-sql-check --no-audit --no-fund @electric-sql/pglite
PGLITE_MODULE=/tmp/shareplate-block-sql-check/node_modules/@electric-sql/pglite/dist/index.js node --test scripts/tests/user_blocks.test.mjs
```
