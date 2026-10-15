#!/usr/bin/env python3
"""Daily TMDB health check: call the endpoints the app uses and check their shape.

The schemas below mirror the DTOs in SilverScreen/Data/Networking. A field the
DTO decodes with `decode` is required here; one it decodes with `decodeIfPresent`
is Opt(...). Appended sections (`append_to_response`) are optional in the app,
which degrades quietly without them, so they are required here: a quiet
degradation is exactly what this check is for.

    TMDB_ACCESS_TOKEN=... python3 scripts/tmdb_health.py
    python3 scripts/tmdb_health.py --file-issue   # on CI: open or comment on an issue

Exit status is 1 when any check fails. No pip packages.
"""

from __future__ import annotations

import argparse
import datetime as dt
import json
import os
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
from dataclasses import dataclass, field
from typing import Any, Dict, List, Optional

import github_issues

ISSUE_LABEL = "tmdb-health"
BASE_URL = "https://api.themoviedb.org/3"
MAX_ERRORS_PER_CHECK = 10


# Schema vocabulary --------------------------------------------------------


class Opt:
    """Absent or null is fine; otherwise the value must match `spec`."""

    def __init__(self, spec):
        self.spec = spec


class ListOf:
    """A JSON array of `spec`.

    lossy: the app skips bad rows (TMDBPageDecoding, OptionalElement), so one
    bad row is not a failure. Most rows failing still is.
    """

    def __init__(self, spec, lossy=False, min_items=0):
        self.spec = spec
        self.lossy = lossy
        self.min_items = min_items


class MapOf:
    """A JSON object with arbitrary keys (such as region codes) whose values match `spec`."""

    def __init__(self, spec):
        self.spec = spec


def _type_name(value):
    if value is None:
        return "null"
    if isinstance(value, bool):
        return "bool"
    if isinstance(value, (int, float)):
        return "number"
    if isinstance(value, str):
        return "string"
    if isinstance(value, list):
        return "array"
    return "object"


def _scalar_ok(kind, value):
    if kind == "str":
        return isinstance(value, str)
    if kind == "bool":
        return isinstance(value, bool)
    if kind == "num":
        # Swift Double decodes any JSON number.
        return isinstance(value, (int, float)) and not isinstance(value, bool)
    if kind == "int":
        # Swift Int decodes 5 and 5.0, not 5.5.
        if isinstance(value, bool):
            return False
        return isinstance(value, int) or (isinstance(value, float) and value.is_integer())
    raise ValueError(f"unknown scalar kind {kind!r}")


def validate(value, spec, path="$"):
    """Problems with `value` against `spec`, as 'path: message' strings."""
    if isinstance(spec, Opt):
        if value is None:
            return []
        return validate(value, spec.spec, path)
    if value is None:
        return [f"{path}: missing or null"]
    if isinstance(spec, str):
        if _scalar_ok(spec, value):
            return []
        return [f"{path}: expected {spec}, got {_type_name(value)}"]
    if isinstance(spec, dict):
        if not isinstance(value, dict):
            return [f"{path}: expected object, got {_type_name(value)}"]
        errors = []
        for key, child in spec.items():
            errors.extend(validate(value.get(key), child, f"{path}.{key}"))
        return errors
    if isinstance(spec, MapOf):
        if not isinstance(value, dict):
            return [f"{path}: expected object, got {_type_name(value)}"]
        errors = []
        for key, child in value.items():
            errors.extend(validate(child, spec.spec, f"{path}.{key}"))
        return errors
    if isinstance(spec, ListOf):
        if not isinstance(value, list):
            return [f"{path}: expected array, got {_type_name(value)}"]
        if len(value) < spec.min_items:
            return [f"{path}: expected at least {spec.min_items} item(s), got {len(value)}"]
        per_item = [validate(item, spec.spec, f"{path}[{index}]") for index, item in enumerate(value)]
        bad = [errors for errors in per_item if errors]
        if not bad:
            return []
        if spec.lossy and len(bad) * 2 <= len(value):
            return []
        errors = [error for item_errors in bad[:3] for error in item_errors]
        if spec.lossy:
            errors.insert(0, f"{path}: {len(bad)} of {len(value)} rows fail to decode")
        return errors
    raise ValueError(f"unknown spec at {path}: {spec!r}")


