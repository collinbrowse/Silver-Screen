#!/usr/bin/env python3
"""Tests for the App Store Connect helper used by release.py."""

from __future__ import annotations

import gzip
import unittest
import urllib.error
from pathlib import Path
from unittest import mock

import asc_api


class ASCClientTests(unittest.TestCase):
    def test_set_testflight_notes_patches_existing_localization(self) -> None:
        calls: list[tuple[str, str]] = []

        def http(method: str, url: str, headers: dict[str, str], body: bytes | None):
            calls.append((method, url))
            if method == "GET" and "betaBuildLocalizations" in url:
                self.assertNotIn("filter", url)
                return 200, {
                    "data": [
                        {"id": "loc-fr", "type": "betaBuildLocalizations", "attributes": {"locale": "fr-FR"}},
                        {"id": "loc-1", "type": "betaBuildLocalizations", "attributes": {"locale": "en-US"}},
                    ]
                }
            if method == "PATCH":
                return 200, {"data": {"id": "loc-1"}}
            self.fail(f"unexpected {method} {url}")

        client = asc_api.ASCClient(
            asc_api.ASCCredentials("KEY", "ISSUER", Path("/tmp/missing.p8")),
            http=http,
            token="test-token",
        )
        client.set_testflight_notes("build-1", "- Fixed stars.")
        self.assertEqual(calls[0][0], "GET")
        self.assertEqual(calls[1][0], "PATCH")
        self.assertIn("/v1/betaBuildLocalizations/loc-1", calls[1][1])

    def test_set_testflight_notes_creates_missing_locale(self) -> None:
        calls: list[tuple[str, str]] = []

        def http(method: str, url: str, headers: dict[str, str], body: bytes | None):
            calls.append((method, url))
            if method == "GET":
                return 200, {
                    "data": [
                        {"id": "loc-fr", "type": "betaBuildLocalizations", "attributes": {"locale": "fr-FR"}}
                    ]
                }
            if method == "POST":
                return 201, {"data": {"id": "loc-2"}}
            self.fail(f"unexpected {method} {url}")

        client = asc_api.ASCClient(
            asc_api.ASCCredentials("KEY", "ISSUER", Path("/tmp/missing.p8")),
            http=http,
            token="test-token",
        )
        client.set_testflight_notes("build-1", "- Fixed stars.")
        self.assertEqual(calls[1][0], "POST")
        self.assertTrue(calls[1][1].endswith("/v1/betaBuildLocalizations"))

    def test_set_phased_release_posts_when_missing(self) -> None:
        calls: list[tuple[str, str]] = []

        def http(method: str, url: str, headers: dict[str, str], body: bytes | None):
            calls.append((method, url))
            if method == "GET":
                return 200, {"data": None}
            if method == "POST":
                return 201, {"data": {"id": "phase-1"}}
            self.fail(f"unexpected {method} {url}")

        client = asc_api.ASCClient(
            asc_api.ASCCredentials("KEY", "ISSUER", Path("/tmp/missing.p8")),
            http=http,
            token="test-token",
        )
        client.set_phased_release("version-1", "ACTIVE")
        self.assertEqual(calls[1][0], "POST")
        self.assertIn("/v1/appStoreVersionPhasedReleases", calls[1][1])

    def test_halt_without_existing_phased_release_fails(self) -> None:
        def http(method: str, url: str, headers: dict[str, str], body: bytes | None):
            return 200, {"data": None}

        client = asc_api.ASCClient(
            asc_api.ASCCredentials("KEY", "ISSUER", Path("/tmp/missing.p8")),
            http=http,
            token="test-token",
        )
        with self.assertRaises(asc_api.ASCError):
            client.set_phased_release("version-1", "PAUSED")

    def test_find_build_id_is_none_until_registered(self) -> None:
        def http(method: str, url: str, headers: dict[str, str], body: bytes | None):
            return 200, {"data": []}

        client = asc_api.ASCClient(
            asc_api.ASCCredentials("KEY", "ISSUER", Path("/tmp/missing.p8")),
            http=http,
            token="test-token",
        )
        self.assertIsNone(client.find_build_id("app-1", "0.1.1", "8"))
        with self.assertRaises(asc_api.ASCError):
            client.build_id("app-1", "0.1.1", "8")

    def test_find_build_id_still_raises_on_auth_failure(self) -> None:
        def http(method: str, url: str, headers: dict[str, str], body: bytes | None):
            return 401, {"errors": [{"status": "401"}]}

        client = asc_api.ASCClient(
            asc_api.ASCCredentials("KEY", "ISSUER", Path("/tmp/missing.p8")),
            http=http,
            token="test-token",
        )
        with self.assertRaises(asc_api.ASCError):
            client.find_build_id("app-1", "0.1.1", "8")


