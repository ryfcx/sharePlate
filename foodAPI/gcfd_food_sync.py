#!/usr/bin/env python3
"""Greater Chicago Food Depository - daily food location sync.

Pulls every food location (plus contact info and opening hours) that powers the
"Find Food" map on https://www.chicagosfoodbank.org/find-food-2/ and stores them
in a local SQL (SQLite) database. Re-running the script refreshes / upserts the
data so the database always reflects the current state of the network.

This uses the same internal JSON API that the map widget itself calls
(https://api.accessfood.org), NOT HTML scraping, so it is fast and stable.

Standard library only - no `pip install` required. Just run:

    python gcfd_food_sync.py

Run it once a day (see README.md for Windows Task Scheduler instructions).
"""

from __future__ import annotations

import argparse
import datetime as dt
import html.parser
import json
import logging
import os
import shutil
import sqlite3
import ssl
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path
from typing import Any, Iterable

# --------------------------------------------------------------------------- #
# Configuration
# --------------------------------------------------------------------------- #

API_BASE = "https://api.accessfood.org/api/MapInformation/"

# The GCFD "English Map" security token, taken from the accessfood-widget embed
# on the Find Food page (data-map="...").
MAP_TOKEN = "DF82D6EF-FE73-4F97-80D1-CB23CC19D443"

# Search radius (miles) from the map's default center. ~100mi comfortably covers
# the entire Greater Chicago Food Depository service area (Cook County and
# surroundings). Going much larger starts pulling in unrelated national
# locations from the shared Vivery network.
DEFAULT_RADIUS_MILES = 100

# Include locations flagged as "out of network" in the results.
DEFAULT_SHOW_OUT_OF_NETWORK = True

# How many location ids to request per services / schedules call.
BATCH_SIZE = 25

# Politeness / robustness settings.
REQUEST_TIMEOUT = 60          # seconds
REQUEST_DELAY = 0.25          # seconds between requests
MAX_RETRIES = 4
RETRY_BACKOFF = 2.0           # seconds, multiplied by attempt number

USER_AGENT = (
    "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 "
    "(KHTML, like Gecko) Chrome/120.0 Safari/537.36"
)

DEFAULT_DB_PATH = "gcfd_food.db"

# Where to copy the finished DB so the iOS app bundles the latest data.
# Resolved relative to this script: <repo>/sharePlate/Resources/gcfd_food.db
DEFAULT_APP_DB_PATH = str(
    Path(__file__).resolve().parent.parent / "sharePlate" / "Resources" / "gcfd_food.db"
)

# Supabase Storage — hosts the finished DB so already-installed apps can pick up
# fresh data without waiting for a new build. Public read, write via service role
# key only (never exposed to the app). Same project the app already uses.
DEFAULT_SUPABASE_URL = "https://fkcsgxywdpcdwdlhflgv.supabase.co"
SUPABASE_STORAGE_BUCKET = "app-data"
SUPABASE_STORAGE_OBJECT_PATH = "gcfd_food.db"

log = logging.getLogger("gcfd_sync")


# --------------------------------------------------------------------------- #
# Small helpers
# --------------------------------------------------------------------------- #

def clean(value: Any) -> Any:
    """Trim whitespace from strings (the API pads several fields)."""
    if isinstance(value, str):
        return value.strip()
    return value


class _HTMLTextExtractor(html.parser.HTMLParser):
    """Turn the small HTML fragments returned by AccessFood into plain text."""

    _BLOCK_TAGS = {
        "address", "article", "blockquote", "br", "div", "h1", "h2", "h3",
        "h4", "h5", "h6", "li", "p", "section", "tr",
    }

    def __init__(self) -> None:
        super().__init__(convert_charrefs=True)
        self.parts: list[str] = []

    def handle_starttag(self, tag: str, attrs: list[tuple[str, str | None]]) -> None:
        if tag.lower() in self._BLOCK_TAGS:
            self.parts.append("\n")

    def handle_endtag(self, tag: str) -> None:
        if tag.lower() in self._BLOCK_TAGS:
            self.parts.append("\n")

    def handle_data(self, data: str) -> None:
        self.parts.append(data)


