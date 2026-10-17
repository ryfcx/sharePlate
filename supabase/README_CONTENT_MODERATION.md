# Content moderation

Most donor and pantry surplus posts appear immediately. The database checks text for obvious spam, payment requests, and objectionable terms. Posts it flags stay private until a team member reviews them. User reports also enter the review queue, but do not automatically remove a post. Public pantry directory records are unchanged.

Photos are required and kept in private storage, but their contents are **not automatically scanned**. Review photos when text is flagged or a report arrives. If automatic image moderation is needed later, that requires a separate image moderation service and its own credentials.

## Enable

1. Run `listing_reports.sql` and `user_blocks.sql` first if they are not already installed.
2. Run the entire `content_moderation.sql` file in the Supabase SQL Editor.
3. If the push function is in use, redeploy it from the project folder:

   ```sh
   supabase functions deploy send-handoff-push --project-ref fkcsgxywdpcdwdlhflgv
   ```

4. Rebuild and install the app on each device, or upload a new TestFlight/App Store build.

The SQL script installs the queue, server enforcement, private photo access, and Realtime publication for `listing_visibility`. Keep your existing `listings` Realtime publication enabled. No new Edge Function, scheduled job, or paid moderation API is required.

Existing posts stay available when the script first runs. If the earlier manual-review version of this script was already run, running this updated version releases pending posts with ordinary text and a valid photo. Flagged posts and rejected posts keep their states. Re-running the script does not undo rejections. Existing bookings keep working. Older app builds cannot post without a private uploaded photo and cannot reserve a flagged post; distribute the new build when enabling this change.

## Review a post

In the Supabase SQL Editor, run:

```sql
select * from public.listing_moderation_queue
order by created_at;
```

Only dashboard administrators and the trusted service role can read this view. It contains flagged, unexpired posts and posts with unresolved reports. Ordinary app accounts cannot read the queue or approve posts. Do not place the service role key in the app.

Review only posts in this queue:

1. Inspect the title, description/quantity details, pickup notes, and provider instructions. Confirm the content describes a genuine food offer. Reject harassment, hate, explicit material, dangerous instructions, spam, scams, requests for payment, and clearly unsafe food offers. The automatic text check covers only obvious terms and can miss harmful wording.
2. In Storage → `listing-photos`, open the uploaded photo at the path in `photo_url`. For legacy full URLs, use the path after `/listing-photos/`. Review the actual image, not its filename. Do not make the bucket public. Reject explicit, violent, unrelated, or misleading photos. Avoid approving images that expose someone's sensitive information.
3. If `open_reports` is nonzero, review the matching rows in `listing_reports` before deciding. Reports do not automatically remove posts; this prevents malicious reports from taking down valid food offers.
4. Copy the post's `id` and current `moderation_version` from the queue into one of the calls below. The version prevents approval of content changed since you reviewed it.

Approve:

```sql
select public.moderate_listing('REPLACE_WITH_LISTING_UUID', 'approved', 1);
```

Reject or remove an already approved post:

```sql
select public.moderate_listing(
  'REPLACE_WITH_LISTING_UUID', 'rejected', 1,
  'The photo does not match the food offered. Please post a clear photo of the food.'
);
```

Replace `1` with the actual version. Rejection requires a brief explanation that the donor can read. Approval dismisses outstanding reports; rejection resolves them. Decisions stamp `moderated_at`. Donors see the decision in My Listings, including any explanation, and can contact support. Notes can use the existing translation control.

Approved posts appear on the map and can be reserved until their normal deadline. Rejected posts disappear from browsing and cannot receive new bookings or messages, including on older clients. Live visibility updates also hide a rejected post from devices that had already cached it; refresh/foreground sync is the fallback if the connection drops. An open detail screen switches to an unavailable message rather than keeping pickup actions active.

## Protections

- The database decides whether a new post is immediately `approved` or needs review. Clients cannot approve themselves, forge the owner, or use a reservation RPC to bypass review.
- Text and photo changes are checked again. Approved provider content is locked against client changes. Numeric package updates and the consumer's private drop-off details remain usable during bookings.
- Photos are private, limited to 5 MB, uploaded under the account's own folder, and cannot be overwritten or deleted while attached to a listing. An upload is attached in the same listing insert, avoiding a publicly visible post with a missing photo. Unattached uploads from failed attempts are removed when possible; storage can still contain orphan files after a device/network failure.
- Submissions are limited to ten per account per hour. This reduces casual spam; it is not a guarantee against someone creating multiple anonymous accounts.
- The public visibility signal contains only listing IDs, review states, and update times, not photos, text, addresses, or reporter identities.
- Review fields live on the listing itself. Account deletion removes them and the related visibility row with the post; no duplicate moderation snapshot is retained by this feature. Reports follow the existing reporting and account-deletion rules.

Review and remove orphan uploads through the Storage API or dashboard if needed. Do not delete rows directly from `storage.objects`, since that would leave the underlying files behind.

This change adds no external content-processing provider. Your privacy policy should accurately describe review of flagged or reported submissions and the existing Supabase storage/reporting services.

## Build check

Compile the iOS app after applying the SQL. Before launch, exercise submission, approval, rejection, reports, multi-package handoffs, and private image access on two physical devices. This implementation does not deploy the SQL or the push function automatically.

References: [Supabase private buckets](https://supabase.com/docs/guides/storage/buckets/fundamentals), [Storage access control](https://supabase.com/docs/guides/storage/security/access-control), and [Realtime with RLS](https://supabase.com/docs/guides/realtime/postgres-changes).