SALES_REPORT = "\t".join(
    ["Provider", "SKU", "Title", "Product Type Identifier", "Units", "Apple Identifier"]
) + "\n" + "\n".join(
    "\t".join(row)
    for row in [
        ["APPLE", "ss", "Silver Screen", "1", "12", "6700000001"],
        ["APPLE", "ss", "Silver Screen", "1F", "3.00", "6700000001"],
        ["APPLE", "ss", "Silver Screen", "7", "40", "6700000001"],
        ["APPLE", "other", "Other App", "1", "99", "6700000002"],
    ]
) + "\n"


class ASCReportTests(unittest.TestCase):
    def client(self, http=None, download=None):
        return asc_api.ASCClient(
            asc_api.ASCCredentials("KEY", "ISSUER", Path("/tmp/missing.p8")),
            http=http or (lambda *args: self.fail("unexpected JSON call")),
            download=download or (lambda *args: self.fail("unexpected download")),
            token="test-token",
        )

    def test_sum_units_counts_first_downloads_for_one_app(self) -> None:
        self.assertEqual(asc_api.sum_units(SALES_REPORT, apple_id="6700000001"), 15)
        self.assertEqual(asc_api.sum_units(SALES_REPORT), 114)

    def test_sales_report_gunzips_and_sends_filters(self) -> None:
        seen = []

        def download(method, url, headers, body):
            seen.append((url, headers))
            return 200, gzip.compress(SALES_REPORT.encode())

        text = self.client(download=download).sales_report("8812345", "2026-10-11")
        self.assertEqual(text, SALES_REPORT)
        url, headers = seen[0]
        self.assertIn("filter%5BvendorNumber%5D=8812345", url)
        self.assertIn("filter%5BreportDate%5D=2026-10-11", url)
        self.assertIn("filter%5Bfrequency%5D=WEEKLY", url)
        self.assertEqual(headers["Accept"], "application/a-gzip")

    def test_sales_report_is_none_without_sales(self) -> None:
        client = self.client(download=lambda *args: (404, b'{"errors":[{"code":"NOT_FOUND"}]}'))
        self.assertIsNone(client.sales_report("8812345", "2026-10-11"))

    def test_sales_report_raises_on_permission_failure(self) -> None:
        client = self.client(download=lambda *args: (403, b'{"errors":[{"code":"FORBIDDEN"}]}'))
        with self.assertRaises(asc_api.ASCError):
            client.sales_report("8812345", "2026-10-11")

    def test_customer_reviews_flattens_attributes_newest_first(self) -> None:
        seen = []

        def http(method, url, headers, body):
            seen.append(url)
            return 200, {
                "data": [
                    {"id": "r1", "attributes": {"rating": 5, "title": "Great", "createdDate": "2026-10-12T10:00:00Z"}},
                ]
            }

        reviews = self.client(http=http).customer_reviews("app-1")
        self.assertEqual(reviews, [{"id": "r1", "rating": 5, "title": "Great", "createdDate": "2026-10-12T10:00:00Z"}])
        self.assertIn("/v1/apps/app-1/customerReviews", seen[0])
        self.assertIn("sort=-createdDate", seen[0])


class SlowResponse:
    """urlopen() result whose read() times out, like a stalled ASC report download."""

    status = 200

    def __enter__(self):
        return self

    def __exit__(self, *exc):
        return False

    def read(self):
        raise TimeoutError("The read operation timed out")


class ASCTransportTests(unittest.TestCase):
    def test_default_http_turns_a_network_failure_into_asc_error(self) -> None:
        refused = urllib.error.URLError(ConnectionRefusedError(61, "Connection refused"))
        with mock.patch("urllib.request.urlopen", side_effect=refused):
            with self.assertRaises(asc_api.ASCError) as caught:
                asc_api.default_http("GET", "https://api.appstoreconnect.apple.com/v1/apps?filter=x", {}, None)
        self.assertIn("/v1/apps", str(caught.exception))
        self.assertNotIn("filter=x", str(caught.exception))

    def test_default_http_turns_a_read_timeout_into_asc_error(self) -> None:
        with mock.patch("urllib.request.urlopen", return_value=SlowResponse()):
            with self.assertRaises(asc_api.ASCError):
                asc_api.default_http("GET", "https://api.appstoreconnect.apple.com/v1/apps", {}, None)

    def test_default_download_turns_timeouts_and_os_errors_into_asc_error(self) -> None:
        url = "https://api.appstoreconnect.apple.com/v1/salesReports"
        for failure in (TimeoutError("timed out"), ConnectionResetError(54, "reset"), OSError("unreachable")):
            with self.subTest(failure=failure):
                with mock.patch("urllib.request.urlopen", side_effect=failure):
                    with self.assertRaises(asc_api.ASCError):
                        asc_api.default_download("GET", url, {}, None)
        with mock.patch("urllib.request.urlopen", return_value=SlowResponse()):
            with self.assertRaises(asc_api.ASCError):
                asc_api.default_download("GET", url, {}, None)


if __name__ == "__main__":
    unittest.main()