def html_to_text(value: Any) -> Any:
    """Remove markup while preserving readable paragraph breaks."""
    value = clean(value)
    if not isinstance(value, str) or not value:
        return value

    parser = _HTMLTextExtractor()
    parser.feed(value)
    parser.close()

    lines = [" ".join(line.split()) for line in "".join(parser.parts).splitlines()]
    return "\n".join(line for line in lines if line)


def chunked(items: list, size: int) -> Iterable[list]:
    for i in range(0, len(items), size):
        yield items[i:i + size]


def now_iso() -> str:
    return dt.datetime.now().isoformat(timespec="seconds")


def build_ssl_context(insecure: bool = False) -> ssl.SSLContext:
    """Build the SSL context used for HTTPS requests.

    macOS python.org builds often ship without usable CA certificates (you must
    run "Install Certificates.command"), which causes CERTIFICATE_VERIFY_FAILED.
    To be robust everywhere, prefer the `certifi` CA bundle when it is installed,
    and fall back to the system default otherwise. `--insecure` disables
    verification entirely as a last resort (not recommended).
    """
    if insecure:
        log.warning("TLS verification disabled (--insecure). Use only if you trust the network.")
        return ssl._create_unverified_context()
    try:
        import certifi  # optional; not required when system certs work
        return ssl.create_default_context(cafile=certifi.where())
    except ImportError:
        return ssl.create_default_context()


# --------------------------------------------------------------------------- #
# API client
# --------------------------------------------------------------------------- #

class AccessFoodClient:
    """Thin client over the accessfood.org MapInformation API."""

    def __init__(self, base: str = API_BASE, ssl_context: ssl.SSLContext | None = None):
        self.base = base
        self.ssl_context = ssl_context

    def _get(self, endpoint: str, params: dict[str, Any]) -> Any:
        # Use quote_via=quote so commas/pipes in id lists are preserved the way
        # the API expects (it does not want them percent-encoded away).
        query = urllib.parse.urlencode(params, quote_via=urllib.parse.quote, safe="|,")
        url = f"{self.base}{endpoint}?{query}"

        last_err: Exception | None = None
        for attempt in range(1, MAX_RETRIES + 1):
            try:
                req = urllib.request.Request(url, headers={"User-Agent": USER_AGENT,
                                                           "Accept": "application/json"})
                with urllib.request.urlopen(req, timeout=REQUEST_TIMEOUT,
                                            context=self.ssl_context) as resp:
                    raw = resp.read().decode("utf-8")
                time.sleep(REQUEST_DELAY)
                return json.loads(raw)
            except Exception as err:  # noqa: BLE001 - we want to retry on anything
                last_err = err
                wait = RETRY_BACKOFF * attempt
                log.warning("Request failed (attempt %d/%d) for %s: %s; retrying in %.1fs",
                            attempt, MAX_RETRIES, endpoint, err, wait)
                time.sleep(wait)
        raise RuntimeError(f"Giving up on {endpoint} after {MAX_RETRIES} attempts: {last_err}")

    def region_map(self, token: str) -> dict:
        return self._get("RegionMap", {"securityToken": token, "isMapV2": "true"})

    def location_search(self, *, region_id: int, region_map_id: int, lat: float,
                        lng: float, radius: int, page: int,
                        show_out_of_network: bool) -> dict:
        return self._get("LocationSearch", {
            "radius": radius,
            "lat": lat,
            "lng": lng,
            "dayAv": "", "foodProgramAv": "", "serviceTypeAv": "",
            "foodOfferingAv": "", "dietRestrictionAv": "", "locationFeatureAv": "",
            "languagesAv": "", "serviceCategoriesAv": "",
            "regionId": region_id,
            "regionMapId": region_map_id,
            "showOutOfNetwork": "1" if show_out_of_network else "0",
            "page": page,
            "includeLocationOperatingHours": "true",
            "isMapV2": "true",
        })

    def location_services(self, loc_region_ids: list[str], map_region_id: int) -> list[dict]:
        result = self._get("LocationServices", {
            "LocationIds": ",".join(loc_region_ids),
            "PreviewMode": "false",
            "MapRegionId": map_region_id,
        })
        return result if isinstance(result, list) else []

    def location_service_schedules(self, location_ids: list[int], map_region_id: int) -> list[dict]:
        result = self._get("LocationServiceSchedules", {
            "LocationIds": ",".join(str(i) for i in location_ids),
            "MapRegionId": map_region_id,
        })
        return result if isinstance(result, list) else []


