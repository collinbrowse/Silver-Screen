#!/usr/bin/env python3
"""Builder tests. They use the saved Wikidata payload and never call SPARQL."""

from __future__ import annotations

import json
import os
import subprocess
import sys
import tempfile
import unittest

sys.path.insert(0, os.path.dirname(__file__))
import build_awards_catalog as builder  # noqa: E402

FIXTURE = os.path.join(os.path.dirname(__file__), "fixtures", "wikidata_award_bindings.json")


class BuilderTests(unittest.TestCase):
    def test_saved_payload_becomes_sorted_credits(self):
        with open(FIXTURE, encoding="utf-8") as handle:
            payload = json.load(handle)
        credits = builder.credits_from_bindings(payload["results"]["bindings"], "academy", True)
        self.assertEqual({credit["title"] for credit in credits}, {"The Godfather", "Oppenheimer"})
        oppenheimer = next(credit for credit in credits if credit["title"] == "Oppenheimer")
        self.assertEqual(oppenheimer["category"], "Best Picture")
        self.assertEqual(oppenheimer["imdbID"], "tt15398776")
        self.assertEqual(oppenheimer["year"], 2024)
        self.assertTrue(oppenheimer["won"])
        godfather = next(credit for credit in credits if credit["title"] == "The Godfather")
        self.assertIsNone(godfather["imdbID"])
        self.assertEqual(godfather["category"], "Best Actor")

    def test_find_url_names_imdb_as_the_source(self):
        path = builder.tmdb_find_path("tt15398776")
        self.assertIn("/find/tt15398776?", path)
        self.assertIn("external_source=imdb_id", path)

    def test_category_query_reads_the_work_and_the_person(self):
        wins = builder.category_credits_query("Q103916", True)
        self.assertIn("pq:P1686 ?work", wins)
        self.assertIn("ps:P166 wd:Q103916", wins)
        nominations = builder.category_credits_query("Q989438", False)
        self.assertIn("ps:P1411 wd:Q989438", nominations)
        self.assertIn("pq:P1686 ?work", nominations)

    def test_previous_resolution_skips_find(self):
        raw = [
            {
                "key": "academy|Q102427|2024|won|Q108669",
                "family": "academy",
                "category": "Best Picture",
                "categoryID": "Q102427",
                "won": True,
                "year": 2024,
                "title": "Oppenheimer",
                "imdbID": "tt15398776",
                "wikidataID": "Q108669",
            }
        ]
        previous = {
            "generatedAt": "2026-01-01T00:00:00Z",
            "credits": [{**raw[0], "work": {"kind": "movie", "movieID": 872585}}],
        }
        calls = []

        def resolve(credit):
            calls.append(credit["imdbID"])
            return {"kind": "movie", "movieID": 1}

        catalog, changed = builder.assemble_catalog(raw, previous, resolve, "2026-09-27T10:00:00Z")
        self.assertEqual(calls, [])
        self.assertFalse(changed)
        self.assertEqual(catalog["credits"][0]["work"]["movieID"], 872585)

    def test_new_imdb_is_resolved_and_summarized(self):
        raw = [
            {
                "key": "academy|Q102427|2024|won|Q108669",
                "family": "academy",
                "category": "Best Picture",
                "categoryID": "Q102427",
                "won": True,
                "year": 2024,
                "title": "Oppenheimer",
                "imdbID": "tt15398776",
                "wikidataID": "Q108669",
            }
        ]
        previous = {"generatedAt": "2026-01-01T00:00:00Z", "credits": []}

        def resolve(credit):
            return {"kind": "movie", "movieID": 872585}

        catalog, changed = builder.assemble_catalog(raw, previous, resolve, "2026-09-27T10:00:00Z")
        self.assertTrue(changed)
        self.assertEqual(catalog["credits"][0]["work"], {"kind": "movie", "movieID": 872585})
        summary = builder.diff_summary(previous, catalog)
        self.assertIn("Added 1 credits", summary)
        self.assertIn("Oppenheimer", summary)
        self.assertIn("Removed 0 credits", summary)

    def test_failed_query_does_not_replace_the_file(self):
        with tempfile.TemporaryDirectory() as directory:
            path = os.path.join(directory, "AwardsCatalog.json")
            original = {"generatedAt": "2026-01-01T00:00:00Z", "credits": [{"key": "keep"}]}
            builder.write_catalog(path, original)

            def fetch(_query):
                raise builder.QueryFailure("timeout")

            with self.assertRaises(builder.QueryFailure):
                builder.collect_family(builder.FAMILIES[0], fetch)
            self.assertEqual(builder.load_catalog(path), original)

    def test_pr_body_matches_the_template(self):
        body = builder.render_pr_body("Added 1 credits. Removed 0 credits.\n")
        root = os.path.dirname(os.path.dirname(__file__))
        with tempfile.NamedTemporaryFile("w", suffix=".md", delete=False) as handle:
            handle.write(body)
            name = handle.name
        try:
            result = subprocess.run(
                [sys.executable, os.path.join(root, "scripts", "validate-pr-body.py"), "--file", name],
                check=False,
                capture_output=True,
                text=True,
                cwd=root,
            )
        finally:
            os.remove(name)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)


if __name__ == "__main__":
    unittest.main()

