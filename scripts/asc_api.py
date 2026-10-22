#!/usr/bin/env python3
"""Minimal App Store Connect API client (stdlib + openssl).

Used by release.py for TestFlight notes and phased release, and by
weekly_digest.py for sales, downloads, and customer reviews. No pip packages.
"""

from __future__ import annotations

import base64
import csv
import gzip
import http.client
import io
import json
import os
import subprocess
import time
import urllib.error
import urllib.parse
import urllib.request
from dataclasses import dataclass
from pathlib import Path
from typing import Any, Callable, Dict, Optional, Tuple


class ASCError(Exception):
    """ASC API or credential failure the caller can fix."""


@dataclass(frozen=True)
class ASCCredentials:
    key_id: str
    issuer_id: str
    key_path: Path


def load_credentials():
    key_id = os.environ.get("ASC_KEY_ID", "").strip()
    issuer = os.environ.get("ASC_ISSUER_ID", "").strip()
    missing = [name for name, value in (("ASC_KEY_ID", key_id), ("ASC_ISSUER_ID", issuer)) if not value]
    if missing:
        raise ASCError("Set " + " and ".join(missing) + " for App Store Connect API calls.")

    key_path_env = os.environ.get("ASC_KEY_PATH", "").strip()
    if key_path_env:
        key_path = Path(key_path_env).expanduser().resolve()
    else:
        candidates = [
            Path.home() / "private_keys" / f"AuthKey_{key_id}.p8",
            Path.home() / ".private_keys" / f"AuthKey_{key_id}.p8",
            Path.home() / ".appstoreconnect" / "private_keys" / f"AuthKey_{key_id}.p8",
        ]
        key_path = next((path for path in candidates if path.is_file()), candidates[0])

    if not key_path.is_file():
        raise ASCError(
            f"ASC API key file not found at {key_path}. "
            "Set ASC_KEY_PATH or place AuthKey_<ASC_KEY_ID>.p8 in ~/private_keys."
        )
    return ASCCredentials(key_id=key_id, issuer_id=issuer, key_path=key_path)


def _b64url(data: bytes) -> str:
    return base64.urlsafe_b64encode(data).rstrip(b"=").decode("ascii")


def _der_ecdsa_to_jose(der: bytes) -> bytes:
    """Convert OpenSSL ECDSA-SHA256 DER signature to JWT R||S (64 bytes)."""
    if len(der) < 8 or der[0] != 0x30:
        raise ASCError("Unexpected ECDSA signature encoding from openssl.")
    # SEQ { INT r, INT s }
    index = 2 if der[1] < 0x80 else 3
    if der[index] != 0x02:
        raise ASCError("ECDSA signature missing R integer.")
    r_len = der[index + 1]
    r = der[index + 2 : index + 2 + r_len]
    index = index + 2 + r_len
    if der[index] != 0x02:
        raise ASCError("ECDSA signature missing S integer.")
    s_len = der[index + 1]
    s = der[index + 2 : index + 2 + s_len]
    return r.lstrip(b"\x00").rjust(32, b"\x00") + s.lstrip(b"\x00").rjust(32, b"\x00")


def make_token(credentials: ASCCredentials, now=None):
    """ES256 JWT for App Store Connect (20 minute lifetime)."""
    issued = int(time.time() if now is None else now)
    header = {"alg": "ES256", "kid": credentials.key_id, "typ": "JWT"}
    payload = {
        "iss": credentials.issuer_id,
        "iat": issued,
        "exp": issued + 20 * 60,
        "aud": "appstoreconnect-v1",
    }
    signing_input = (
        f"{_b64url(json.dumps(header, separators=(',', ':')).encode())}."
        f"{_b64url(json.dumps(payload, separators=(',', ':')).encode())}"
    ).encode()

    result = subprocess.run(
        ["openssl", "dgst", "-sha256", "-sign", str(credentials.key_path)],
        input=signing_input,
        capture_output=True,
        check=False,
    )
    if result.returncode != 0:
        raise ASCError(f"openssl failed to sign ASC JWT: {result.stderr.decode().strip()}")
    signature = _b64url(_der_ecdsa_to_jose(result.stdout))
    return signing_input.decode() + "." + signature


HttpFn = Callable[[str, str, Dict[str, str], Optional[bytes]], Tuple[int, Dict[str, Any]]]


