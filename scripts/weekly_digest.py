#!/usr/bin/env python3
"""Weekly digest: App Store and Sentry numbers for last week, posted as a GitHub issue.

The week is the last full Monday–Sunday before today. Each source is optional:
a section whose credentials are missing, or that has no data yet (every App
Store section before launch), says so in one line instead of failing the run.

Week-over-week change compares against the metrics block hidden in the last
digest issue, so no state lives in the repo.

    python3 scripts/weekly_digest.py --dry-run   # print the issue body
    python3 scripts/weekly_digest.py             # post it (CI)

Environment: ASC_KEY_ID, ASC_ISSUER_ID, ASC_KEY_PATH, ASC_VENDOR_NUMBER,
SENTRY_AUTH_TOKEN, SENTRY_ORG, SENTRY_PROJECT, GITHUB_TOKEN, GITHUB_REPOSITORY.
No pip packages.
"""

from __future__ import annotations

import argparse
import datetime as dt
import json
import os
import re
import sys
import urllib.error
import urllib.parse
import urllib.request
from dataclasses import dataclass, field
from typing import Any, Dict, List, Optional

import asc_api
import github_issues

ISSUE_LABEL = "weekly-digest"
BUNDLE_ID = "com.collinbrowse.thesilverscreen"
METRICS_MARKER = "digest-metrics"
METRICS_PATTERN = re.compile(r"<!--\s*" + METRICS_MARKER + r"\s+(\{.*?\})\s*-->", re.S)


class SourceError(Exception):
    """A source could not be read. The section reports it and the digest still posts."""


@dataclass(frozen=True)
class Week:
    start: dt.date
    end: dt.date

    @classmethod
    def before(cls, today):
        """The last full Monday–Sunday week before `today`."""
        end = today - dt.timedelta(days=today.weekday() + 1)
        return cls(end - dt.timedelta(days=6), end)

    @property
    def label(self):
        return f"{self.start:%b %-d} – {self.end:%b %-d, %Y}"

    def start_iso(self):
        return f"{self.start.isoformat()}T00:00:00Z"

    def end_iso(self):
        return f"{(self.end + dt.timedelta(days=1)).isoformat()}T00:00:00Z"


@dataclass
class Section:
    title: str
    lines: List[str] = field(default_factory=list)
    note: Optional[str] = None


# Sources -------------------------------------------------------------------


def http_json(method, url, headers, body=None):
    request = urllib.request.Request(url, data=body, headers=headers, method=method)
    try:
        with urllib.request.urlopen(request, timeout=60) as response:
            raw = response.read()
            status = response.status
    except urllib.error.HTTPError as error:
        raw = error.read()
        status = error.code
    except urllib.error.URLError as error:
        raise SourceError(f"{url.split('?')[0]}: {error}") from error
    try:
        return status, json.loads(raw.decode()) if raw else {}
    except json.JSONDecodeError as error:
        raise SourceError(f"non-JSON response ({status}) from {url.split('?')[0]}") from error


class SentryClient:
    def __init__(self, token, org, project, base_url="https://sentry.io", http=http_json):
        self.token = token
        self.org = org
        self.project = project
        self.base_url = base_url.rstrip("/")
        self.http = http
        self._project_id = None

    @classmethod
    def from_env(cls, http=http_json):
        token = os.environ.get("SENTRY_AUTH_TOKEN", "").strip()
        org = os.environ.get("SENTRY_ORG", "").strip()
        project = os.environ.get("SENTRY_PROJECT", "").strip()
        if not (token and org and project):
            return None
        base_url = os.environ.get("SENTRY_URL", "").strip() or "https://sentry.io"
        return cls(token, org, project, base_url=base_url, http=http)

    def get(self, path, query=None):
        url = f"{self.base_url}/api/0{path}"
        if query:
            url += "?" + urllib.parse.urlencode(query, doseq=True)
        status, data = self.http("GET", url, {"Authorization": f"Bearer {self.token}"})
        if status >= 400:
            raise SourceError(f"Sentry {path} failed ({status}): {str(data)[:200]}")
        return data

    def project_id(self):
        if self._project_id is None:
            data = self.get(f"/projects/{self.org}/{self.project}/")
            self._project_id = str(data["id"])
        return self._project_id

    def latest_release(self):
        rows = self.get(
            f"/organizations/{self.org}/releases/",
            {"project": self.project_id(), "per_page": "1"},
        )
        return rows[0]["version"] if rows else None

    def crash_free(self, release, week):
        data = self.get(
            f"/organizations/{self.org}/sessions/",
            {
                "project": self.project_id(),
                "field": ["crash_free_rate(session)", "crash_free_rate(user)", "sum(session)"],
                "query": f'release:"{release}"',
                "start": week.start_iso(),
                "end": week.end_iso(),
                "interval": "1d",
            },
        )
        groups = data.get("groups") or []
        totals = (groups[0].get("totals") if groups else None) or {}
        return {
            "sessions": totals.get("sum(session)") or 0,
            "crash_free_sessions": totals.get("crash_free_rate(session)"),
            "crash_free_users": totals.get("crash_free_rate(user)"),
        }

    def issues(self, query, week, limit):
        return self.get(
            f"/organizations/{self.org}/issues/",
            {
                "project": self.project_id(),
                "query": query,
                "sort": "freq",
                "limit": str(limit),
                "start": week.start_iso(),
                "end": week.end_iso(),
            },
        ) or []