# --------------------------------------------------------------------------- #
# Database
# --------------------------------------------------------------------------- #

SCHEMA = """
CREATE TABLE IF NOT EXISTS locations (
    location_id          INTEGER PRIMARY KEY,
    organization_id      INTEGER,
    name                 TEXT,
    address1             TEXT,
    address2             TEXT,
    city                 TEXT,
    state                TEXT,
    zip_code             TEXT,
    country              TEXT,
    phone                TEXT,
    phone_ext            TEXT,
    website              TEXT,
    latitude             REAL,
    longitude            REAL,
    contact_name         TEXT,
    contact_phone        TEXT,
    contact_phone_ext    TEXT,
    contact_email        TEXT,
    about_us             TEXT,
    notes                TEXT,
    service_area         TEXT,
    service_areas        TEXT,
    food_programs        TEXT,
    food_service_types   TEXT,
    service_languages    TEXT,
    location_features    TEXT,
    food_offerings       TEXT,
    diet_restrictions    TEXT,
    service_programs     TEXT,
    region_id            INTEGER,
    region_name          TEXT,
    in_network           INTEGER,
    time_zone_code       TEXT,
    network_affiliations TEXT,
    first_seen           TEXT,
    last_updated         TEXT,
    is_active            INTEGER DEFAULT 1
);

CREATE TABLE IF NOT EXISTS services (
    location_service_id      INTEGER PRIMARY KEY,
    location_id              INTEGER,
    service_name             TEXT,
    service_category_id      INTEGER,
    service_category_desc    TEXT,
    food_program_type_id     INTEGER,
    food_program_type_desc   TEXT,
    overview                 TEXT,
    qualifications           TEXT,
    notes                    TEXT,
    contact_name             TEXT,
    contact_phone            TEXT,
    contact_phone_ext        TEXT,
    contact_email            TEXT,
    languages                TEXT,
    service_areas            TEXT,
    program_url              TEXT,
    active                   INTEGER,
    last_updated             TEXT,
    FOREIGN KEY (location_id) REFERENCES locations(location_id)
);

CREATE TABLE IF NOT EXISTS service_schedules (
    id                       INTEGER PRIMARY KEY AUTOINCREMENT,
    location_service_id      INTEGER,
    location_id              INTEGER,
    day_of_week              INTEGER,
    week_day                 TEXT,
    start_time               TEXT,
    end_time                 TEXT,
    start_time_desc          TEXT,
    end_time_desc            TEXT,
    weeks_of_month           TEXT,
    days_of_month            TEXT,
    every_other_week         INTEGER,
    contact_for_hours        TEXT,
    notes                    TEXT,
    last_updated             TEXT
);

CREATE TABLE IF NOT EXISTS sync_runs (
    id                INTEGER PRIMARY KEY AUTOINCREMENT,
    started_at        TEXT,
    finished_at       TEXT,
    locations_seen    INTEGER,
    services_seen     INTEGER,
    schedules_seen    INTEGER,
    deactivated       INTEGER,
    status            TEXT,
    message           TEXT
);

CREATE INDEX IF NOT EXISTS idx_services_location ON services(location_id);
CREATE INDEX IF NOT EXISTS idx_sched_location ON service_schedules(location_id);
CREATE INDEX IF NOT EXISTS idx_sched_service ON service_schedules(location_service_id);
"""


def connect(db_path: str) -> sqlite3.Connection:
    conn = sqlite3.connect(db_path)
    conn.execute("PRAGMA foreign_keys = ON;")
    conn.executescript(SCHEMA)
    return conn


