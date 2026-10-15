#!/usr/bin/env python3
"""Tests for the TMDB health check and the GitHub issue filing it shares with the digest."""

from __future__ import annotations

import json
import unittest

import github_issues
import tmdb_health
from tmdb_health import ListOf, MapOf, Opt


def movie_summary(**overrides):
    row = {"id": 1, "title": "Heat", "poster_path": None, "release_date": "1995-12-15",
           "vote_average": 7.9, "genre_ids": [80], "popularity": 30.5}
    row.update(overrides)
    return row


class ValidateTests(unittest.TestCase):
    def test_scalars_follow_swift_decoding(self) -> None:
        self.assertEqual(tmdb_health.validate(5, "int"), [])
        self.assertEqual(tmdb_health.validate(5.0, "int"), [])
        self.assertTrue(tmdb_health.validate(5.5, "int"))
        self.assertEqual(tmdb_health.validate(5, "num"), [])
        self.assertTrue(tmdb_health.validate(True, "num"))
        self.assertTrue(tmdb_health.validate("7.9", "num"))

    def test_required_field_missing_names_the_path(self) -> None:
        errors = tmdb_health.validate({"id": 1}, {"id": "int", "title": "str"})
        self.assertEqual(errors, ["$.title: missing or null"])

    def test_optional_field_may_be_null_but_not_the_wrong_type(self) -> None:
        spec = {"poster_path": Opt("str")}
        self.assertEqual(tmdb_health.validate({"poster_path": None}, spec), [])
        self.assertEqual(tmdb_health.validate({}, spec), [])
        self.assertEqual(
            tmdb_health.validate({"poster_path": 3}, spec),
            ["$.poster_path: expected str, got number"],
        )

    def test_lossy_list_tolerates_a_minority_of_bad_rows(self) -> None:
        spec = ListOf(tmdb_health.MOVIE_SUMMARY, lossy=True, min_items=1)
        rows = [movie_summary(id=1), movie_summary(id=2), {"id": 3}]
        self.assertEqual(tmdb_health.validate(rows, spec), [])

    def test_lossy_list_fails_when_most_rows_are_bad(self) -> None:
        spec = ListOf(tmdb_health.MOVIE_SUMMARY, lossy=True, min_items=1)
        rows = [movie_summary(), movie_summary(vote_average="high"), movie_summary(title=None)]
        errors = tmdb_health.validate(rows, spec)
        self.assertEqual(errors[0], "$: 2 of 3 rows fail to decode")
        self.assertIn("$[1].vote_average: expected num, got string", errors)

    def test_strict_list_fails_on_one_bad_row(self) -> None:
        errors = tmdb_health.validate([{"id": 1, "name": "Drama"}, {"id": "x", "name": "War"}],
                                      ListOf(tmdb_health.GENRE))
        self.assertEqual(errors, ["$[1].id: expected int, got string"])

    def test_min_items(self) -> None:
        self.assertEqual(
            tmdb_health.validate([], ListOf("int", min_items=1)),
            ["$: expected at least 1 item(s), got 0"],
        )

    def test_map_checks_every_region(self) -> None:
        provider = {"provider_id": 8, "provider_name": "Netflix", "logo_path": "/n.png"}
        payload = {"results": {"US": {"flatrate": [provider]}, "GB": {"flatrate": [{"provider_id": 8}]}}}
        errors = tmdb_health.validate(payload, tmdb_health.WATCH_PROVIDERS)
        self.assertEqual(errors, ["$.results.GB.flatrate[0].provider_name: missing or null"])
        self.assertTrue(tmdb_health.validate({"results": []}, {"results": MapOf("int")}))