def itunes_rating(bundle_id, country="us", http=http_json):
    """(average, count) from the public lookup API, or None before the app is live.

    App Store Connect's API has reviews but no aggregate rating, so the store
    listing's own number comes from here.
    """
    query = urllib.parse.urlencode({"bundleId": bundle_id, "country": country})
    status, data = http("GET", f"https://itunes.apple.com/lookup?{query}", {})
    if status >= 400:
        raise SourceError(f"iTunes lookup failed ({status})")
    results = data.get("results") or []
    if not results or not results[0].get("userRatingCount"):
        return None
    app = results[0]
    return float(app.get("averageUserRating") or 0), int(app["userRatingCount"])


# Sections ------------------------------------------------------------------


def fmt_delta(current, previous, kind="count"):
    """' (+3, +12%)' style change against last week, or '' when there is no baseline."""
    if previous is None or current is None:
        return ""
    diff = current - previous
    if kind == "rate":
        return f" ({diff * 100:+.1f} pt)"
    if kind == "rating":
        return f" ({diff:+.2f})"
    if previous:
        return f" ({diff:+d}, {diff / previous:+.0%})"
    return f" ({diff:+d})"


def fmt_rate(rate):
    return "no sessions" if rate is None else f"{rate:.2%}"


def parse_timestamp(value):
    """ASC dates look like 2026-10-12T10:00:00-07:00. None when unreadable."""
    try:
        parsed = dt.datetime.fromisoformat((value or "").replace("Z", "+00:00"))
    except ValueError:
        return None
    return parsed if parsed.tzinfo else parsed.replace(tzinfo=dt.timezone.utc)


def downloads_section(client, app_id, vendor_number, week, metrics, previous):
    section = Section("Downloads")
    if not vendor_number:
        section.note = "Skipped: set ASC_VENDOR_NUMBER to read Sales and Trends reports."
        return section
    report = client.sales_report(vendor_number, week.end.isoformat())
    if report is None:
        section.note = "No sales report for this week (none before launch, or Apple has not published it yet)."
        return section
    units = asc_api.sum_units(report, apple_id=app_id)
    metrics["downloads"] = units
    section.lines.append(f"- **{units:,}** first-time downloads{fmt_delta(units, previous.get('downloads'))}")
    return section


def rating_section(rating_lookup, metrics, previous):
    section = Section("Rating")
    found = rating_lookup()
    if found is None:
        section.note = "No ratings yet."
        return section
    average, count = found
    metrics["rating_average"] = average
    metrics["rating_count"] = count
    line = f"- **{average:.2f}★** from {count:,} ratings (US){fmt_delta(average, previous.get('rating_average'), 'rating')}"
    if previous.get("rating_count") is not None:
        line += f", {count - previous['rating_count']:+,} ratings this week"
    section.lines.append(line)
    return section