def upsert_location(conn: sqlite3.Connection, loc: dict, run_ts: str) -> None:
    affiliations = loc.get("networkAffiliationsList") or []
    region_name = affiliations[0]["regionName"] if affiliations else None

    conn.execute(
        """
        INSERT INTO locations (
            location_id, organization_id, name, address1, address2, city, state,
            zip_code, country, phone, phone_ext, website, latitude, longitude,
            contact_name, contact_phone, contact_phone_ext, contact_email,
            about_us, notes, service_area, service_areas, food_programs,
            food_service_types, service_languages, location_features,
            food_offerings, diet_restrictions, service_programs, region_id,
            region_name, in_network, time_zone_code, network_affiliations,
            first_seen, last_updated, is_active
        ) VALUES (
            :location_id, :organization_id, :name, :address1, :address2, :city,
            :state, :zip_code, :country, :phone, :phone_ext, :website, :latitude,
            :longitude, :contact_name, :contact_phone, :contact_phone_ext,
            :contact_email, :about_us, :notes, :service_area, :service_areas,
            :food_programs, :food_service_types, :service_languages,
            :location_features, :food_offerings, :diet_restrictions,
            :service_programs, :region_id, :region_name, :in_network,
            :time_zone_code, :network_affiliations, :run_ts, :run_ts, 1
        )
        ON CONFLICT(location_id) DO UPDATE SET
            organization_id=excluded.organization_id,
            name=excluded.name,
            address1=excluded.address1,
            address2=excluded.address2,
            city=excluded.city,
            state=excluded.state,
            zip_code=excluded.zip_code,
            country=excluded.country,
            phone=excluded.phone,
            phone_ext=excluded.phone_ext,
            website=excluded.website,
            latitude=excluded.latitude,
            longitude=excluded.longitude,
            contact_name=excluded.contact_name,
            contact_phone=excluded.contact_phone,
            contact_phone_ext=excluded.contact_phone_ext,
            contact_email=excluded.contact_email,
            about_us=excluded.about_us,
            notes=excluded.notes,
            service_area=excluded.service_area,
            service_areas=excluded.service_areas,
            food_programs=excluded.food_programs,
            food_service_types=excluded.food_service_types,
            service_languages=excluded.service_languages,
            location_features=excluded.location_features,
            food_offerings=excluded.food_offerings,
            diet_restrictions=excluded.diet_restrictions,
            service_programs=excluded.service_programs,
            region_id=excluded.region_id,
            region_name=excluded.region_name,
            in_network=excluded.in_network,
            time_zone_code=excluded.time_zone_code,
            network_affiliations=excluded.network_affiliations,
            last_updated=excluded.last_updated,
            is_active=1
        """,
        {
            "location_id": loc.get("locationId"),
            "organization_id": loc.get("organizationId"),
            "name": clean(loc.get("locationName")),
            "address1": clean(loc.get("address1")),
            "address2": clean(loc.get("address2")),
            "city": clean(loc.get("city")),
            "state": clean(loc.get("state")),
            "zip_code": clean(loc.get("zipCode")),
            "country": clean(loc.get("country")),
            "phone": clean(loc.get("phone")),
            "phone_ext": clean(loc.get("phoneExt")),
            "website": clean(loc.get("website")),
            "latitude": loc.get("latitude"),
            "longitude": loc.get("longitude"),
            "contact_name": clean(loc.get("contactName")),
            "contact_phone": clean(loc.get("contactPhone")),
            "contact_phone_ext": clean(loc.get("contactPhoneExt")),
            "contact_email": clean(loc.get("contactEmail")),
            "about_us": html_to_text(loc.get("aboutUs")),
            "notes": clean(loc.get("notes")),
            "service_area": clean(loc.get("serviceArea")),
            "service_areas": clean(loc.get("serviceAreas")),
            "food_programs": clean(loc.get("foodPrograms")),
            "food_service_types": clean(loc.get("foodServiceTypes")),
            "service_languages": clean(loc.get("serviceLanguages")),
            "location_features": clean(loc.get("locationFeatures")),
            "food_offerings": clean(loc.get("foodOfferings")),
            "diet_restrictions": clean(loc.get("dietRestrictions")),
            "service_programs": clean(loc.get("servicePrograms")),
            "region_id": loc.get("regionId"),
            "region_name": region_name,
            "in_network": loc.get("inNetWorkInd"),
            "time_zone_code": clean(loc.get("timeZoneCode")),
            "network_affiliations": json.dumps(affiliations) if affiliations else None,
            "run_ts": run_ts,
        },
    )