# DTO schemas ---------------------------------------------------------------

STR, INT, NUM, BOOL = "str", "int", "num", "bool"

GENRE = {"id": INT, "name": STR}
IMAGE = {"file_path": STR, "vote_average": Opt(NUM)}
IMAGES = {
    "backdrops": Opt(ListOf(IMAGE)),
    "posters": Opt(ListOf(IMAGE)),
    "stills": Opt(ListOf(IMAGE)),
}
CAST = {
    "id": INT,
    "credit_id": Opt(STR),
    "name": Opt(STR),
    "character": Opt(STR),
    "profile_path": Opt(STR),
    "order": Opt(INT),
    "known_for_department": Opt(STR),
}
CREW = {
    "id": INT,
    "credit_id": Opt(STR),
    "name": Opt(STR),
    "job": Opt(STR),
    "department": Opt(STR),
    "profile_path": Opt(STR),
    "known_for_department": Opt(STR),
}
MOVIE_SUMMARY = {
    "id": INT,
    "title": STR,
    "poster_path": Opt(STR),
    "release_date": Opt(STR),
    "vote_average": NUM,
    "genre_ids": Opt(ListOf(INT)),
    "popularity": Opt(NUM),
}
TV_SUMMARY = {
    "id": INT,
    "name": Opt(STR),
    "poster_path": Opt(STR),
    "first_air_date": Opt(STR),
    "genre_ids": Opt(ListOf(INT)),
    "vote_average": Opt(NUM),
    "popularity": Opt(NUM),
}
PERSON_SUMMARY = {
    "id": INT,
    "name": Opt(STR),
    "profile_path": Opt(STR),
    "known_for_department": Opt(STR),
    "popularity": Opt(NUM),
}
VIDEOS = {
    "results": ListOf(
        {
            "name": Opt(STR),
            "key": Opt(STR),
            "site": Opt(STR),
            "type": Opt(STR),
            "official": Opt(BOOL),
        }
    )
}
PROVIDER = {
    "provider_id": INT,
    "provider_name": STR,
    "logo_path": Opt(STR),
    "display_priority": Opt(INT),
}
WATCH_PROVIDERS = {"results": MapOf({"flatrate": Opt(ListOf(PROVIDER))})}


def page(item):
    return {
        "page": INT,
        "results": ListOf(item, lossy=True, min_items=1),
        "total_pages": INT,
        "total_results": INT,
    }