def _send(method, url, headers, body, timeout):
    """(status, raw bytes) for one request. HTTP errors return their status and body.

    A network failure (DNS, refused connection, timeout, dropped connection) is an
    ASCError, so a caller that guards ASC calls does not crash on it.
    """
    request = urllib.request.Request(url, data=body, headers=headers, method=method)
    try:
        with urllib.request.urlopen(request, timeout=timeout) as response:
            return response.status, response.read()
    except urllib.error.HTTPError as error:
        return error.code, error.read()
    except (OSError, http.client.HTTPException) as error:
        # URLError and TimeoutError are OSErrors. Log the path, never the query.
        raise ASCError(f"{method} {url.split('?')[0]} failed: {error}") from error


def default_http(method, url, headers, body):
    status, raw = _send(method, url, headers, body, timeout=60)
    if not raw:
        return status, {}
    try:
        return status, json.loads(raw.decode())
    except json.JSONDecodeError as error:
        raise ASCError(f"ASC returned non-JSON ({status}): {raw[:200]!r}") from error


def default_download(method, url, headers, body):
    """Like default_http, but returns raw bytes. Reports come back gzipped, not JSON."""
    return _send(method, url, headers, body, timeout=120)


# Product Type Identifiers for a first-time app download (not an update or
# redownload): iPhone, universal, and iPad.
DOWNLOAD_PRODUCT_TYPES = frozenset({"1", "1F", "1T"})


def sum_units(report_text, apple_id=None, product_types=DOWNLOAD_PRODUCT_TYPES):
    """Total Units in a tab-separated Sales report for the given product types.

    apple_id limits the total to one app, since a vendor's report covers all of its apps.
    """
    total = 0
    reader = csv.DictReader(io.StringIO(report_text), delimiter="\t")
    for row in reader:
        if (row.get("Product Type Identifier") or "").strip() not in product_types:
            continue
        if apple_id is not None and (row.get("Apple Identifier") or "").strip() != str(apple_id):
            continue
        try:
            total += int(float(row.get("Units") or 0))
        except ValueError:
            continue
    return total


