#!/usr/bin/env python3
"""Seed and remove Chicago-only person-to-person SharePlate demo listings."""

from __future__ import annotations

import argparse
import datetime as dt
import json
import mimetypes
import os
import re
import secrets
import ssl
import sys
import urllib.error
import urllib.parse
import urllib.request
import uuid
from pathlib import Path
from typing import Any


ROOT = Path(__file__).resolve().parents[1]
DEFAULT_MANIFEST = ROOT / "demo" / "listings.json"
DEFAULT_IMAGES = ROOT / "demo" / "images"
STATE_FILE = ROOT / "demo" / ".seed-state.json"
DEFAULT_SUPABASE_URL = "https://fkcsgxywdpcdwdlhflgv.supabase.co"
PHOTO_BUCKET = "listing-photos"
SEED_TAG = "shareplate_chicago_demo_v1"

# Conservative bounding box around the City of Chicago. Every manifest entry
# must pass this check; the script has no flag for bypassing it.
CHICAGO_BOUNDS = {
    "min_latitude": 41.64,
    "max_latitude": 42.03,
    "min_longitude": -87.94,
    "max_longitude": -87.52,
}
VALID_CATEGORIES = {
    "preparedMeals",
    "produce",
    "bakery",
    "pantry",
    "drinks",
    "mixed",
    "other",
}
VALID_PICKUP_TYPES = {"porch", "lobby", "meetOutside", "frontDesk", "communityFridge"}
VALID_DROPOFF_RADIUS_MILES = {1, 3, 5, 10}
METERS_PER_MILE = 1_609
DROPOFF_PICKUP_TYPE = "communityFridge"


class SeedError(RuntimeError):
    pass


def load_dotenv() -> None:
    env_file = ROOT / ".env"
    if not env_file.exists():
        return
    for raw_line in env_file.read_text(encoding="utf-8").splitlines():
        line = raw_line.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        key, value = line.split("=", 1)
        os.environ.setdefault(key.strip(), value.strip().strip("'\""))


class SupabaseAdmin:
    def __init__(self, url: str, service_key: str) -> None:
        self.url = url.rstrip("/")
        self.service_key = service_key
        try:
            import certifi

            self.ssl_context = ssl.create_default_context(cafile=certifi.where())
        except ImportError:
            self.ssl_context = ssl.create_default_context()

    def request(
        self,
        method: str,
        path: str,
        *,
        json_body: Any | None = None,
        raw_body: bytes | None = None,
        extra_headers: dict[str, str] | None = None,
    ) -> Any:
        headers = {
            "apikey": self.service_key,
            "Authorization": f"Bearer {self.service_key}",
        }
        if extra_headers:
            headers.update(extra_headers)

        body = raw_body
        if json_body is not None:
            body = json.dumps(json_body, separators=(",", ":")).encode("utf-8")
            headers["Content-Type"] = "application/json"

        request = urllib.request.Request(
            f"{self.url}{path}",
            data=body,
            headers=headers,
            method=method,
        )
        try:
            with urllib.request.urlopen(request, timeout=45, context=self.ssl_context) as response:
                payload = response.read()
                if not payload:
                    return None
                return json.loads(payload)
        except urllib.error.HTTPError as error:
            detail = error.read().decode("utf-8", errors="replace")
            raise SeedError(f"{method} {path} failed ({error.code}): {detail}") from error
        except urllib.error.URLError as error:
            raise SeedError(f"Could not reach Supabase: {error.reason}") from error

    def existing_users(self) -> dict[str, str]:
        response = self.request("GET", "/auth/v1/admin/users?page=1&per_page=1000")
        users = response.get("users", []) if isinstance(response, dict) else response or []
        return {
            str(user.get("email", "")).lower(): str(user["id"])
            for user in users
            if user.get("email") and user.get("id")
        }

    def ensure_demo_user(self, provider_name: str, users: dict[str, str]) -> str:
        slug = re.sub(r"[^a-z0-9]+", ".", provider_name.lower()).strip(".") or "provider"
        email = f"shareplate.demo.{slug}@example.com"
        if email in users:
            return users[email]

        response = self.request(
            "POST",
            "/auth/v1/admin/users",
            json_body={
                "email": email,
                "password": secrets.token_urlsafe(24),
                "email_confirm": True,
                "user_metadata": {
                    "display_name": provider_name,
                    "shareplate_demo_user": True,
                },
            },
        )
        user_id = str(response["id"])
        users[email] = user_id
        return user_id

    def upload_photo(self, object_path: str, image_path: Path) -> None:
        content_type = mimetypes.guess_type(image_path.name)[0] or "application/octet-stream"
        encoded_path = "/".join(urllib.parse.quote(part, safe="") for part in object_path.split("/"))
        self.request(
            "POST",
            f"/storage/v1/object/{PHOTO_BUCKET}/{encoded_path}",
            raw_body=image_path.read_bytes(),
            extra_headers={"Content-Type": content_type, "x-upsert": "true"},
        )

    def remove_photos(self, object_paths: list[str]) -> None:
        if object_paths:
            self.request(
                "DELETE",
                f"/storage/v1/object/{PHOTO_BUCKET}",
                json_body={"prefixes": object_paths},
            )

    def insert_listing(self, payload: dict[str, Any]) -> dict[str, Any]:
        response = self.request(
            "POST",
            "/rest/v1/listings",
            json_body=payload,
            extra_headers={"Prefer": "return=representation"},
        )
        if not isinstance(response, list) or not response:
            raise SeedError("Supabase did not return the inserted listing.")
        return response[0]

    def delete_listing(self, listing_id: str) -> None:
        self.request(
            "DELETE",
            f"/rest/v1/listings?id=eq.{urllib.parse.quote(listing_id, safe='')}",
            extra_headers={"Prefer": "return=minimal"},
        )

    def delete_user(self, user_id: str) -> None:
        self.request("DELETE", f"/auth/v1/admin/users/{urllib.parse.quote(user_id, safe='')}")


