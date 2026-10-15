#!/usr/bin/env python3
"""Minimal GitHub issues client (stdlib only) for scheduled workflows.

Used by tmdb_health.py and weekly_digest.py. Reads GITHUB_TOKEN and
GITHUB_REPOSITORY, which Actions sets for every job. No pip packages.
"""

from __future__ import annotations

import json
import os
import urllib.error
import urllib.parse
import urllib.request
from typing import Any, Callable, Dict, Optional, Tuple


class GitHubError(Exception):
    """GitHub API or credential failure."""


HttpFn = Callable[[str, str, Dict[str, str], Optional[bytes]], Tuple[int, Any]]


def default_http(method, url, headers, body):
    request = urllib.request.Request(url, data=body, headers=headers, method=method)
    try:
        with urllib.request.urlopen(request, timeout=60) as response:
            raw = response.read()
            status = response.status
    except urllib.error.HTTPError as error:
        raw = error.read()
        status = error.code
    if not raw:
        return status, {}
    try:
        return status, json.loads(raw.decode())
    except json.JSONDecodeError as error:
        raise GitHubError(f"GitHub returned non-JSON ({status}): {raw[:200]!r}") from error


class GitHubIssues:
    def __init__(self, token, repo, http=default_http):
        self.token = token
        self.repo = repo
        self.http = http

    @classmethod
    def from_env(cls, http=default_http):
        token = os.environ.get("GITHUB_TOKEN", "").strip()
        repo = os.environ.get("GITHUB_REPOSITORY", "").strip()
        if not token or not repo:
            raise GitHubError("Set GITHUB_TOKEN and GITHUB_REPOSITORY to file issues.")
        return cls(token, repo, http=http)

    def request(self, method, path, query=None, payload=None):
        url = f"https://api.github.com/repos/{self.repo}{path}"
        if query:
            url += "?" + urllib.parse.urlencode(query)
        headers = {
            "Authorization": f"Bearer {self.token}",
            "Accept": "application/vnd.github+json",
            "X-GitHub-Api-Version": "2022-11-28",
            "Content-Type": "application/json",
        }
        body = None if payload is None else json.dumps(payload).encode()
        status, data = self.http(method, url, headers, body)
        if status >= 400:
            raise GitHubError(f"GitHub {method} {path} failed ({status}): {data}")
        return data

    def ensure_label(self, name, color="ededed", description=""):
        try:
            self.request("GET", "/labels/" + urllib.parse.quote(name, safe=""))
        except GitHubError as error:
            if "(404)" not in str(error):
                raise
            self.request(
                "POST",
                "/labels",
                payload={"name": name, "color": color, "description": description},
            )

    def issues(self, label, state="open", limit=10):
        """Issues (not PRs) with the label, newest first."""
        rows = self.request(
            "GET",
            "/issues",
            query={
                "labels": label,
                "state": state,
                "sort": "created",
                "direction": "desc",
                "per_page": str(limit),
            },
        )
        return [row for row in rows or [] if "pull_request" not in row]

    def create_issue(self, title, body, labels):
        return self.request(
            "POST",
            "/issues",
            payload={"title": title, "body": body, "labels": list(labels)},
        )

    def comment(self, number, body):
        return self.request("POST", f"/issues/{number}/comments", payload={"body": body})

    def file_or_comment(self, label, title, body):
        """Comment on the newest open issue with the label, or open one.

        Returns (issue number, True when a new issue was opened).
        """
        self.ensure_label(label)
        existing = self.issues(label, state="open", limit=1)
        if existing:
            number = existing[0]["number"]
            self.comment(number, body)
            return number, False
        created = self.create_issue(title, body, [label])
        return created["number"], True