def replace_services(conn: sqlite3.Connection, location_ids: list[int],
                     services: list[dict], run_ts: str) -> None:
    if location_ids:
        placeholders = ",".join("?" for _ in location_ids)
        conn.execute(f"DELETE FROM services WHERE location_id IN ({placeholders})",
                     location_ids)
    for svc in services:
        conn.execute(
            """
            INSERT INTO services (
                location_service_id, location_id, service_name, service_category_id,
                service_category_desc, food_program_type_id, food_program_type_desc,
                overview, qualifications, notes, contact_name, contact_phone,
                contact_phone_ext, contact_email, languages, service_areas,
                program_url, active, last_updated
            ) VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)
            ON CONFLICT(location_service_id) DO UPDATE SET
                location_id=excluded.location_id,
                service_name=excluded.service_name,
                service_category_id=excluded.service_category_id,
                service_category_desc=excluded.service_category_desc,
                food_program_type_id=excluded.food_program_type_id,
                food_program_type_desc=excluded.food_program_type_desc,
                overview=excluded.overview,
                qualifications=excluded.qualifications,
                notes=excluded.notes,
                contact_name=excluded.contact_name,
                contact_phone=excluded.contact_phone,
                contact_phone_ext=excluded.contact_phone_ext,
                contact_email=excluded.contact_email,
                languages=excluded.languages,
                service_areas=excluded.service_areas,
                program_url=excluded.program_url,
                active=excluded.active,
                last_updated=excluded.last_updated
            """,
            (
                svc.get("locationServiceId"),
                svc.get("locationId"),
                clean(svc.get("serviceName")),
                svc.get("serviceCategoryId"),
                clean(svc.get("serviceCategoryDescription")),
                svc.get("foodProgramTypeId"),
                clean(svc.get("foodProgramTypeDescription")),
                clean(svc.get("overview")),
                clean(svc.get("qualifications")),
                clean(svc.get("notes")),
                clean(svc.get("contactName")),
                clean(svc.get("contactPhone")),
                clean(svc.get("contactPhoneExt")),
                clean(svc.get("contactEmail")),
                clean(svc.get("languages")),
                clean(svc.get("serviceAreas")),
                clean(svc.get("programUrl")),
                1 if svc.get("activeInd") else 0,
                run_ts,
            ),
        )


def replace_schedules(conn: sqlite3.Connection, location_ids: list[int],
                      schedules: list[dict], run_ts: str) -> None:
    if location_ids:
        placeholders = ",".join("?" for _ in location_ids)
        conn.execute(f"DELETE FROM service_schedules WHERE location_id IN ({placeholders})",
                     location_ids)
    for sch in schedules:
        conn.execute(
            """
            INSERT INTO service_schedules (
                location_service_id, location_id, day_of_week, week_day,
                start_time, end_time, start_time_desc, end_time_desc,
                weeks_of_month, days_of_month, every_other_week,
                contact_for_hours, notes, last_updated
            ) VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?)
            """,
            (
                sch.get("locationServiceId"),
                sch.get("locationId"),
                sch.get("dayOfWeek"),
                clean(sch.get("weekDayDescr")),
                clean(sch.get("startTime")),
                clean(sch.get("endTime")),
                clean(sch.get("startTimeDescr")),
                clean(sch.get("endTimeDescr")),
                clean(sch.get("weeksOfMonth")),
                clean(sch.get("daysOfMonth")),
                1 if sch.get("everyOtherWeekInd") else 0,
                clean(sch.get("contactForHoursMessage")),
                clean(sch.get("notes")),
                run_ts,
            ),
        )


# --------------------------------------------------------------------------- #
# Sync orchestration
# --------------------------------------------------------------------------- #

def fetch_all_locations(client: AccessFoodClient, *, region_id: int,
                        region_map_id: int, lat: float, lng: float, radius: int,
                        show_out_of_network: bool) -> list[dict]:
    """Page through LocationSearch until all locations are collected."""
    first = client.location_search(region_id=region_id, region_map_id=region_map_id,
                                    lat=lat, lng=lng, radius=radius, page=0,
                                    show_out_of_network=show_out_of_network)
    total = first.get("item5") or 0
    locations: list[dict] = list(first.get("item1") or [])
    log.info("Total locations reported by API: %d", total)

    page = 1
    while len(locations) < total:
        batch = client.location_search(region_id=region_id, region_map_id=region_map_id,
                                       lat=lat, lng=lng, radius=radius, page=page,
                                       show_out_of_network=show_out_of_network)
        rows = batch.get("item1") or []
        if not rows:
            log.warning("Page %d returned no rows; stopping early at %d/%d",
                        page, len(locations), total)
            break
        locations.extend(rows)
        log.info("Fetched page %d (%d/%d locations)", page, len(locations), total)
        page += 1

    # De-duplicate on location_id (paged search can overlap).
    unique: dict[int, dict] = {}
    for loc in locations:
        lid = loc.get("locationId")
        if lid is not None:
            unique[lid] = loc
    return list(unique.values())


