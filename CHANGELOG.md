# SharePlate Changelog

This file records user-visible features, fixes, database changes, and developer tooling updates.

## 2026-10-17

### Changed

- Publish ordinary food posts immediately; hold only posts with suspicious text for review. Reported posts remain in the moderation queue.
- Update the posting screen and Spanish text to explain when a post needs review.
- Show every currently open matching place in Open now, beyond the nearby radius and pin limit, and refresh its hours while the map stays open.

## 2026-10-16

### Changed

- Add private review of listing text and photos, a protected moderation queue with approve/reject actions, live removal signals, upload limits, and English/Spanish review status screens. New posts require manual approval before appearing publicly.
- Add Delete my data in Settings, with protected server cleanup, reservation release, secure retries, local data removal, and an explicit Start fresh action after deletion.
- Send listing reports to a private Supabase review queue, with reasons, optional notes, receipt confirmation, retry handling, and server limits on duplicate and repeated submissions.
- Add privacy policy, SharePlate support, and terms links to Settings, with Spanish labels.
- Add user blocking to listings and active handoffs, with unblock controls in Settings and server protection for reservations and messages.
- Restore pantry hours from the GCFD schedule and refresh saved app data.
- Remove the automatic fake donor listing job and add a Supabase cleanup script for demo listings.

## 2026-09-07

### Added

- Added Chicago-only demo listing seed data and tooling for person-to-person listings with photos.
- Added a reusable SharePlate logo to the main app screen headers.
- Added an automated changelog utility and persistent project rule.

### Changed

- Expanded Spanish localization across UI labels, dynamic listing text, alerts, errors, schedules, and notifications.
- Configured the Chicago demo manifest around the supplied images and optimized them for upload.
- Expanded the Chicago demo catalog to 15 distinct providers with varied food types, quantities, neighborhoods, and documented Unsplash images.
- Replaced polished stock photos in the demo catalog with casual CC0 and public-domain food photos and recorded their licenses.

### Fixed

- Fixed localization paths where plain Swift strings bypassed the String Catalog.
- Fixed demo seeding on Python installations without a configured system certificate bundle.

### Database

- Granted the Supabase service role access to manage listings for server-side demo tooling.

## 2026-09-13

### Changed

- Converted five Chicago demo listings to neighbor drop-off with 3- and 5-mile radii.
- Made booking numbers large and matching on both phones, with a branded SharePlate QR code at handoff.

### Fixed

- Show new nearby listings immediately in an open consumer app, with an in-app banner instead of waiting for a refresh.
- Prevent a Realtime crash on launch by attaching the listing catalog channel only once, before subscribe.

## 2026-09-21

### Added

- Added a branded SharePlate startup splash that covers cold launch and the first moment the app is ready.

## 2026-09-26

### Fixed

- Make note translation retry when language detection fails and download the language model instead of showing an error.
- Fix note translation so a tap actually translates English text instead of cancelling before the language sheet appears.
- Stop note translation from cancelling itself and reporting Couldn't translate before the language download can finish.
- Offer note translation in any app language through the system translation sheet, instead of requiring Spanish and failing with Couldn't translate.

### Added

- Show the booking code and QR on a listing as soon as it is posted, including in My Listings.

## 2026-09-27

### Changed

- Offer on-device translation for listing titles, addresses, notes, and pantry directory text.

## 2026-10-01

### Changed

- Temporarily show every pantry map dot in green.

## 2026-10-03

### Added

- Add 6.5-inch App Store screenshots for the map, pantry list, pantry details, and posting food.
- Add 13-inch iPad App Store screenshots for the map, pantry list, pantry details, and posting food.

### Changed

- Refresh App Store screenshots so posting food sits alongside finding pantries.
- Show the app name as SharePlate on TestFlight and the Home Screen.
- Use the new SharePlate logo for the app icon and the in-app logo.

## 2026-10-05

### Changed

- Show the translate control only on pantry About text and on notes.
- Translate a pantry's hours with one button for the whole schedule.
- Show pantry map dots in open, closing soon, and closed colors again.
- Use the same open, closing soon, and closed colors on pantry rows and listing countdowns as on the map.
- Keep four Lincoln Park pantries green and shown as open regardless of their weekly hours.
- Show the four Lincoln Park pantries as Open 24 Hours so they stay green.
- Keep the four always-open pantries on a fixed Open 24 Hours schedule, and test that they stay green after a refresh and at any time of day.
- Call the scheduled donor-listing job directly so a check uses the same refill path as the every-minute database schedule.
- Start the map with the nearby list collapsed, and use the previous green-and-orange logo again.
- Show the three Lincoln Park pantries as green dots that stay open, and drop the fourth site and its cart pin.
- Start the six map filters on, keep posts and reservations in Activity history, and show a booking code on every shared meal including automatic listings.
- Show a food listing's booking code only after it is reserved.
- Turn on All locations immediately, without a confirmation.
- Spread the 15 permanent Lincoln Park listings across the neighborhood instead of a rectangular grid.
- Add individual neighbor donations alongside the grocery and restaurant listings.
- Show each selected filter's locations, with neighbor donations in purple and grocery and restaurant spots in green.
- Add named Lincoln Park restaurant listings alongside grocery spots and neighbor donations.

### Fixed

- Keep pantry hour translation on the same system translation sheet used for notes and About.
- Keep the reserve package picker readable when a listing has many packages.
- Make All locations zoom the map out to every matching place again.
- Apply Drop off and Pickup even when pantry or store filters are also selected.
- Clear the extra map pins when All locations is turned off.

### Added

- Add permanent listings for the four always-open stores and keep them in the catalog when donor listings expire.

### Database

- Schedule a job that keeps about 15 donor listings live, posting a random pickup or drop-off each minute and removing each one after 15 minutes.
- Replace the 15 rotating donor meals with 15 permanent Lincoln Park listings, 100 packages each, that stay on the map.

### Removed

- Remove the green in-app notice bar so alerts only appear as Apple notifications.

## 2026-10-06

### Fixed

- Show a booking code on food you post, before anyone reserves it.
- Leave the listing screen after a donor marks the food as picked up.