def reviews_section(client, app_id, week, metrics):
    section = Section("New reviews")
    start = dt.datetime.combine(week.start, dt.time(), dt.timezone.utc)
    end = start + dt.timedelta(days=7)
    fresh = []
    for review in client.customer_reviews(app_id):
        created = parse_timestamp(review.get("createdDate"))
        if created is not None and start <= created < end:
            fresh.append(review)
    metrics["new_reviews"] = len(fresh)
    if not fresh:
        section.note = "No new reviews."
        return section
    average = sum(int(review.get("rating") or 0) for review in fresh) / len(fresh)
    section.lines.append(f"{len(fresh)} new, averaging {average:.1f}★.")
    section.lines.append("")
    for review in fresh[:10]:
        stars = "★" * int(review.get("rating") or 0)
        title = (review.get("title") or "").strip() or "(no title)"
        body = " ".join((review.get("body") or "").split())
        if len(body) > 200:
            body = body[:199] + "…"
        territory = review.get("territory") or "?"
        section.lines.append(f"- {stars} **{title}** ({territory}): {body}")
    if len(fresh) > 10:
        section.lines.append(f"- …and {len(fresh) - 10} more in App Store Connect.")
    return section


def guarded(title, build):
    """Run one section; an API failure becomes a one-line note so the rest still posts."""
    try:
        return build()
    except (asc_api.ASCError, SourceError, KeyError, ValueError, TypeError, IndexError) as error:
        print(f"{title} unavailable: {error}", file=sys.stderr)
        return Section(title, note=f"Unavailable: {error}")


def asc_sections(client, vendor_number, week, metrics, previous, rating_lookup):
    app_id = client.app_id()
    return [
        guarded("Downloads", lambda: downloads_section(client, app_id, vendor_number, week, metrics, previous)),
        guarded("Rating", lambda: rating_section(rating_lookup, metrics, previous)),
        guarded("New reviews", lambda: reviews_section(client, app_id, week, metrics)),
    ]


def sentry_sections(sentry, week, metrics, previous):
    return [
        guarded("Release health", lambda: release_health_section(sentry, week, metrics, previous)),
        guarded("Top unresolved issues", lambda: top_issues_section(sentry, week)),
        guarded("User feedback", lambda: feedback_section(sentry, week, metrics, previous)),
    ]


def release_health_section(sentry, week, metrics, previous):
    section = Section("Release health")
    release = sentry.latest_release()
    if release is None:
        section.note = "No releases in Sentry yet."
        return section
    crash = sentry.crash_free(release, week)
    same_release = previous.get("release") == release
    metrics["release"] = release
    metrics["crash_free_sessions"] = crash["crash_free_sessions"]
    metrics["crash_free_users"] = crash["crash_free_users"]
    section.lines.append(f"Latest release `{release}`, {int(crash['sessions']):,} sessions this week.")
    section.lines.append("")
    for key, label in (("crash_free_sessions", "Crash-free sessions"), ("crash_free_users", "Crash-free users")):
        delta = fmt_delta(crash[key], previous.get(key), "rate") if same_release else ""
        section.lines.append(f"- {label}: **{fmt_rate(crash[key])}**{delta}")
    if previous.get("release") and not same_release:
        section.lines.append(f"- Last week covered `{previous['release']}`, so no change is shown.")
    return section


def top_issues_section(sentry, week):
    section = Section("Top unresolved issues")
    rows = sentry.issues("is:unresolved !issue.category:feedback", week, limit=5)
    if not rows:
        section.note = "No unresolved issues had events this week."
    for row in rows[:5]:
        title = (row.get("title") or "").replace("[", "\\[").replace("]", "\\]")
        section.lines.append(
            f"- [{row.get('shortId', '?')}]({row.get('permalink', '')}) {title}: "
            f"{int(row.get('count') or 0):,} events, {int(row.get('userCount') or 0):,} users"
        )
    return section


def feedback_section(sentry, week, metrics, previous):
    section = Section("User feedback")
    count = len(sentry.issues("issue.category:feedback", week, limit=100))
    metrics["feedback"] = count
    shown = "100+" if count >= 100 else f"{count:,}"
    section.lines.append(f"- **{shown}** feedback reports{fmt_delta(count, previous.get('feedback'))}")
    return section


# Rendering -----------------------------------------------------------------


def previous_metrics(issues, week):
    """Metrics from the newest earlier digest, ignoring a rerun for this same week."""
    for issue in issues:
        match = METRICS_PATTERN.search(issue.get("body") or "")
        if not match:
            continue
        try:
            data = json.loads(match.group(1))
        except json.JSONDecodeError:
            continue
        if data.get("week_end") != week.end.isoformat():
            return data
    return {}


