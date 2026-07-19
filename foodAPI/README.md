# Greater Chicago Food Depository – Food Location Sync

Daily sync of every food location, its **contact information**, and its
**opening hours** from the GCFD "Find Food" map
(<https://www.chicagosfoodbank.org/find-food-2/>) into a local SQL (SQLite)
database.

It does **not** scrape HTML. It calls the same internal JSON API that the map
widget on the page uses (`https://api.accessfood.org`), so it is fast and won't
get rate-limited/timed-out the way a browser scraper would.

## Requirements

- Python 3.10+ (tested on 3.14). **No third-party packages** – it uses only the
  Python standard library (`urllib`, `sqlite3`).

## Usage

```bash
python gcfd_food_sync.py
```

This creates / updates `gcfd_food.db` in the current folder. Run it again any
time and it will **upsert** (insert new + update existing) every location, so
the database always reflects the latest data. Locations that disappear from the
network are kept but flagged `is_active = 0`.

### Options

| Flag | Default | Description |
|------|---------|-------------|
| `--db PATH` | `gcfd_food.db` | SQLite database file path |
| `--radius N` | `100` | Search radius in miles from the map center |
| `--in-network-only` | off | Exclude out-of-network locations |
| `--map-token TOKEN` | GCFD map | accessfood widget map id (from the page embed) |
| `-v`, `--verbose` | off | Debug logging |

A full run fetches ~874 locations and takes ~1 minute (it is polite and pauses
briefly between API calls).

## What gets stored

The database has four tables:

- **`locations`** – one row per location: name, full address, `phone`,
  `website`, `contact_name` / `contact_phone` / `contact_email`, lat/long,
  food programs, languages, features, region/network, `is_active`,
  `first_seen`, `last_updated`.
- **`services`** – programs offered at each location (e.g. "Pantry/Grocery
  Distribution", "Hot Meal Program") with per-program overview, qualifications
  and contact details.
- **`service_schedules`** – the **opening hours**: day of week, start/end time,
  and notes for each program.
- **`sync_runs`** – an audit log of every run (counts, status, errors).

### Example queries

```sql
-- All active pantries with a phone number
SELECT name, address1, city, zip_code, phone, website
FROM locations
WHERE is_active = 1 AND phone <> ''
ORDER BY name;

-- Opening hours for a location
SELECT sc.week_day, sc.start_time_desc, sc.end_time_desc
FROM service_schedules sc
WHERE sc.location_id = 755
ORDER BY sc.day_of_week;

-- Everything open on Saturday (day_of_week 7)
SELECT DISTINCT l.name, l.address1, sc.start_time_desc, sc.end_time_desc
FROM locations l
JOIN service_schedules sc ON sc.location_id = l.location_id
WHERE sc.day_of_week = 7 AND l.is_active = 1;
```

> Note on `day_of_week`: 1 = Sunday, 2 = Monday, … 7 = Saturday. The
> human-readable `week_day` column is also stored.

You can also run `python verify.py` for a quick summary of the database.

## Running it automatically every day (Windows Task Scheduler)

1. Open **Task Scheduler** → **Create Basic Task…**
2. Name: `GCFD Food Sync`. Trigger: **Daily**, pick a time (e.g. 6:00 AM).
3. Action: **Start a program**.
   - **Program/script:** `python`
     (or the full path, e.g. `C:\Users\ryann\AppData\Local\Programs\Python\Python314\python.exe`)
   - **Add arguments:** `gcfd_food_sync.py`
   - **Start in:** `C:\Users\ryann\OneDrive\Desktop\foodAPI`
4. Finish. The task will run the sync every day and keep the database current.

To capture logs to a file, set the arguments to:

```
gcfd_food_sync.py >> sync.log 2>&1
```

(or wrap it in a small `.bat` file that does the redirection).

### macOS / Linux (cron)

```cron
0 6 * * *  cd /path/to/foodAPI && /usr/bin/python3 gcfd_food_sync.py >> sync.log 2>&1
```

## How it works (data sources)

| Step | API endpoint | Purpose |
|------|--------------|---------|
| 1 | `RegionMap?securityToken=…` | Resolve the map token → `regionId`, `regionMapId`, center lat/long |
| 2 | `LocationSearch?…&page=N` | Paginated list of all locations + contact info |
| 3 | `LocationServices?LocationIds=id\|region,…` | Programs/services per location |
| 4 | `LocationServiceSchedules?LocationIds=id,…` | Opening hours per program |

The GCFD map token (`DF82D6EF-FE73-4F97-80D1-CB23CC19D443`) is taken from the
`accessfood-widget` embed on the Find Food page. If GCFD ever changes it, pass
the new value with `--map-token`.