def load_manifest(path: Path, images_dir: Path) -> list[dict[str, Any]]:
    try:
        raw = json.loads(path.read_text(encoding="utf-8"))
    except FileNotFoundError as error:
        raise SeedError(f"Manifest not found: {path}") from error
    except json.JSONDecodeError as error:
        raise SeedError(f"Manifest contains invalid JSON: {error}") from error

    if not isinstance(raw, list) or not raw:
        raise SeedError("Manifest must contain a non-empty JSON array.")

    required = {
        "provider",
        "title",
        "category",
        "packages",
        "max_per_booking",
        "pickup_type",
        "area",
        "pickup_address",
        "latitude",
        "longitude",
        "deadline_hours",
        "image",
    }
    validated: list[dict[str, Any]] = []
    images_root = images_dir.resolve()

    for index, listing in enumerate(raw, start=1):
        if not isinstance(listing, dict):
            raise SeedError(f"Listing {index} must be a JSON object.")
        missing = sorted(required - listing.keys())
        if missing:
            raise SeedError(f"Listing {index} is missing: {', '.join(missing)}")

        category = str(listing["category"])
        pickup_type = str(listing["pickup_type"])
        packages = int(listing["packages"])
        maximum = int(listing["max_per_booking"])
        latitude = float(listing["latitude"])
        longitude = float(listing["longitude"])
        deadline_hours = float(listing["deadline_hours"])

        if category not in VALID_CATEGORIES:
            raise SeedError(f"Listing {index} has unsupported category: {category}")
        if pickup_type not in VALID_PICKUP_TYPES:
            raise SeedError(
                f"Listing {index} must use a person-to-person pickup or drop-off type, not {pickup_type!r}."
            )

        dropoff_radius_miles = listing.get("dropoff_radius_miles")
        if pickup_type == DROPOFF_PICKUP_TYPE:
            if dropoff_radius_miles is None:
                raise SeedError(
                    f"Listing {index} is drop-off and must include dropoff_radius_miles "
                    f"({', '.join(str(value) for value in sorted(VALID_DROPOFF_RADIUS_MILES))})."
                )
            dropoff_radius_miles = int(dropoff_radius_miles)
            if dropoff_radius_miles not in VALID_DROPOFF_RADIUS_MILES:
                raise SeedError(
                    f"Listing {index} dropoff_radius_miles must be one of "
                    f"{sorted(VALID_DROPOFF_RADIUS_MILES)}."
                )
        elif dropoff_radius_miles is not None:
            raise SeedError(f"Listing {index} is pickup and cannot include dropoff_radius_miles.")
        if not 1 <= packages <= 8 or not 1 <= maximum <= packages:
            raise SeedError(f"Listing {index} must have 1–8 packages and a valid per-booking maximum.")
        if not 0.5 <= deadline_hours <= 72:
            raise SeedError(f"Listing {index} deadline_hours must be between 0.5 and 72.")
        if not (
            CHICAGO_BOUNDS["min_latitude"] <= latitude <= CHICAGO_BOUNDS["max_latitude"]
            and CHICAGO_BOUNDS["min_longitude"] <= longitude <= CHICAGO_BOUNDS["max_longitude"]
        ):
            raise SeedError(
                f"Listing {index} is outside the enforced Chicago boundary "
                f"({latitude}, {longitude})."
            )

        image_path = (images_dir / str(listing["image"])).resolve()
        if images_root not in image_path.parents:
            raise SeedError(f"Listing {index} image path escapes the demo image directory.")
        if not image_path.is_file():
            raise SeedError(f"Missing image for listing {index}: {image_path}")
        if image_path.suffix.lower() not in {".jpg", ".jpeg", ".png"}:
            raise SeedError(f"Listing {index} image must be JPG or PNG.")
        if image_path.stat().st_size > 10 * 1024 * 1024:
            raise SeedError(f"Listing {index} image exceeds 10 MB: {image_path.name}")

        item = dict(listing)
        item.update(
            packages=packages,
            max_per_booking=maximum,
            latitude=latitude,
            longitude=longitude,
            deadline_hours=deadline_hours,
            image_path=image_path,
            dropoff_radius_miles=dropoff_radius_miles,
        )
        validated.append(item)

    return validated


