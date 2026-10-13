#!/usr/bin/env python3
"""Tests for the App Store Connect helper used by release.py."""

from __future__ import annotations

import unittest
from pathlib import Path

import asc_api


class ASCClientTests(unittest.TestCase):
    def test_set_testflight_notes_patches_existing_localization(self) -> None:
        calls: list[tuple[str, str]] = []

        def http(method: str, url: str, headers: dict[str, str], body: bytes | None):
            calls.append((method, url))
            if method == "GET" and "betaBuildLocalizations" in url:
                return 200, {"data": [{"id": "loc-1", "type": "betaBuildLocalizations"}]}
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


if __name__ == "__main__":
    unittest.main()
