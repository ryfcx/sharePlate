#!/usr/bin/env python3
"""Run the Supabase donor-listing job once and print how many are live.

The job itself is scheduled inside the database and runs once an hour.
This script only calls that same function. It keeps the 15 Lincoln Park
spots and does not create a second pool.
"""

from __future__ import annotations

import datetime as dt
import json
import os
import ssl
import sys
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
DEFAULT_SUPABASE_URL = "https://fkcsgxywdpcdwdlhflgv.supabase.co"
POSTER_EMAIL = "shareplate.auto.donor@example.com"
TARGET = 15


class MaintainError(RuntimeError):
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


def request(url: str, key: str, method: str, path: str, body: dict | None = None):
    try:
        import certifi

        context = ssl.create_default_context(cafile=certifi.where())
    except ImportError:
        context = ssl.create_default_context()
    payload = None if body is None else json.dumps(body).encode("utf-8")
    headers = {
        "apikey": key,
        "Authorization": f"Bearer {key}",
        "Content-Type": "application/json",
    }
    req = urllib.request.Request(f"{url}{path}", data=payload, headers=headers, method=method)
    try:
        with urllib.request.urlopen(req, timeout=45, context=context) as response:
            raw = response.read()
            return json.loads(raw) if raw else None
    except urllib.error.HTTPError as error:
        detail = error.read().decode("utf-8", errors="replace")
        raise MaintainError(f"{method} {path} failed ({error.code}): {detail}") from error
    except urllib.error.URLError as error:
        raise MaintainError(f"Could not reach Supabase: {error.reason}") from error


def main() -> int:
    load_dotenv()
    url = os.environ.get("SUPABASE_URL", DEFAULT_SUPABASE_URL).strip().rstrip("/")
    key = os.environ.get("SUPABASE_SERVICE_ROLE_KEY", "").strip()
    if not key:
        raise MaintainError("SUPABASE_SERVICE_ROLE_KEY is not set.")

    request(url, key, "POST", "/rest/v1/rpc/maintain_donor_listings", {})
    users = request(url, key, "GET", "/auth/v1/admin/users?page=1&per_page=1000")
    poster = next(
        user["id"]
        for user in users.get("users", [])
        if str(user.get("email", "")).lower() == POSTER_EMAIL
    )
    now = dt.datetime.now(dt.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
    live = request(
        url,
        key,
        "GET",
        "/rest/v1/listings?select=id,pickup_type"
        f"&posted_by=eq.{urllib.parse.quote(poster, safe='')}"
        f"&status=eq.available&pickup_deadline=gt.{urllib.parse.quote(now, safe='')}",
    ) or []
    dropoff = sum(1 for row in live if row.get("pickup_type") == "communityFridge")
    print(json.dumps({
        "live": len(live),
        "target": TARGET,
        "pickup": len(live) - dropoff,
        "dropoff": dropoff,
    }))
    return 0 if len(live) == TARGET else 1


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except MaintainError as error:
        print(f"error: {error}", file=sys.stderr)
        raise SystemExit(1)
