# Account deletion

## Enable it

1. Run `account_deletion.sql` in the Supabase SQL Editor.
2. Deploy the `delete-account` Edge Function:

```sh
supabase functions deploy delete-account --project-ref fkcsgxywdpcdwdlhflgv --no-verify-jwt
```

The deployment includes `index.ts` and `handler.ts`. The function uses Supabase's built-in `SUPABASE_URL` and `SUPABASE_SERVICE_ROLE_KEY` environment variables. Do not add the service role key to the iOS app.

The platform JWT check is off for this function because deletion retries must work after the account's login is gone. The handler verifies the user with Supabase Auth before accepting a new request. Further retries require the same random secret saved in the device Keychain. A caller cannot choose another user's ID.

If deploying from the Supabase Dashboard, create the `delete-account` function, include both TypeScript files, and turn off its platform JWT verification setting. The handler performs its own authentication. The CLI command above is the recommended deployment path.

3. Rebuild and install the app. Open Activity → Settings → Your data → Delete my data.

## What it does

Deletion removes the Supabase Auth account, its listings and uploaded files, messages, bookings and completion history, pantry claims, push tokens, blocks, and reports associated with that account. It also clears personal data cached on the device, the display name, photo cache, and notifications.

Reservations held by the deleted account are released. Only their reserved packages are restored to the donor's stock. Private drop-off details are cleared, expired food stays expired, and other donors' listings remain available. Deleting a provider removes their listings, including existing bookings for those listings.

The server stops app writes while deletion is pending and rejects stale account tokens after deletion. Uploaded files are removed through the Storage API before deleting the Auth account. If any stage fails, the app keeps a secure retry request and does not claim success. The app resumes pending deletion after a restart.

After completion the app displays a confirmation screen. It creates a new anonymous account only when the user chooses Start fresh. Public pantry directory data and language preferences are preserved.

The server keeps a private recovery receipt containing a random request ID, a hash of its random secret, and timestamps. The receipt's user ID is cleared on completion. It lets the device confirm a completed deletion if the final network response was lost.

If you add new tables containing user data, extend the cleanup function and its protections. If optional user tables are installed after this script, rerun it so they receive deletion protections.

## Verification

The automated checks use disposable data. They do not delete real Supabase accounts.

```sh
deno test supabase/functions/delete-account/handler_test.ts
PGLITE_MODULE=/tmp/shareplate-block-sql-check/node_modules/@electric-sql/pglite/dist/index.js node --test scripts/tests/account_deletion.test.mjs
```

After deployment, test with a disposable account on a physical phone: post a photo, reserve another test user's listing, delete the account, and confirm its data and storage files are gone. Check that the donor's remaining packages are correct. Reopen the app and confirm it stays on the deleted-data screen until Start fresh is selected.