def run_sync(db_path: str, *, radius: int, show_out_of_network: bool,
             map_token: str, insecure: bool = False) -> int:
    started = now_iso()
    client = AccessFoodClient(ssl_context=build_ssl_context(insecure))
    conn = connect(db_path)

    try:
        region = client.region_map(map_token)
        region_id = region["regionId"]
        region_map_id = region["regionMapId"]
        lat = region.get("defaultLatitude", 41.8781136)
        lng = region.get("defaultLongitude", -87.6297982)
        log.info("Map '%s' -> regionId=%s regionMapId=%s center=(%.5f, %.5f)",
                 region.get("mapName"), region_id, region_map_id, lat, lng)

        locations = fetch_all_locations(
            client, region_id=region_id, region_map_id=region_map_id,
            lat=lat, lng=lng, radius=radius, show_out_of_network=show_out_of_network,
        )
        log.info("Collected %d unique locations", len(locations))

        run_ts = now_iso()
        total_services = 0
        total_schedules = 0

        # Upsert locations.
        for loc in locations:
            upsert_location(conn, loc, run_ts)
        conn.commit()

        # Fetch + replace services and schedules in batches.
        all_ids = [loc["locationId"] for loc in locations]
        id_region = {loc["locationId"]: loc.get("regionId") for loc in locations}

        for i, batch in enumerate(chunked(all_ids, BATCH_SIZE), start=1):
            loc_region_ids = [f"{lid}|{id_region.get(lid)}" for lid in batch]
            services = client.location_services(loc_region_ids, region_id)
            schedules = client.location_service_schedules(batch, region_id)

            replace_services(conn, batch, services, run_ts)
            replace_schedules(conn, batch, schedules, run_ts)
            conn.commit()

            total_services += len(services)
            total_schedules += len(schedules)
            log.info("Batch %d/%d: %d services, %d schedules",
                     i, (len(all_ids) + BATCH_SIZE - 1) // BATCH_SIZE,
                     len(services), len(schedules))

        # Deactivate locations that were not seen in this run.
        cur = conn.execute(
            "UPDATE locations SET is_active = 0 WHERE last_updated < ? AND is_active = 1",
            (run_ts,),
        )
        deactivated = cur.rowcount
        conn.commit()

        conn.execute(
            """INSERT INTO sync_runs (started_at, finished_at, locations_seen,
               services_seen, schedules_seen, deactivated, status, message)
               VALUES (?,?,?,?,?,?,?,?)""",
            (started, now_iso(), len(locations), total_services, total_schedules,
             deactivated, "success", None),
        )
        conn.commit()

        log.info("Done. %d locations, %d services, %d schedules, %d deactivated.",
                 len(locations), total_services, total_schedules, deactivated)
        return 0

    except Exception as err:  # noqa: BLE001
        log.exception("Sync failed: %s", err)
        try:
            conn.execute(
                """INSERT INTO sync_runs (started_at, finished_at, locations_seen,
                   services_seen, schedules_seen, deactivated, status, message)
                   VALUES (?,?,?,?,?,?,?,?)""",
                (started, now_iso(), 0, 0, 0, 0, "error", str(err)),
            )
            conn.commit()
        except Exception:  # noqa: BLE001
            pass
        return 1
    finally:
        conn.close()


def deploy_to_app(db_path: str, app_db_path: str) -> bool:
    """Copy the finished database into the iOS app's bundled resources so a
    rebuilt app ships the latest data.

    No-op (with a warning) when the app's Resources folder is absent, e.g. when
    the sync runs on a server rather than this repo checkout.
    """
    src = Path(db_path)
    dest = Path(app_db_path)
    if not src.exists():
        log.error("Cannot deploy: source database %s does not exist.", src)
        return False
    if not dest.parent.exists():
        log.warning("Skipping app deploy: %s does not exist.", dest.parent)
        return False
    shutil.copy2(src, dest)
    log.info("Deployed database to app: %s", dest)
    return True