class RunCheckTests(unittest.TestCase):
    PAGE_CHECK = tmdb_health.Check("Now playing", "movie/now_playing", {"region": "US"},
                                   tmdb_health.page(tmdb_health.MOVIE_SUMMARY))

    def page_payload(self, rows):
        return json.dumps({"page": 1, "results": rows, "total_pages": 1, "total_results": len(rows)}).encode()

    def test_sends_the_bearer_token_in_the_header(self) -> None:
        seen = []

        def fetch(url, headers):
            seen.append((url, headers))
            return 200, self.page_payload([movie_summary()])

        result = tmdb_health.run_check(self.PAGE_CHECK, "secret", fetch=fetch, sleep=lambda _: None)
        self.assertTrue(result.ok)
        url, headers = seen[0]
        self.assertEqual(headers["Authorization"], "Bearer secret")
        self.assertNotIn("secret", url)
        self.assertIn("/3/movie/now_playing?region=US", url)

    def test_retries_once_on_server_error(self) -> None:
        responses = [(503, b"down"), (200, self.page_payload([movie_summary()]))]
        sleeps = []
        result = tmdb_health.run_check(
            self.PAGE_CHECK, "t", fetch=lambda url, headers: responses.pop(0), sleep=sleeps.append
        )
        self.assertTrue(result.ok)
        self.assertEqual(sleeps, [5])

    def test_http_failure_is_reported(self) -> None:
        result = tmdb_health.run_check(
            self.PAGE_CHECK, "t", fetch=lambda url, headers: (401, b'{"status_code":7}'), sleep=lambda _: None
        )
        self.assertFalse(result.ok)
        self.assertTrue(result.errors[0].startswith("HTTP 401"))

    def test_non_json_is_reported(self) -> None:
        result = tmdb_health.run_check(
            self.PAGE_CHECK, "t", fetch=lambda url, headers: (200, b"<html>"), sleep=lambda _: None
        )
        self.assertEqual(result.errors, ["response is not JSON"])

    def test_empty_page_fails(self) -> None:
        result = tmdb_health.run_check(
            self.PAGE_CHECK, "t", fetch=lambda url, headers: (200, self.page_payload([])), sleep=lambda _: None
        )
        self.assertIn("$.results: expected at least 1 item(s), got 0", result.errors)

    def test_every_check_has_a_schema_the_validator_understands(self) -> None:
        # An empty object exercises every branch of each schema without raising.
        for check in tmdb_health.CHECKS:
            self.assertTrue(tmdb_health.validate({}, check.schema), check.name)

    def test_report_lists_failures(self) -> None:
        good = tmdb_health.Result(self.PAGE_CHECK, status=200)
        bad = tmdb_health.Result(tmdb_health.CHECKS[0], status=200, errors=["$.title: missing or null"])
        report = tmdb_health.render_report([good, bad], "2026-10-15", "https://example.test/run")
        self.assertIn("**1 of 2 TMDB checks failed on 2026-10-15.**", report)
        self.assertIn("### Movie detail", report)
        self.assertIn("- `$.title: missing or null`", report)
        self.assertIn("Run: https://example.test/run", report)


class FakeGitHub:
    def __init__(self, open_issues=(), label_exists=True):
        self.calls = []
        self.open_issues = list(open_issues)
        self.label_exists = label_exists

    def __call__(self, method, url, headers, body):
        self.calls.append((method, url, json.loads(body) if body else None))
        if method == "GET" and "/labels/" in url:
            return (200, {"name": "x"}) if self.label_exists else (404, {"message": "Not Found"})
        if method == "GET" and "/issues?" in url:
            return 200, self.open_issues
        if method == "POST" and url.endswith("/issues"):
            return 201, {"number": 42}
        if method == "POST":
            return 201, {"id": 1}
        raise AssertionError(f"unexpected {method} {url}")


class GitHubIssuesTests(unittest.TestCase):
    def test_comments_on_the_open_issue_instead_of_opening_another(self) -> None:
        http = FakeGitHub(open_issues=[{"number": 7}, {"number": 9, "pull_request": {}}])
        client = github_issues.GitHubIssues("tok", "owner/repo", http=http)
        number, opened = client.file_or_comment("tmdb-health", "Title", "Body")
        self.assertEqual((number, opened), (7, False))
        method, url, payload = http.calls[-1]
        self.assertEqual(method, "POST")
        self.assertTrue(url.endswith("/repos/owner/repo/issues/7/comments"))
        self.assertEqual(payload, {"body": "Body"})

    def test_opens_a_labelled_issue_and_creates_the_label(self) -> None:
        http = FakeGitHub(label_exists=False)
        client = github_issues.GitHubIssues("tok", "owner/repo", http=http)
        number, opened = client.file_or_comment("tmdb-health", "Title", "Body")
        self.assertEqual((number, opened), (42, True))
        posts = [(url, payload) for method, url, payload in http.calls if method == "POST"]
        self.assertTrue(posts[0][0].endswith("/labels"))
        self.assertEqual(posts[1][1], {"title": "Title", "body": "Body", "labels": ["tmdb-health"]})

    def test_issue_listing_filters_by_label_and_state(self) -> None:
        http = FakeGitHub()
        client = github_issues.GitHubIssues("tok", "owner/repo", http=http)
        client.issues("weekly-digest", state="all", limit=1)
        url = http.calls[0][1]
        self.assertIn("labels=weekly-digest", url)
        self.assertIn("state=all", url)


if __name__ == "__main__":
    unittest.main()
