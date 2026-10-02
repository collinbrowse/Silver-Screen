#!/usr/bin/env python3
"""Compare TMDB US watch-provider IDs to StreamingProviderLaunch.swift mappings."""

from __future__ import annotations

import json
import re
import sys
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
LAUNCH_FILE = ROOT / "TheSilverScreen" / "Support" / "StreamingProviderLaunch.swift"
SECRETS = ROOT / "Secrets.xcconfig"

SKIP_NAME_PARTS = (
    "amazon channel",
    "roku premium",
    "apple tv channel",
    " amazon channel",
)

# First-party apps we expect to open on iOS (TMDB provider_name substrings, lowercased).
FIRST_PARTY_NAME_MARKERS = (
    "netflix",
    "amazon prime video",
    "disney plus",
    "disneynow",
    "hulu",
    "hbo max",
    "max",
    "paramount plus",
    "peacock premium",
    "apple tv",
    "crunchyroll",
    "starz",
    "discovery +",
    "pluto tv",
    "espn",
    "fubotv",
    "youtube tv",
    "youtube premium",
    "youtube free",
    "youtube",
    "amc+",
    "tubi tv",
    "plex",
    "mgm plus",
    "mubi",
    "shudder",
    "acorn tv",
    "britbox",
    "curiosity stream",
    "criterion channel",
    "philo",
    "sling tv",
    "hoichoi",
    "rakuten viki",
    "hidive",
    "kocowa",
    "allblk",
    "pure flix",
    "hoopla",
    "kanopy",
    "showtime",
)


def read_api_key() -> str:
    if not SECRETS.is_file():
        print("Secrets.xcconfig missing; skip TMDB fetch.", file=sys.stderr)
        sys.exit(0)
    for line in SECRETS.read_text().splitlines():
        if line.strip().startswith("TMDB_API_KEY"):
            return line.split("=", 1)[1].strip()
    print("TMDB_API_KEY not found in Secrets.xcconfig", file=sys.stderr)
    sys.exit(1)


def fetch_providers(path: str, api_key: str) -> dict[int, str]:
    query = urllib.parse.urlencode({"watch_region": "US", "api_key": api_key})
    url = f"https://api.themoviedb.org/3/{path}?{query}"
    with urllib.request.urlopen(url, timeout=30) as response:
        payload = json.load(response)
    return {entry["provider_id"]: entry["provider_name"] for entry in payload["results"]}


def mapped_ids() -> set[int]:
    text = LAUNCH_FILE.read_text()
    ids: set[int] = set()
    for match in re.finditer(r"assign\([^,]+,\s*ids:\s*([0-9,\s]+)\)", text):
        chunk = match.group(1)
        ids.update(int(part.strip()) for part in chunk.split(",") if part.strip())
    return ids


def is_first_party(name: str) -> bool:
    lowered = name.lower()
    if any(part in lowered for part in SKIP_NAME_PARTS):
        return False
    return any(marker in lowered for marker in FIRST_PARTY_NAME_MARKERS)


def main() -> None:
    api_key = read_api_key()
    movie = fetch_providers("watch/providers/movie", api_key)
    tv = fetch_providers("watch/providers/tv", api_key)
    catalog = movie | tv
    mapped = mapped_ids()

    missing: list[tuple[int, str]] = []
    for provider_id, name in sorted(catalog.items()):
        if not is_first_party(name):
            continue
        if provider_id not in mapped:
            missing.append((provider_id, name))

    if missing:
        print("Missing StreamingProviderLaunch mappings for US first-party providers:")
        for provider_id, name in missing:
            print(f"  {provider_id}\t{name}")
        sys.exit(1)

    print(
        f"OK: {len(mapped)} mapped IDs; "
        f"all {len(catalog)} US catalog entries checked for first-party coverage."
    )


if __name__ == "__main__":
    main()