def iso8601(value: dt.datetime) -> str:
    return value.astimezone(dt.timezone.utc).isoformat(timespec="seconds").replace("+00:00", "Z")


def quantity_size(packages: int) -> str:
    if packages <= 1:
        return "feeds1to2"
    if packages <= 3:
        return "feeds3to5"
    return "feeds10plus"


def quantity_label(packages: int, maximum: int) -> str:
    if packages == 1:
        return "1 package"
    if maximum >= packages:
        return f"{packages} packages"
    return f"{packages} packages · max {maximum} each"


def dropoff_radius_label(miles: int) -> str:
    return f"{miles} mi"


def build_payload(item: dict[str, Any], provider_id: str, listing_id: str) -> dict[str, Any]:
    now = dt.datetime.now(dt.timezone.utc)
    deadline = now + dt.timedelta(hours=item["deadline_hours"])
    ready_time = min(now + dt.timedelta(minutes=30), deadline)
    is_dropoff = item["pickup_type"] == DROPOFF_PICKUP_TYPE
    radius_miles = item.get("dropoff_radius_miles")
    pickup_address = (
        f"Within {dropoff_radius_label(int(radius_miles))}"
        if is_dropoff and radius_miles is not None
        else item["pickup_address"]
    )
    meetup_address = f"Near {item['area']}" if is_dropoff else item["pickup_address"]
    contact_instructions = {
        "meetupAddress": meetup_address,
        "handoffSpot": "outside",
        "timeslot": iso8601(ready_time),
        "meetupLatitude": item["latitude"],
        "meetupLongitude": item["longitude"],
        "providerNote": item.get("provider_note", ""),
        "consumerDropOffAddress": "",
        "instructionsPublished": True,
    }
    details_parts = [
        f"packages_total={item['packages']}",
        f"packages_max={item['max_per_booking']}",
        f"packages_remaining={item['packages']}",
        f"demo_seed={SEED_TAG}",
    ]
    if is_dropoff and radius_miles is not None:
        details_parts.append(f"dropoff_radius_meters={int(radius_miles) * METERS_PER_MILE}")
    details = ";".join(details_parts)

    return {
        "id": listing_id,
        "title": item["title"],
        "details": details,
        "quantity": quantity_label(item["packages"], item["max_per_booking"]),
        "category": item["category"],
        "quantity_size": quantity_size(item["packages"]),
        "pickup_type": item["pickup_type"],
        "area": item["area"],
        "photo_url": None,
        "pickup_address": pickup_address,
        "latitude": item["latitude"],
        "longitude": item["longitude"],
        "pickup_deadline": iso8601(deadline),
        "pickup_notes": item.get("pickup_notes"),
        "contact_instructions": json.dumps(contact_instructions, separators=(",", ":")),
        "status": "available",
        "posted_by": provider_id,
        "claimed_by": None,
        "reserved_until": None,
        "pantry_gcfd_location_id": None,
    }


def write_state(state: dict[str, Any]) -> None:
    STATE_FILE.parent.mkdir(parents=True, exist_ok=True)
    STATE_FILE.write_text(json.dumps(state, indent=2) + "\n", encoding="utf-8")