MOVIE_DETAIL = {
    "id": INT,
    "title": STR,
    "overview": Opt(STR),
    "poster_path": Opt(STR),
    "release_date": Opt(STR),
    "vote_average": NUM,
    "popularity": Opt(NUM),
    "runtime": Opt(INT),
    "genres": Opt(ListOf(GENRE)),
    "budget": Opt(INT),
    "revenue": Opt(INT),
    "belongs_to_collection": Opt({"id": INT, "name": STR, "poster_path": Opt(STR)}),
    "images": IMAGES,
    "credits": {"cast": ListOf(CAST, min_items=1), "crew": ListOf(CREW)},
    "similar": {"results": ListOf(MOVIE_SUMMARY, lossy=True)},
    "videos": VIDEOS,
    "watch/providers": WATCH_PROVIDERS,
}
COLLECTION = {
    "id": INT,
    "name": STR,
    "overview": Opt(STR),
    "poster_path": Opt(STR),
    "parts": ListOf(MOVIE_SUMMARY, min_items=1),
}
REVIEWS = {
    "results": ListOf(
        {
            "id": STR,
            "author": Opt(STR),
            "content": Opt(STR),
            "updated_at": Opt(STR),
            "author_details": Opt({"username": Opt(STR)}),
        },
        min_items=1,
    ),
    "total_results": Opt(INT),
}
TV_AGGREGATE_CREDITS = {
    "cast": ListOf(
        {
            "id": INT,
            "name": Opt(STR),
            "profile_path": Opt(STR),
            "known_for_department": Opt(STR),
            "total_episode_count": Opt(INT),
            "roles": Opt(ListOf({"character": Opt(STR), "episode_count": Opt(INT)})),
        },
        lossy=True,
        min_items=1,
    ),
    "crew": ListOf(
        {
            "id": INT,
            "name": Opt(STR),
            "profile_path": Opt(STR),
            "department": Opt(STR),
            "known_for_department": Opt(STR),
            "total_episode_count": Opt(INT),
            "jobs": Opt(ListOf({"job": Opt(STR), "episode_count": Opt(INT)})),
        },
        lossy=True,
    ),
}
TV_DETAIL = {
    "id": INT,
    "name": STR,
    "overview": Opt(STR),
    "poster_path": Opt(STR),
    "first_air_date": Opt(STR),
    "last_air_date": Opt(STR),
    "genres": Opt(ListOf(GENRE)),
    "created_by": Opt(ListOf({"id": INT, "name": Opt(STR)})),
    "seasons": ListOf(
        {
            "id": INT,
            "name": Opt(STR),
            "season_number": INT,
            "episode_count": Opt(INT),
            "air_date": Opt(STR),
            "poster_path": Opt(STR),
        },
        min_items=1,
    ),
    "vote_average": Opt(NUM),
    "popularity": Opt(NUM),
    "images": IMAGES,
    "aggregate_credits": TV_AGGREGATE_CREDITS,
    "recommendations": {"results": ListOf(TV_SUMMARY, lossy=True)},
    "videos": VIDEOS,
    "watch/providers": WATCH_PROVIDERS,
}
TV_SEASON = {
    "id": INT,
    "name": Opt(STR),
    "overview": Opt(STR),
    "season_number": INT,
    "air_date": Opt(STR),
    "poster_path": Opt(STR),
    "episodes": ListOf(
        {
            "id": INT,
            "name": Opt(STR),
            "overview": Opt(STR),
            "episode_number": INT,
            "air_date": Opt(STR),
            "still_path": Opt(STR),
            "crew": Opt(ListOf(CREW)),
        },
        min_items=1,
    ),
    "vote_average": Opt(NUM),
    "images": IMAGES,
    "aggregate_credits": TV_AGGREGATE_CREDITS,
    "videos": VIDEOS,
}
TV_EPISODE = {
    "id": INT,
    "name": Opt(STR),
    "overview": Opt(STR),
    "episode_number": INT,
    "air_date": Opt(STR),
    "still_path": Opt(STR),
    "vote_average": Opt(NUM),
    "crew": Opt(ListOf(CREW)),
    "guest_stars": Opt(ListOf(CAST)),
    "credits": {
        "cast": Opt(ListOf(CAST)),
        "crew": Opt(ListOf(CREW)),
        "guest_stars": Opt(ListOf(CAST)),
    },
    "images": IMAGES,
    "videos": VIDEOS,
}
PERSON_CREDIT = {
    "id": INT,
    "media_type": Opt(STR),
    "title": Opt(STR),
    "name": Opt(STR),
    "poster_path": Opt(STR),
    "release_date": Opt(STR),
    "first_air_date": Opt(STR),
    "genre_ids": Opt(ListOf(INT)),
    "character": Opt(STR),
    "job": Opt(STR),
    "department": Opt(STR),
    "popularity": Opt(NUM),
    "vote_average": Opt(NUM),
    "order": Opt(INT),
    "vote_count": Opt(INT),
    "episode_count": Opt(INT),
}
PERSON_DETAIL = {
    "id": INT,
    "name": STR,
    "biography": Opt(STR),
    "birthday": Opt(STR),
    "deathday": Opt(STR),
    "place_of_birth": Opt(STR),
    "profile_path": Opt(STR),
    "known_for_department": Opt(STR),
    "popularity": Opt(NUM),
    "images": {"profiles": ListOf(IMAGE)},
    "combined_credits": {
        "cast": ListOf(PERSON_CREDIT, min_items=1),
        "crew": ListOf(PERSON_CREDIT),
    },
    "external_ids": {"imdb_id": Opt(STR)},
}


