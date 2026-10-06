# Chicago Demo Listings

`scripts/seed_demo_listings.py` creates person-to-person demo listings in Supabase. It does not create pantry listings:

- `pantry_gcfd_location_id` is always `null`.
- Pantry-only pickup types are rejected. Neighbor drop-off uses `communityFridge`.
- Every coordinate must fall inside the script's fixed Chicago boundary.
- Dedicated demo Auth users own the listings, so your anonymous app user can reserve them.

## 1. Add images

Create `demo/images/` and add these files:

```text
tomatoes.jpg
bread.jpg
pasta.jpg
fruit.jpg
groceries.jpg
casual-pizza.jpg
casual-tomatoes.jpg
casual-oatmeal.jpg
casual-cookies.jpg
casual-noodles.jpg
casual-salad.jpg
casual-grilled-cheese.jpg
casual-food-plate.jpg
casual-dry-goods.jpg
casual-egg-dish.jpg
```

JPG, JPEG, and PNG files up to 10 MB are accepted. If your filenames differ, edit the `image` values in `demo/listings.json`.

## 2. Add local Supabase credentials

Copy `.env.example` to `.env`, then add the server-side service-role key from your Supabase project:

```text
SUPABASE_URL=https://fkcsgxywdpcdwdlhflgv.supabase.co
SUPABASE_SERVICE_ROLE_KEY=your-service-role-key
```

`.env` is ignored by Git. Never put the service-role key in the iOS app, a committed file, or client-side code.

## 3. Validate before uploading

```bash
python3 scripts/seed_demo_listings.py validate
```

This checks required fields, image files, enum values, package counts, and the Chicago coordinate boundary. It does not contact Supabase.

## 4. Seed the listings

```bash
python3 scripts/seed_demo_listings.py seed
```

Open or refresh SharePlate afterward. The 15 listings should appear as regular available food listings.

If a previous demo batch exists and you want to replace it:

```bash
python3 scripts/seed_demo_listings.py seed --replace
```

## 5. Remove demo data

```bash
python3 scripts/seed_demo_listings.py clean
```

This removes the listings and uploaded photos recorded in `demo/.seed-state.json`. It keeps the reusable demo Auth users.

To remove those users too:

```bash
python3 scripts/seed_demo_listings.py clean --delete-users
```

Do not manually delete `demo/.seed-state.json` before cleanup; it contains the IDs and Storage paths needed to remove the seeded data.

## Customize listings

Edit `demo/listings.json`. Supported values include:

- `category`: `preparedMeals`, `produce`, `bakery`, `pantry`, `drinks`, `mixed`, or `other`
- `pickup_type`: `porch`, `lobby`, `meetOutside`, or `frontDesk` for pickup; `communityFridge` for drop-off
- `dropoff_radius_miles`: required for drop-off listings (`1`, `3`, `5`, or `10`)
- `packages`: 1–8
- `deadline_hours`: 0.5–72

The `pantry` category means shelf-stable pantry items. It does **not** make a listing a pantry-managed listing; only `pantry_gcfd_location_id` controls that distinction, and the script always sets it to `null`.