def clean(admin: SupabaseAdmin, *, delete_users: bool = False, quiet: bool = False) -> None:
    if not STATE_FILE.exists():
        if not quiet:
            print("No demo seed state found; nothing to clean.")
        return

    state = json.loads(STATE_FILE.read_text(encoding="utf-8"))
    entries = state.get("listings", [])
    for entry in entries:
        admin.delete_listing(str(entry["id"]))
        if not quiet:
            print(f"Deleted listing {entry['id']}")

    admin.remove_photos([str(entry["photo_path"]) for entry in entries if entry.get("photo_path")])

    if delete_users:
        for user_id in sorted(set(state.get("provider_user_ids", []))):
            admin.delete_user(str(user_id))
            if not quiet:
                print(f"Deleted demo provider {user_id}")

    STATE_FILE.unlink(missing_ok=True)
    if not quiet:
        print("Chicago demo listings removed.")


def seed(
    admin: SupabaseAdmin,
    manifest: list[dict[str, Any]],
    *,
    replace: bool,
) -> None:
    if STATE_FILE.exists():
        if not replace:
            raise SeedError(
                f"{STATE_FILE.relative_to(ROOT)} already exists. "
                "Run the clean command or seed again with --replace."
            )
        clean(admin, quiet=True)

    users = admin.existing_users()
    state: dict[str, Any] = {
        "seed_tag": SEED_TAG,
        "created_at": iso8601(dt.datetime.now(dt.timezone.utc)),
        "provider_user_ids": [],
        "listings": [],
    }

    for item in manifest:
        provider_id = admin.ensure_demo_user(str(item["provider"]), users)
        listing_id = str(uuid.uuid4())
        suffix = item["image_path"].suffix.lower()
        if suffix == ".jpeg":
            suffix = ".jpg"
        photo_path = f"{provider_id.lower()}/{listing_id.lower()}{suffix}"
        payload = build_payload(item, provider_id, listing_id)
        payload["photo_url"] = photo_path

        admin.upload_photo(photo_path, item["image_path"])
        try:
            admin.insert_listing(payload)
        except Exception:
            admin.remove_photos([photo_path])
            raise

        state["provider_user_ids"].append(provider_id)
        state["provider_user_ids"] = sorted(set(state["provider_user_ids"]))
        state["listings"].append(
            {
                "id": listing_id,
                "title": item["title"],
                "provider": item["provider"],
                "provider_user_id": provider_id,
                "photo_path": photo_path,
            }
        )
        write_state(state)
        print(f"Seeded {item['title']} in {item['area']} ({listing_id})")

    print(f"Seeded {len(manifest)} Chicago person-to-person listings.")
    print(f"Cleanup state saved to {STATE_FILE.relative_to(ROOT)}")


def make_admin() -> SupabaseAdmin:
    load_dotenv()
    url = os.environ.get("SUPABASE_URL", DEFAULT_SUPABASE_URL).strip()
    key = os.environ.get("SUPABASE_SERVICE_ROLE_KEY", "").strip()
    if not key:
        raise SeedError(
            "SUPABASE_SERVICE_ROLE_KEY is not set. Add it to the repository's local .env file."
        )
    return SupabaseAdmin(url, key)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    subparsers = parser.add_subparsers(dest="command", required=True)

    validate_parser = subparsers.add_parser("validate", help="Validate the manifest and images only")
    seed_parser = subparsers.add_parser("seed", help="Upload photos and create demo listings")
    clean_parser = subparsers.add_parser("clean", help="Remove listings created by this script")

    for command_parser in (validate_parser, seed_parser):
        command_parser.add_argument("--manifest", type=Path, default=DEFAULT_MANIFEST)
        command_parser.add_argument("--images", type=Path, default=DEFAULT_IMAGES)
    seed_parser.add_argument("--replace", action="store_true", help="Replace a previous seeded batch")
    clean_parser.add_argument(
        "--delete-users",
        action="store_true",
        help="Also delete the dedicated demo Auth users",
    )

    args = parser.parse_args()
    try:
        if args.command == "validate":
            manifest = load_manifest(args.manifest, args.images)
            print(f"Validated {len(manifest)} listings; all coordinates are within Chicago.")
            return 0

        admin = make_admin()
        if args.command == "clean":
            clean(admin, delete_users=args.delete_users)
        else:
            manifest = load_manifest(args.manifest, args.images)
            seed(admin, manifest, replace=args.replace)
        return 0
    except (SeedError, OSError, ValueError) as error:
        print(f"error: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