# Checks --------------------------------------------------------------------

# Long-lived titles with full data: Fight Club, its collection-bearing sibling
# Star Wars, Game of Thrones, and Brad Pitt.
MOVIE_ID = 550
COLLECTION_ID = 10
TV_ID = 1399
PERSON_ID = 287
LANG = {"language": "en-US"}
IMAGE_LANG = {"include_image_language": "en,null"}


@dataclass(frozen=True)
class Check:
    name: str
    path: str
    query: Dict[str, str]
    schema: Any


CHECKS = [
    Check(
        "Movie detail",
        f"movie/{MOVIE_ID}",
        {**LANG, **IMAGE_LANG, "append_to_response": "credits,images,similar,videos,watch/providers"},
        MOVIE_DETAIL,
    ),
    Check("Movie collection", f"collection/{COLLECTION_ID}", LANG, COLLECTION),
    Check("Movie reviews", f"movie/{MOVIE_ID}/reviews", LANG, REVIEWS),
    Check(
        "TV series",
        f"tv/{TV_ID}",
        {**LANG, **IMAGE_LANG, "append_to_response": "images,aggregate_credits,recommendations,videos,watch/providers"},
        TV_DETAIL,
    ),
    Check(
        "TV season",
        f"tv/{TV_ID}/season/1",
        {**LANG, "append_to_response": "images,aggregate_credits,videos"},
        TV_SEASON,
    ),
    Check(
        "TV episode",
        f"tv/{TV_ID}/season/1/episode/1",
        {**LANG, "append_to_response": "images,credits,videos"},
        TV_EPISODE,
    ),
    Check("TV watch providers", f"tv/{TV_ID}/watch/providers", LANG, WATCH_PROVIDERS),
    Check(
        "Person",
        f"person/{PERSON_ID}",
        {**LANG, "append_to_response": "combined_credits,images,external_ids"},
        PERSON_DETAIL,
    ),
    Check("Now playing", "movie/now_playing", {**LANG, "region": "US"}, page(MOVIE_SUMMARY)),
    Check("Upcoming", "movie/upcoming", {**LANG, "region": "US"}, page(MOVIE_SUMMARY)),
    Check("TV on the air", "tv/on_the_air", LANG, page(TV_SUMMARY)),
    Check(
        "Search movies",
        "search/movie",
        {**LANG, "query": "Inception", "include_adult": "false"},
        page(MOVIE_SUMMARY),
    ),
    Check(
        "Search TV",
        "search/tv",
        {**LANG, "query": "Breaking Bad", "include_adult": "false"},
        page(TV_SUMMARY),
    ),
    Check(
        "Search people",
        "search/person",
        {**LANG, "query": "Meryl Streep", "include_adult": "false"},
        page(PERSON_SUMMARY),
    ),
]


@dataclass
class Result:
    check: Check
    status: Optional[int] = None
    errors: List[str] = field(default_factory=list)

    @property
    def ok(self):
        return not self.errors


def default_fetch(url, headers):
    """(status, raw bytes). Network failures become status None."""
    request = urllib.request.Request(url, headers=headers)
    try:
        with urllib.request.urlopen(request, timeout=30) as response:
            return response.status, response.read()
    except urllib.error.HTTPError as error:
        return error.code, error.read()
    except (urllib.error.URLError, TimeoutError) as error:
        return None, str(error).encode()


