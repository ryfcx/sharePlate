#!/usr/bin/env python3
"""add a dated entry to changelog."""

from __future__ import annotations

import argparse
import datetime as dt
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
CHANGELOG = ROOT / "CHANGELOG.md"
CATEGORIES = ("Added", "Changed", "Fixed", "Removed", "Security", "Database")


def add_entry(category: str, message: str, date: str, dry_run: bool) -> bool:
    message = " ".join(message.strip().split())
    if not message:
        raise ValueError("The changelog message cannot be empty.")

    bullet = f"- {message}"
    text = CHANGELOG.read_text(encoding="utf-8") if CHANGELOG.exists() else "# SharePlate Changelog\n"
    if bullet in text:
        print("Entry already exists; no change made.")
        return False

    date_heading = f"## {date}"
    category_heading = f"### {category}"

    if date_heading not in text:
        text = text.rstrip() + f"\n\n{date_heading}\n\n{category_heading}\n\n{bullet}\n"
    else:
        date_start = text.index(date_heading)
        next_date = text.find("\n## ", date_start + len(date_heading))
        date_end = len(text) if next_date == -1 else next_date
        date_block = text[date_start:date_end]

        if category_heading in date_block:
            category_start = text.index(category_heading, date_start, date_end)
            next_heading = text.find("\n### ", category_start + len(category_heading), date_end)
            insert_at = date_end if next_heading == -1 else next_heading
            text = text[:insert_at].rstrip() + f"\n{bullet}\n\n" + text[insert_at:].lstrip("\n")
        else:
            insertion = f"\n\n{category_heading}\n\n{bullet}\n"
            text = text[:date_end].rstrip() + insertion + text[date_end:]

    if dry_run:
        print(text)
    else:
        CHANGELOG.write_text(text.rstrip() + "\n", encoding="utf-8")
        print(f"Added {category} entry to {CHANGELOG.relative_to(ROOT)}")
    return True


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--type", choices=CATEGORIES, required=True, dest="category")
    parser.add_argument("--message", required=True)
    parser.add_argument("--date", default=dt.date.today().isoformat(), help="YYYY-MM-DD; defaults to today")
    parser.add_argument("--dry-run", action="store_true")
    args = parser.parse_args()

    try:
        dt.date.fromisoformat(args.date)
        add_entry(args.category, args.message, args.date, args.dry_run)
    except ValueError as error:
        parser.error(str(error))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
