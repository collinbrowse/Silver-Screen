#!/usr/bin/env python3
"""Tests for the Pro survey report and its weekly digest section."""

from __future__ import annotations

import datetime as dt
import unittest

import survey_report
import weekly_digest
from weekly_digest import Week

WEEK = Week(dt.date(2026, 11, 2), dt.date(2026, 11, 8))


def fake_query(rows_by_sql=None, fail=False):
    """Answers each SQL constant with canned rows and records the parameters."""
    calls = []
    rows_by_sql = rows_by_sql or {
        survey_report.COUNT_SQL: [{"responses": 4}],
        survey_report.FEATURES_SQL: [{"feature": "widgets", "picks": 3}, {"feature": "stats", "picks": 1}],
        survey_report.SOURCES_SQL: [{"source": "libraryCard", "responses": 3}, {"source": "settings", "responses": 1}],
        survey_report.OTHER_SQL: [{"updated_at": "2026-11-08T10:00:00Z", "other": "Watch parties"}],
    }

    def run(sql, params):
        if fail:
            raise survey_report.SurveySourceError("D1 query failed (403)")
        calls.append((sql, params))
        return rows_by_sql.get(sql, [])

    run.calls = calls
    return run


class SummaryTests(unittest.TestCase):
    def test_every_query_leaves_out_debug_builds(self):
        for sql in (survey_report.COUNT_SQL, survey_report.FEATURES_SQL, survey_report.SOURCES_SQL, survey_report.OTHER_SQL):
            self.assertIn("is_test = 0", sql)

    def test_summarize_passes_survey_id_and_since(self):
        query = fake_query()

        survey_report.summarize(query, since="2026-11-01")

        self.assertTrue(all(params == [survey_report.SURVEY_ID, "2026-11-01"] for _, params in query.calls))

    def test_render_lists_features_with_share_and_free_text(self):
        body = survey_report.render(survey_report.summarize(fake_query()))

        self.assertIn("4 responses", body)
        self.assertIn("- widgets: **3** (75% of respondents)", body)
        self.assertIn("Watch parties", body)

    def test_summarize_without_other_skips_free_text_query(self):
        query = fake_query()

        summary = survey_report.summarize(query, include_other=False)

        self.assertEqual(summary.other, [])
        self.assertNotIn(survey_report.OTHER_SQL, [sql for sql, _ in query.calls])


class DigestSectionTests(unittest.TestCase):
    def test_digest_shows_counts_and_change_but_never_free_text(self):
        body = weekly_digest.build_digest(WEEK, {"survey_responses": 1}, survey_query=fake_query())

        self.assertIn("**Pro survey**", body)
        self.assertIn("**4** responses in all", body)
        self.assertIn("- widgets: **3**", body)
        self.assertNotIn("Watch parties", body)
        self.assertIn('"survey_responses": 4', body)

    def test_digest_without_credentials_skips_with_note(self):
        body = weekly_digest.build_digest(WEEK, {})

        self.assertIn("Skipped: set CLOUDFLARE_API_TOKEN", body)

    def test_digest_when_d1_fails_still_posts(self):
        body = weekly_digest.build_digest(WEEK, {}, survey_query=fake_query(fail=True))

        self.assertIn("_Unavailable: D1 query failed (403)_", body)

    def test_digest_with_no_answers_says_so(self):
        query = fake_query({survey_report.COUNT_SQL: [{"responses": 0}]})

        body = weekly_digest.build_digest(WEEK, {}, survey_query=query)

        self.assertIn("_No answers yet._", body)


if __name__ == "__main__":
    unittest.main()