def run_check(check, token, fetch=default_fetch, sleep=time.sleep):
    url = f"{BASE_URL}/{check.path}?{urllib.parse.urlencode(check.query)}"
    headers = {"Authorization": f"Bearer {token}", "Accept": "application/json"}
    status, raw = fetch(url, headers)
    # One retry for rate limits and blips, so a single hiccup doesn't file an issue.
    if status is None or status == 429 or status >= 500:
        sleep(5)
        status, raw = fetch(url, headers)
    result = Result(check, status=status)
    if status != 200:
        detail = (raw or b"")[:200].decode(errors="replace")
        result.errors.append(f"HTTP {status if status is not None else 'error'}: {detail}")
        return result
    try:
        payload = json.loads(raw.decode())
    except (UnicodeDecodeError, json.JSONDecodeError):
        result.errors.append("response is not JSON")
        return result
    errors = validate(payload, check.schema)
    if len(errors) > MAX_ERRORS_PER_CHECK:
        extra = len(errors) - MAX_ERRORS_PER_CHECK
        errors = errors[:MAX_ERRORS_PER_CHECK] + [f"…and {extra} more"]
    result.errors = errors
    return result


def run_url():
    server = os.environ.get("GITHUB_SERVER_URL", "https://github.com")
    repo = os.environ.get("GITHUB_REPOSITORY")
    run_id = os.environ.get("GITHUB_RUN_ID")
    if repo and run_id:
        return f"{server}/{repo}/actions/runs/{run_id}"
    return None


def render_report(results, today, link=None):
    failed = [result for result in results if not result.ok]
    lines = []
    if failed:
        lines.append(f"**{len(failed)} of {len(results)} TMDB checks failed on {today}.**")
    else:
        lines.append(f"All {len(results)} TMDB checks passed on {today}.")
    lines.append("")
    lines.append("| Check | Endpoint | Result |")
    lines.append("| --- | --- | --- |")
    for result in results:
        mark = "✅" if result.ok else "❌"
        lines.append(f"| {result.check.name} | `{result.check.path}` | {mark} |")
    for result in failed:
        lines.append("")
        lines.append(f"### {result.check.name}")
        lines.append("")
        lines.extend(f"- `{error}`" for error in result.errors)
    if failed:
        lines.append("")
        lines.append(
            "Schemas live in `scripts/tmdb_health.py` and mirror the DTOs in "
            "`SilverScreen/Data/Networking`. A real API change means updating both."
        )
    if link:
        lines.append("")
        lines.append(f"Run: {link}")
    return "\n".join(lines) + "\n"


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument(
        "--file-issue",
        action="store_true",
        help=f"On failure, comment on the open '{ISSUE_LABEL}' issue or open one",
    )
    args = parser.parse_args(argv)

    token = os.environ.get("TMDB_ACCESS_TOKEN", "").strip()
    if not token:
        print("Set TMDB_ACCESS_TOKEN.", file=sys.stderr)
        return 2

    results = []
    for check in CHECKS:
        result = run_check(check, token)
        print(("ok    " if result.ok else "FAIL  ") + check.name)
        for error in result.errors:
            print("      " + error)
        results.append(result)

    today = dt.date.today().isoformat()
    report = render_report(results, today, run_url())
    summary_path = os.environ.get("GITHUB_STEP_SUMMARY")
    if summary_path:
        with open(summary_path, "a", encoding="utf-8") as handle:
            handle.write(report)

    if all(result.ok for result in results):
        return 0
    if args.file_issue:
        issues = github_issues.GitHubIssues.from_env()
        number, opened = issues.file_or_comment(
            ISSUE_LABEL, f"TMDB health check failing – {today}", report
        )
        print(("Opened" if opened else "Commented on") + f" issue #{number}")
    return 1


if __name__ == "__main__":
    sys.exit(main())