def render(week, groups, metrics, previous, link=None):
    lines = [f"Week of {week.label}."]
    if previous.get("week_end"):
        lines.append(f"Changes compare with the week ending {previous['week_end']}.")
    for heading, sections in groups:
        lines += ["", f"## {heading}"]
        for section in sections:
            lines += ["", f"**{section.title}**", ""]
            if section.note:
                lines.append(f"_{section.note}_")
            lines += section.lines
    if link:
        lines += ["", f"Run: {link}"]
    lines += ["", f"<!-- {METRICS_MARKER} {json.dumps(metrics, sort_keys=True)} -->"]
    return "\n".join(lines) + "\n"


def run_url():
    server = os.environ.get("GITHUB_SERVER_URL", "https://github.com")
    repo = os.environ.get("GITHUB_REPOSITORY")
    run_id = os.environ.get("GITHUB_RUN_ID")
    return f"{server}/{repo}/actions/runs/{run_id}" if repo and run_id else None


def build_digest(week, previous, asc_client=None, vendor_number="", sentry=None, rating_lookup=None):
    metrics: Dict[str, Any] = {"week_end": week.end.isoformat()}
    groups = []

    if asc_client is None:
        app_store = [Section("App Store", note="Skipped: App Store Connect API key not configured.")]
    else:
        app_store = guarded(
            "App Store",
            lambda: asc_sections(asc_client, vendor_number, week, metrics, previous, rating_lookup),
        )
        if isinstance(app_store, Section):
            app_store = [app_store]
    groups.append(("App Store", app_store))

    if sentry is None:
        crash = [Section("Sentry", note="Skipped: set SENTRY_AUTH_TOKEN, SENTRY_ORG, and SENTRY_PROJECT.")]
    else:
        crash = sentry_sections(sentry, week, metrics, previous)
    groups.append(("Stability and feedback", crash))

    return render(week, groups, metrics, previous, run_url())


def load_asc_client():
    if not (os.environ.get("ASC_KEY_ID") and os.environ.get("ASC_ISSUER_ID")):
        return None
    try:
        credentials = asc_api.load_credentials()
    except asc_api.ASCError as error:
        print(f"App Store Connect skipped: {error}", file=sys.stderr)
        return None
    return asc_api.ASCClient(credentials, bundle_id=BUNDLE_ID)


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--dry-run", action="store_true", help="Print the issue body instead of posting it")
    parser.add_argument("--date", help="Pretend today is YYYY-MM-DD (the digest covers the week before it)")
    args = parser.parse_args(argv)

    today = dt.date.fromisoformat(args.date) if args.date else dt.date.today()
    week = Week.before(today)
    title = f"Weekly digest – {today.isoformat()}"

    issues = None
    previous: Dict[str, Any] = {}
    if os.environ.get("GITHUB_TOKEN") and os.environ.get("GITHUB_REPOSITORY"):
        issues = github_issues.GitHubIssues.from_env()
        previous = previous_metrics(issues.issues(ISSUE_LABEL, state="all", limit=5), week)

    body = build_digest(
        week,
        previous,
        asc_client=load_asc_client(),
        vendor_number=os.environ.get("ASC_VENDOR_NUMBER", "").strip(),
        sentry=SentryClient.from_env(),
        rating_lookup=lambda: itunes_rating(BUNDLE_ID),
    )

    summary_path = os.environ.get("GITHUB_STEP_SUMMARY")
    if summary_path:
        with open(summary_path, "a", encoding="utf-8") as handle:
            handle.write(f"# {title}\n\n{body}")

    if args.dry_run or issues is None:
        print(f"# {title}\n\n{body}")
        if not args.dry_run:
            print("GITHUB_TOKEN or GITHUB_REPOSITORY missing; not posting.", file=sys.stderr)
            return 1
        return 0

    issues.ensure_label(ISSUE_LABEL, color="0e8a16", description="Monday app digest")
    same_title = [issue for issue in issues.issues(ISSUE_LABEL, state="all", limit=5) if issue.get("title") == title]
    if same_title:
        number = same_title[0]["number"]
        issues.update_issue(number, body=body)
        print(f"Updated issue #{number}")
    else:
        created = issues.create_issue(title, body, [ISSUE_LABEL])
        print(f"Opened issue #{created['number']}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
