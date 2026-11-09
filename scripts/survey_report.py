#!/usr/bin/env python3
"""Pro survey report: how many people answered and which features they picked.

Reads the Worker's D1 database (worker/README.md → Feature survey) through the
Cloudflare D1 HTTP API. Debug-build answers (is_test = 1) are always left out.

    python3 scripts/survey_report.py               # counts plus the free-text answers
    python3 scripts/survey_report.py --since 2026-11-01

The free-text answers are printed here only. The weekly digest posts to a public
issue, so it gets counts alone (`digest_section`).

Environment: CLOUDFLARE_API_TOKEN (Account → D1 → Read), CLOUDFLARE_ACCOUNT_ID,
SURVEY_D1_DATABASE_ID. No pip packages.
"""

from __future__ import annotations

import argparse
import json
import os
import sys
import urllib.error
import urllib.request
from dataclasses import dataclass, field
from typing import Callable, List, Optional, Tuple

SURVEY_ID = "pro-features-1"  # ProSurvey.id in the app

COUNT_SQL = """SELECT COUNT(*) AS responses FROM survey_response
WHERE survey_id = ?1 AND is_test = 0 AND submitted_at >= ?2"""

FEATURES_SQL = """SELECT feature.value AS feature, COUNT(*) AS picks
FROM survey_response, json_each(survey_response.features) AS feature
WHERE survey_id = ?1 AND is_test = 0 AND submitted_at >= ?2
GROUP BY feature.value ORDER BY picks DESC, feature.value"""

SOURCES_SQL = """SELECT source, COUNT(*) AS responses FROM survey_response
WHERE survey_id = ?1 AND is_test = 0 AND submitted_at >= ?2
GROUP BY source ORDER BY responses DESC"""

OTHER_SQL = """SELECT updated_at, other FROM survey_response
WHERE survey_id = ?1 AND is_test = 0 AND submitted_at >= ?2 AND other IS NOT NULL
ORDER BY updated_at DESC LIMIT 50"""


class SurveySourceError(Exception):
    """D1 could not be read."""


Query = Callable[[str, List[str]], List[dict]]


def d1_query(account_id: str, database_id: str, token: str) -> Query:
    """A function that runs one SQL statement against D1 and returns its rows."""
    url = f"https://api.cloudflare.com/client/v4/accounts/{account_id}/d1/database/{database_id}/query"

    def run(sql: str, params: List[str]) -> List[dict]:
        body = json.dumps({"sql": sql, "params": params}).encode()
        request = urllib.request.Request(
            url,
            data=body,
            method="POST",
            headers={"Authorization": f"Bearer {token}", "Content-Type": "application/json"},
        )
        try:
            with urllib.request.urlopen(request, timeout=60) as response:
                data = json.loads(response.read().decode())
        except urllib.error.HTTPError as error:
            raise SurveySourceError(f"D1 query failed ({error.code})") from error
        except (OSError, json.JSONDecodeError) as error:
            raise SurveySourceError(f"D1 query failed: {error}") from error
        if not data.get("success"):
            raise SurveySourceError(f"D1 query failed: {data.get('errors')}")
        result = data.get("result") or [{}]
        return result[0].get("results") or []

    return run


def query_from_env() -> Optional[Query]:
    token = os.environ.get("CLOUDFLARE_API_TOKEN", "").strip()
    account = os.environ.get("CLOUDFLARE_ACCOUNT_ID", "").strip()
    database = os.environ.get("SURVEY_D1_DATABASE_ID", "").strip()
    if not (token and account and database):
        return None
    return d1_query(account, database, token)


@dataclass
class SurveySummary:
    responses: int
    features: List[Tuple[str, int]] = field(default_factory=list)
    sources: List[Tuple[str, int]] = field(default_factory=list)
    other: List[Tuple[str, str]] = field(default_factory=list)


def summarize(query: Query, since: str = "", include_other: bool = True) -> SurveySummary:
    params = [SURVEY_ID, since]
    responses = int((query(COUNT_SQL, params) or [{"responses": 0}])[0].get("responses") or 0)
    features = [(row["feature"], int(row["picks"])) for row in query(FEATURES_SQL, params)]
    sources = [(row["source"], int(row["responses"])) for row in query(SOURCES_SQL, params)]
    other = [(row["updated_at"], row["other"]) for row in query(OTHER_SQL, params)] if include_other else []
    return SurveySummary(responses, features, sources, other)


def share(count: int, total: int) -> str:
    return f"{count / total:.0%}" if total else "–"


def feature_lines(summary: SurveySummary) -> List[str]:
    """One Markdown bullet per feature, most picked first, with the share of respondents."""
    return [
        f"- {feature}: **{picks:,}** ({share(picks, summary.responses)} of respondents)"
        for feature, picks in summary.features
    ]


def render(summary: SurveySummary) -> str:
    lines = [f"# Pro survey ({SURVEY_ID})", "", f"{summary.responses:,} responses (Debug builds left out)."]
    if summary.sources:
        lines.append("Opened from: " + ", ".join(f"{source} {count:,}" for source, count in summary.sources) + ".")
    lines += ["", "## Features", ""]
    lines += feature_lines(summary) or ["_No picks yet._"]
    lines += ["", "## Anything else? (latest 50)", ""]
    lines += [f"- {when[:10]}: {text}" for when, text in summary.other] or ["_None yet._"]
    return "\n".join(lines) + "\n"


def main(argv=None) -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--since", default="", help="Only answers first sent on or after YYYY-MM-DD")
    args = parser.parse_args(argv)
    query = query_from_env()
    if query is None:
        print("Set CLOUDFLARE_API_TOKEN, CLOUDFLARE_ACCOUNT_ID, and SURVEY_D1_DATABASE_ID.", file=sys.stderr)
        return 1
    try:
        print(render(summarize(query, since=args.since)), end="")
    except SurveySourceError as error:
        print(error, file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
