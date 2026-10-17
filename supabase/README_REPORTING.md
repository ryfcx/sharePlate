# Listing reports

Run `listing_reports.sql` in the Supabase SQL Editor, then rebuild the app.

People can tap the flag on a listing or an active reservation, choose a reason, add optional details, and send the report. The app confirms only after Supabase accepts it. Failed submissions keep the form open for retry.

Reports use the listing's server ID and the signed-in account. The server captures the listing title, description, photo URL, and pickup note for review. It does not copy exact addresses or private handoff instructions. Other app users, including the provider, cannot read reports or identify the reporter through this feature.

Repeated submissions by the same account for the same listing return the original receipt. New reports are limited to ten per account per hour. A removed listing's report remains available for review.

## Reviewing reports

1. In Supabase, open Table Editor → `listing_reports`.
2. Filter `status` to `pending` and sort `created_at` from oldest to newest.
3. Inspect `reason`, `notes`, and `listing_snapshot`. Use `listing_id` to find the live listing in `listings`.
4. Set `status` to `in_review` while investigating. With [content moderation](README_CONTENT_MODERATION.md) enabled, use `moderate_listing` to reject unsafe posts or approve valid ones. This hides rejected content and updates the reports together. Changing only a report's status does not remove the listing.
5. Set `status` to `resolved` after acting, or `dismissed` if no action is needed. Add a short explanation in `moderator_notes`. The review timestamp fills automatically.

Check the queue regularly. Reporting does not send email alerts or automatically remove content. [Content moderation](README_CONTENT_MODERATION.md) holds flagged posts for review while ordinary posts appear immediately. Keep Supabase dashboard access limited to your team. Never put the service role key in the app.

## Checks

The backend tests run against a disposable PGlite database:

```sh
npm install --prefix /tmp/shareplate-block-sql-check --no-audit --no-fund @electric-sql/pglite
PGLITE_MODULE=/tmp/shareplate-block-sql-check/node_modules/@electric-sql/pglite/dist/index.js node --test scripts/tests/listing_reports.test.mjs
```