def upload_to_storage(db_path: str, *, supabase_url: str, insecure: bool = False) -> bool:
    """Uploads the finished database to Supabase Storage so installed apps can
    fetch fresh data without a new build.

    Requires SUPABASE_SERVICE_ROLE_KEY in the environment (never commit this
    key — it bypasses Row Level Security). Skips with a warning if unset, so
    local manual runs without the secret still succeed.
    """
    service_key = os.environ.get("SUPABASE_SERVICE_ROLE_KEY")
    if not service_key:
        log.warning(
            "Skipping Storage upload: SUPABASE_SERVICE_ROLE_KEY is not set. "
            "Installed apps won't see this run's data until the next app build."
        )
        return False

    src = Path(db_path)
    if not src.exists():
        log.error("Cannot upload: source database %s does not exist.", src)
        return False

    url = (
        f"{supabase_url.rstrip('/')}/storage/v1/object/"
        f"{SUPABASE_STORAGE_BUCKET}/{SUPABASE_STORAGE_OBJECT_PATH}"
    )
    data = src.read_bytes()
    req = urllib.request.Request(
        url,
        data=data,
        method="POST",
        headers={
            "Authorization": f"Bearer {service_key}",
            "apikey": service_key,
            "Content-Type": "application/x-sqlite3",
            # Overwrite the existing object instead of failing on conflict.
            "x-upsert": "true",
        },
    )

    ssl_context = build_ssl_context(insecure)
    try:
        with urllib.request.urlopen(req, timeout=REQUEST_TIMEOUT, context=ssl_context) as resp:
            resp.read()
        log.info("Uploaded database to Supabase Storage: %s/%s (%d bytes)",
                  SUPABASE_STORAGE_BUCKET, SUPABASE_STORAGE_OBJECT_PATH, len(data))
        return True
    except urllib.error.HTTPError as err:
        body = err.read().decode("utf-8", errors="replace")
        log.error("Storage upload failed (%s): %s", err.code, body)
        return False
    except Exception as err:  # noqa: BLE001
        log.error("Storage upload failed: %s", err)
        return False


def parse_args(argv: list[str]) -> argparse.Namespace:
    p = argparse.ArgumentParser(description=__doc__,
                                formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument("--db", default=DEFAULT_DB_PATH,
                   help=f"SQLite database path (default: {DEFAULT_DB_PATH})")
    p.add_argument("--app-db", default=DEFAULT_APP_DB_PATH,
                   help="Destination to copy the finished DB into the app bundle "
                        f"(default: {DEFAULT_APP_DB_PATH})")
    p.add_argument("--no-deploy", action="store_true",
                   help="Do not copy the finished DB into the app bundle")
    p.add_argument("--supabase-url", default=os.environ.get("SUPABASE_URL") or DEFAULT_SUPABASE_URL,
                   help="Supabase project URL for the Storage upload "
                        "(default: env SUPABASE_URL or the app's project)")
    p.add_argument("--no-upload", action="store_true",
                   help="Do not upload the finished DB to Supabase Storage")
    p.add_argument("--insecure", action="store_true",
                   help="Disable TLS certificate verification (last resort)")
    p.add_argument("--radius", type=int, default=DEFAULT_RADIUS_MILES,
                   help=f"Search radius in miles (default: {DEFAULT_RADIUS_MILES})")
    p.add_argument("--map-token", default=MAP_TOKEN,
                   help="accessfood widget map security token")
    p.add_argument("--in-network-only", action="store_true",
                   help="Exclude out-of-network locations")
    p.add_argument("-v", "--verbose", action="store_true", help="Debug logging")
    return p.parse_args(argv)


def main(argv: list[str]) -> int:
    args = parse_args(argv)
    logging.basicConfig(
        level=logging.DEBUG if args.verbose else logging.INFO,
        format="%(asctime)s %(levelname)s %(message)s",
        datefmt="%Y-%m-%d %H:%M:%S",
    )
    code = run_sync(
        args.db,
        radius=args.radius,
        show_out_of_network=not args.in_network_only,
        map_token=args.map_token,
        insecure=args.insecure,
    )
    if code == 0 and not args.no_deploy:
        deploy_to_app(args.db, args.app_db)
    if code == 0 and not args.no_upload:
        upload_to_storage(args.db, supabase_url=args.supabase_url, insecure=args.insecure)
    return code


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
