# Push notifications setup

> **Personal Apple Developer account:** Free/personal teams **cannot** use Push Notifications. The app ships with push **disabled** (`PushNotificationConfiguration.isEnabled = false`) so it builds and runs on a personal team. **Supabase Realtime** still delivers live handoff updates in-app. Skip to section 1 only if you later enroll in the **paid** Apple Developer Program ($99/yr).

SharePlate sends handoff push notifications via **APNs** and an Edge Function triggered by Supabase database webhooks.

## 0. Enable push in the app (paid Apple Developer Program only)

1. Enroll in the [Apple Developer Program](https://developer.apple.com/programs/) (personal/free teams do not support push).
2. In Xcode → target → **Signing & Capabilities** → **+ Capability** → **Push Notifications**.
3. Set **Code Signing Entitlements** to `sharePlate/sharePlate.Push.entitlements` (Debug and Release).
4. In `PushNotificationConfiguration.swift`, set `isEnabled = true`.
5. For App Store builds, change `aps-environment` in the entitlements file to `production`.

## 1. Run SQL

In Supabase **SQL Editor**, run:

- `device_tokens.sql` — device token table + Realtime publication

If `alter publication` fails because a table is already added, ignore that line.

In **Database → Replication**, confirm `listings` and `listing_messages` are enabled for Realtime.

## 2. Apple Developer

1. Enable **Push Notifications** for the SharePlate App ID (requires **paid** program membership).
2. Create an **APNs Auth Key** (.p8) and note Key ID + Team ID.

For production builds, change `sharePlate.Push.entitlements` to `aps-environment` = `production`.

## 3. Edge Function secrets

```bash
supabase secrets set APNS_KEY_ID=XXXXXXXXXX
supabase secrets set APNS_TEAM_ID=XXXXXXXXXX
supabase secrets set APNS_BUNDLE_ID=com.yourteam.sharePlate
supabase secrets set APNS_PRIVATE_KEY="$(cat AuthKey_XXXX.p8)"
# Optional — defaults to sandbox (development)
supabase secrets set APNS_PRODUCTION=false
```

Deploy:

```bash
supabase functions deploy send-handoff-push --no-verify-jwt
```

`--no-verify-jwt` is required because Database Webhooks do not send a user JWT.

## 4. Database webhooks

In **Database → Webhooks**, create two hooks to  
`https://<project-ref>.supabase.co/functions/v1/send-handoff-push`:

| Name | Table | Events |
|------|-------|--------|
| handoff-listing-updates | `listings` | UPDATE |
| handoff-message-inserts | `listing_messages` | INSERT |

## 5. What gets pushed

| Event | Recipient |
|-------|-----------|
| Listing reserved (`claimed_by` set) | Provider (`posted_by`) |
| Instructions published | Consumer (`claimed_by`) |
| Status → `ready_for_pickup` | Consumer |
| New phrase message | Other participant |
| Reservation released / picked up | Other participant |

The app also uses **Supabase Realtime** for instant in-app updates when a handoff is active.
