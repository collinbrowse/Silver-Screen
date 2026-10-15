#!/usr/bin/env python3
"""Tests for the weekly digest's sections, skipping, and week-over-week change."""

from __future__ import annotations

import datetime as dt
import json
import unittest
import urllib.parse

import asc_api
import weekly_digest
from weekly_digest import Week

WEEK = Week(dt.date(2026, 10, 12), dt.date(2026, 10, 18))

REPORT = (
    "Product Type Identifier\tUnits\tApple Identifier\n"
    "1\t30\tapp-1\n"
    "7\t5\tapp-1\n"
)


class FakeASC:
    def __init__(self, report=REPORT, reviews=(), fail_sales=False):
        self.report = report
        self.reviews = list(reviews)
        self.fail_sales = fail_sales
        self.report_dates = []

    def app_id(self):
        return "app-1"

    def sales_report(self, vendor_number, report_date):
        self.report_dates.append(report_date)
        if self.fail_sales:
            raise asc_api.ASCError("ASC sales report failed (403)")
        return self.report

    def customer_reviews(self, app_id):
        return self.reviews


class FakeSentry:
    def __init__(self, release="ss@1.0+3", crash=None, issues=None, feedback=0):
        self.release = release
        self.crash = crash or {"sessions": 1200, "crash_free_sessions": 0.995, "crash_free_users": 0.998}
        self.top = issues or []
        self.feedback = feedback

    def latest_release(self):
        return self.release

    def crash_free(self, release, week):
        return self.crash

    def issues(self, query, week, limit):
        if "feedback" in query and "!" not in query:
            return [{}] * self.feedback
        return self.top


def metrics_from(body):
    match = weekly_digest.METRICS_PATTERN.search(body)
    return json.loads(match.group(1))


class WeekTests(unittest.TestCase):
    def test_monday_covers_the_previous_monday_to_sunday(self) -> None:
        self.assertEqual(Week.before(dt.date(2026, 10, 19)), WEEK)

    def test_sunday_covers_the_week_before_not_the_one_in_progress(self) -> None:
        self.assertEqual(Week.before(dt.date(2026, 10, 18)), Week(dt.date(2026, 10, 5), dt.date(2026, 10, 11)))

    def test_sentry_window_is_end_exclusive(self) -> None:
        self.assertEqual(WEEK.start_iso(), "2026-10-12T00:00:00Z")
        self.assertEqual(WEEK.end_iso(), "2026-10-19T00:00:00Z")


class FormatTests(unittest.TestCase):
    def test_deltas(self) -> None:
        self.assertEqual(weekly_digest.fmt_delta(30, 20), " (+10, +50%)")
        self.assertEqual(weekly_digest.fmt_delta(3, 0), " (+3)")
        self.assertEqual(weekly_digest.fmt_delta(0.995, 0.990, "rate"), " (+0.5 pt)")
        self.assertEqual(weekly_digest.fmt_delta(4.5, 4.6, "rating"), " (-0.10)")
        self.assertEqual(weekly_digest.fmt_delta(3, None), "")

    def test_previous_metrics_skips_a_rerun_of_the_same_week(self) -> None:
        issues = [
            {"body": '<!-- digest-metrics {"week_end": "2026-10-18", "downloads": 99} -->'},
            {"body": "no marker"},
            {"body": 'text\n<!-- digest-metrics {"week_end": "2026-10-11", "downloads": 20} -->'},
        ]
        self.assertEqual(weekly_digest.previous_metrics(issues, WEEK)["downloads"], 20)
        self.assertEqual(weekly_digest.previous_metrics([], WEEK), {})