class ASCClient:
    """Thin App Store Connect API wrapper for release automation."""

    def __init__(
        self,
        credentials,
        http=default_http,
        token=None,
        bundle_id="com.collinbrowse.thesilverscreen",
        download=default_download,
    ):
        self.credentials = credentials
        self.http = http
        self.download = download
        self._token = token
        # None for an injected token, which never expires in tests.
        self._token_issued = None
        self.bundle_id = bundle_id

    @property
    def token(self):
        # Tokens live 20 minutes. Waiting on build processing can outlast one.
        stale = self._token_issued is not None and time.time() - self._token_issued > 15 * 60
        if self._token is None or stale:
            self._token_issued = time.time()
            self._token = make_token(self.credentials)
        return self._token

    def request(self, method, path, query=None, payload=None):
        url = "https://api.appstoreconnect.apple.com" + path
        if query:
            url += "?" + urllib.parse.urlencode(query)
        headers = {
            "Authorization": f"Bearer {self.token}",
            "Content-Type": "application/json",
        }
        body = None if payload is None else json.dumps(payload).encode()
        status, data = self.http(method, url, headers, body)
        if status >= 400:
            raise ASCError(f"ASC {method} {path} failed ({status}): {data}")
        return data

    def app_id(self):
        data = self.request(
            "GET",
            "/v1/apps",
            query={"filter[bundleId]": self.bundle_id, "limit": "1"},
        )
        rows = data.get("data") or []
        if not rows:
            raise ASCError(f"No App Store Connect app for bundle id {self.bundle_id}.")
        return str(rows[0]["id"])

    def find_build_id(self, app_id, version, build):
        """Build id, or None while App Store Connect has not registered the upload yet."""
        data = self.request(
            "GET",
            "/v1/builds",
            query={
                "filter[app]": app_id,
                "filter[version]": build,
                "filter[preReleaseVersion.version]": version,
                "limit": "1",
            },
        )
        rows = data.get("data") or []
        if not rows:
            # Broader fallback: CFBundleVersion alone.
            data = self.request(
                "GET",
                "/v1/builds",
                query={"filter[app]": app_id, "filter[version]": build, "limit": "5"},
            )
            rows = data.get("data") or []
        return str(rows[0]["id"]) if rows else None

    def build_id(self, app_id, version, build):
        found = self.find_build_id(app_id, version, build)
        if found is None:
            raise ASCError(
                f"No ASC build for {version} ({build}). "
                "Wait for processing after upload, then retry."
            )
        return found

    def set_testflight_notes(self, build_id, notes, locale="en-US"):
        # This relationship endpoint rejects filter[locale] (400 PARAMETER_ERROR.ILLEGAL),
        # so list them all and match the locale here.
        listed = self.request(
            "GET",
            f"/v1/builds/{build_id}/betaBuildLocalizations",
            query={"limit": "50"},
        )
        rows = [
            row
            for row in listed.get("data") or []
            if (row.get("attributes") or {}).get("locale") == locale
        ]
        attributes = {"whatsNew": notes}
        if rows:
            localization_id = rows[0]["id"]
            self.request(
                "PATCH",
                f"/v1/betaBuildLocalizations/{localization_id}",
                payload={
                    "data": {
                        "type": "betaBuildLocalizations",
                        "id": localization_id,
                        "attributes": attributes,
                    }
                },
            )
            return
        self.request(
            "POST",
            "/v1/betaBuildLocalizations",
            payload={
                "data": {
                    "type": "betaBuildLocalizations",
                    "attributes": {"locale": locale, **attributes},
                    "relationships": {
                        "build": {"data": {"type": "builds", "id": build_id}}
                    },
                }
            },
        )

    def app_store_version_id(self, app_id, marketing):
        data = self.request(
            "GET",
            f"/v1/apps/{app_id}/appStoreVersions",
            query={
                "filter[versionString]": marketing,
                "filter[platform]": "IOS",
                "limit": "1",
            },
        )
        rows = data.get("data") or []
        if not rows:
            raise ASCError(f"No App Store version {marketing} on ASC. Create it first.")
        return str(rows[0]["id"])

    def set_phased_release(self, version_id, state):
        """state: ACTIVE | PAUSED | COMPLETE"""
        existing = self.request(
            "GET",
            f"/v1/appStoreVersions/{version_id}/appStoreVersionPhasedRelease",
        )
        rows = existing.get("data")
        attributes = {"phasedReleaseState": state}
        if rows:
            release_id = rows["id"] if isinstance(rows, dict) else rows[0]["id"]
            self.request(
                "PATCH",
                f"/v1/appStoreVersionPhasedReleases/{release_id}",
                payload={
                    "data": {
                        "type": "appStoreVersionPhasedReleases",
                        "id": release_id,
                        "attributes": attributes,
                    }
                },
            )
            return
        if state != "ACTIVE":
            raise ASCError(
                f"No phased release to set to {state}. Start one with rollout --start first."
            )
        self.request(
            "POST",
            "/v1/appStoreVersionPhasedReleases",
            payload={
                "data": {
                    "type": "appStoreVersionPhasedReleases",
                    "attributes": attributes,
                    "relationships": {
                        "appStoreVersion": {
                            "data": {"type": "appStoreVersions", "id": version_id}
                        }
                    },
                }
            },
        )

    def sales_report(self, vendor_number, report_date, frequency="WEEKLY"):
        """Sales summary as tab-separated text, or None when Apple has no report.

        Apple answers 404 for a period with no sales, which is every period before
        launch, and for a period whose report is not published yet. WEEKLY dates
        are the Sunday that ends the week.
        """
        query = {
            "filter[frequency]": frequency,
            "filter[reportType]": "SALES",
            "filter[reportSubType]": "SUMMARY",
            "filter[vendorNumber]": str(vendor_number),
            "filter[reportDate]": report_date,
            "filter[version]": "1_0",
        }
        url = "https://api.appstoreconnect.apple.com/v1/salesReports?" + urllib.parse.urlencode(query)
        headers = {"Authorization": f"Bearer {self.token}", "Accept": "application/a-gzip"}
        status, raw = self.download("GET", url, headers, None)
        if status == 404:
            return None
        if status >= 400:
            raise ASCError(f"ASC sales report {report_date} failed ({status}): {raw[:300]!r}")
        try:
            raw = gzip.decompress(raw)
        except OSError:
            pass  # Already plain text.
        return raw.decode("utf-8")

    def customer_reviews(self, app_id, limit=50):
        """Newest customer reviews first, as attribute dicts with an added id."""
        data = self.request(
            "GET",
            f"/v1/apps/{app_id}/customerReviews",
            query={"sort": "-createdDate", "limit": str(limit)},
        )
        return [
            {"id": row.get("id"), **(row.get("attributes") or {})}
            for row in data.get("data") or []
        ]
