"""
fetch.py – query the GCFD database and print every field for a few locations.

Usage:
    python fetch.py                     # first 3 active locations
    python fetch.py --limit 10          # first 10
    python fetch.py --id 488 490 506    # specific location IDs
    python fetch.py --db path/to/other.db
"""

from __future__ import annotations

import argparse
import sqlite3
from pathlib import Path

DEFAULT_DB = Path(__file__).parent / "gcfd_food.db"


def fetch_locations(
    db_path: str | Path = DEFAULT_DB,
    location_ids: list[int] | None = None,
    limit: int = 3,
) -> list[dict]:
    """Return every field from `locations`, `services`, and `service_schedules`
    for the requested locations (or the first `limit` active ones)."""
    conn = sqlite3.connect(db_path)
    conn.row_factory = sqlite3.Row

    try:
        if location_ids:
            placeholders = ",".join("?" * len(location_ids))
            rows = conn.execute(
                f"SELECT * FROM locations WHERE location_id IN ({placeholders})",
                location_ids,
            ).fetchall()
        else:
            rows = conn.execute(
                "SELECT * FROM locations WHERE is_active = 1 LIMIT ?",
                (limit,),
            ).fetchall()

        results = []
        for row in rows:
            loc = dict(row)
            lid = loc["location_id"]

            loc["services"] = [
                dict(r)
                for r in conn.execute(
                    "SELECT * FROM services WHERE location_id = ?", (lid,)
                ).fetchall()
            ]

            loc["schedules"] = [
                dict(r)
                for r in conn.execute(
                    "SELECT * FROM service_schedules WHERE location_id = ? "
                    "ORDER BY day_of_week, start_time",
                    (lid,),
                ).fetchall()
            ]

            results.append(loc)

        return results

    finally:
        conn.close()


def print_location(loc: dict) -> None:
    """print one spot with all its fields."""
    sep = "─" * 60
    print(sep)
    print(f"  {loc['name']}  (id={loc['location_id']})")
    print(sep)

    # main fields
    skip = {"location_id", "name", "services", "schedules"}
    for key, value in loc.items():
        if key in skip or value in (None, ""):
            continue
        label = key.replace("_", " ").title()
        print(f"  {label:<28} {value}")

    # services
    if loc["services"]:
        print(f"\n  Services ({len(loc['services'])}):")
        for svc in loc["services"]:
            print(f"    • {svc['service_name']} [{svc.get('food_program_type_desc', '')}]")
            for field in ("overview", "qualifications", "notes", "languages", "program_url"):
                val = svc.get(field)
                if val:
                    print(f"        {field}: {val}")

    # hours
    if loc["schedules"]:
        print(f"\n  Schedules ({len(loc['schedules'])}):")
        for s in loc["schedules"]:
            day = s.get("week_day", "")
            start = s.get("start_time_desc", "")
            end = s.get("end_time_desc", "")
            notes = s.get("notes") or s.get("contact_for_hours") or ""
            line = f"    • {day:<12} {start} – {end}"
            if notes:
                line += f"  ({notes})"
            print(line)

    print()


def main() -> None:
    p = argparse.ArgumentParser(description=__doc__,
                                formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument("--db", default=DEFAULT_DB, help="Path to gcfd_food.db")
    p.add_argument("--limit", type=int, default=3,
                   help="Number of locations to show (default 3)")
    p.add_argument("--id", dest="ids", type=int, nargs="+", metavar="ID",
                   help="Specific location_id values to fetch")
    args = p.parse_args()

    locations = fetch_locations(
        db_path=args.db,
        location_ids=args.ids,
        limit=args.limit,
    )

    print(f"\nFetched {len(locations)} location(s) from {args.db}\n")
    for loc in locations:
        print_location(loc)


if __name__ == "__main__":
    main()