class DigestTests(unittest.TestCase):
    def build(self, previous=None, **kwargs):
        kwargs.setdefault("rating_lookup", lambda: None)
        return weekly_digest.build_digest(WEEK, previous or {}, **kwargs)

    def test_nothing_configured_skips_every_section(self) -> None:
        body = self.build()
        self.assertIn("_Skipped: App Store Connect API key not configured._", body)
        self.assertIn("_Skipped: set SENTRY_AUTH_TOKEN, SENTRY_ORG, and SENTRY_PROJECT._", body)
        self.assertEqual(metrics_from(body), {"week_end": "2026-10-18"})

    def test_pre_launch_app_store_says_there_is_no_data(self) -> None:
        asc = FakeASC(report=None)
        body = self.build(asc_client=asc, vendor_number="881")
        self.assertIn("_No sales report for this week", body)
        self.assertIn("_No ratings yet._", body)
        self.assertIn("_No new reviews._", body)
        self.assertEqual(asc.report_dates, ["2026-10-18"])

    def test_missing_vendor_number_skips_downloads_only(self) -> None:
        body = self.build(asc_client=FakeASC(), rating_lookup=lambda: (4.6, 12))
        self.assertIn("_Skipped: set ASC_VENDOR_NUMBER", body)
        self.assertIn("**4.60★** from 12 ratings (US)", body)

    def test_downloads_rating_and_reviews_with_week_over_week_change(self) -> None:
        reviews = [
            {"rating": 5, "title": "Lovely", "body": "Great  app\nfor films", "territory": "USA",
             "createdDate": "2026-10-17T21:00:00-07:00"},
            {"rating": 3, "title": "", "body": "ok", "territory": "GBR", "createdDate": "2026-10-12T00:00:00Z"},
            {"rating": 1, "title": "Old", "body": "too early", "createdDate": "2026-10-11T23:59:59Z"},
            {"rating": 1, "title": "Late", "body": "this week", "createdDate": "2026-10-19T00:00:00Z"},
        ]
        previous = {"week_end": "2026-10-11", "downloads": 20, "rating_average": 4.5, "rating_count": 10}
        body = self.build(
            previous,
            asc_client=FakeASC(reviews=reviews),
            vendor_number="881",
            rating_lookup=lambda: (4.6, 12),
        )
        self.assertIn("**30** first-time downloads (+10, +50%)", body)
        self.assertIn("(US) (+0.10), +2 ratings this week", body)
        self.assertIn("2 new, averaging 4.0★.", body)
        self.assertIn("- ★★★★★ **Lovely** (USA): Great app for films", body)
        self.assertIn("- ★★★ **(no title)** (GBR): ok", body)
        self.assertNotIn("too early", body)
        self.assertNotIn("**Late**", body)
        self.assertIn("Changes compare with the week ending 2026-10-11.", body)
        metrics = metrics_from(body)
        self.assertEqual(metrics["downloads"], 30)
        self.assertEqual(metrics["new_reviews"], 2)

    def test_one_failing_section_does_not_sink_the_others(self) -> None:
        body = self.build(asc_client=FakeASC(fail_sales=True), vendor_number="881", rating_lookup=lambda: (4.0, 3))
        self.assertIn("_Unavailable: ASC sales report failed (403)_", body)
        self.assertIn("**4.00★** from 3 ratings", body)

    def test_sentry_sections(self) -> None:
        issues = [
            {"shortId": "SILVER-1A", "permalink": "https://sentry.io/i/1", "title": "Crash in [Detail]",
             "count": "1520", "userCount": 31},
        ]
        previous = {"week_end": "2026-10-11", "release": "ss@1.0+3", "crash_free_sessions": 0.99, "feedback": 4}
        body = self.build(previous, sentry=FakeSentry(issues=issues, feedback=6))
        self.assertIn("Latest release `ss@1.0+3`, 1,200 sessions this week.", body)
        self.assertIn("- Crash-free sessions: **99.50%** (+0.5 pt)", body)
        self.assertIn("- Crash-free users: **99.80%**", body)
        self.assertIn("- [SILVER-1A](https://sentry.io/i/1) Crash in \\[Detail\\]: 1,520 events, 31 users", body)
        self.assertIn("- **6** feedback reports (+2, +50%)", body)

    def test_new_release_hides_crash_free_change(self) -> None:
        previous = {"week_end": "2026-10-11", "release": "ss@1.0+2", "crash_free_sessions": 0.90}
        body = self.build(previous, sentry=FakeSentry())
        self.assertIn("- Crash-free sessions: **99.50%**\n", body)
        self.assertIn("Last week covered `ss@1.0+2`, so no change is shown.", body)

    def test_no_sessions_and_no_release(self) -> None:
        body = self.build(sentry=FakeSentry(crash={"sessions": 0, "crash_free_sessions": None, "crash_free_users": None}))
        self.assertIn("**no sessions**", body)
        self.assertIn("_No unresolved issues had events this week._", body)
        body = self.build(sentry=FakeSentry(release=None))
        self.assertIn("_No releases in Sentry yet._", body)


class SentryClientTests(unittest.TestCase):
    def test_requests_use_the_project_id_window_and_release(self) -> None:
        urls = []

        def http(method, url, headers, body=None):
            urls.append(url)
            self.assertEqual(headers["Authorization"], "Bearer tok")
            path = urllib.parse.urlparse(url).path
            if path == "/api/0/projects/org/ios/":
                return 200, {"id": "4507"}
            if path.endswith("/releases/"):
                return 200, [{"version": "ss@1.0+3"}, {"version": "ss@1.0+2"}]
            if path.endswith("/sessions/"):
                return 200, {"groups": [{"by": {}, "totals": {
                    "sum(session)": 50, "crash_free_rate(session)": 1.0, "crash_free_rate(user)": 1.0}}]}
            return 200, []

        sentry = weekly_digest.SentryClient("tok", "org", "ios", http=http)
        self.assertEqual(sentry.latest_release(), "ss@1.0+3")
        self.assertEqual(sentry.crash_free("ss@1.0+3", WEEK)["sessions"], 50)
        sessions = urllib.parse.parse_qs(urllib.parse.urlparse(urls[2]).query)
        self.assertEqual(sessions["project"], ["4507"])
        self.assertEqual(sessions["query"], ['release:"ss@1.0+3"'])
        self.assertEqual(sessions["start"], ["2026-10-12T00:00:00Z"])
        self.assertIn("crash_free_rate(user)", sessions["field"])
        self.assertEqual(len([url for url in urls if "/projects/org/ios/" in url]), 1)

    def test_http_error_becomes_a_source_error(self) -> None:
        sentry = weekly_digest.SentryClient("tok", "org", "ios", http=lambda *args, **kwargs: (401, {"detail": "bad"}))
        with self.assertRaises(weekly_digest.SourceError):
            sentry.project_id()

    def test_itunes_rating_is_none_before_launch(self) -> None:
        self.assertIsNone(weekly_digest.itunes_rating("b", http=lambda *args: (200, {"resultCount": 0, "results": []})))
        found = weekly_digest.itunes_rating(
            "b", http=lambda *args: (200, {"results": [{"averageUserRating": 4.5, "userRatingCount": 8}]})
        )
        self.assertEqual(found, (4.5, 8))


if __name__ == "__main__":
    unittest.main()
