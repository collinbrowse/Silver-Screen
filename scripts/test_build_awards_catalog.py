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
        self.assertIn("?personLabel", wins)
        self.assertIn("?personImdb", wins)
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

    def test_acting_credit_keeps_the_person_and_the_film(self):
        bindings = [
            {
                "work": {"type": "uri", "value": "http://www.wikidata.org/entity/Q123690368"},
                "workLabel": {"type": "literal", "value": "A Real Pain"},
                "imdb": {"type": "literal", "value": "tt21823606"},
                "year": {"type": "literal", "value": "2025"},
                "person": {"type": "uri", "value": "http://www.wikidata.org/entity/Q313204"},
                "personLabel": {"type": "literal", "value": "Kieran Culkin"},
                "personImdb": {"type": "literal", "value": "nm0000342"},
                "category": {"type": "uri", "value": "http://www.wikidata.org/entity/Q106291"},
                "categoryLabel": {
                    "type": "literal",
                    "value": "Academy Award for Best Supporting Actor",
                },
            },
            {
                "work": {"type": "uri", "value": "http://www.wikidata.org/entity/Q123690368"},
                "workLabel": {"type": "literal", "value": "A Real Pain"},
                "imdb": {"type": "literal", "value": "tt21823606"},
                "year": {"type": "literal", "value": "2025"},
                "person": {"type": "uri", "value": "http://www.wikidata.org/entity/Q23540"},
                "personLabel": {"type": "literal", "value": "Jesse Eisenberg"},
                "personImdb": {"type": "literal", "value": "not-a-person"},
                "categoryLabel": {
                    "type": "literal",
                    "value": "Academy Award for Best Supporting Actor",
                },
            },
        ]
        credits = builder.credits_from_bindings(
            bindings,
            "academy",
            True,
            category_id="Q106291",
            category_label="Best Supporting Actor",
        )
        self.assertEqual(len(credits), 1)
        self.assertEqual(credits[0]["title"], "A Real Pain")
        self.assertEqual(
            credits[0]["recipients"],
            [
                {"name": "Jesse Eisenberg", "wikidataID": "Q23540"},
                {"imdbID": "nm0000342", "name": "Kieran Culkin", "wikidataID": "Q313204"},
            ],
        )

    def test_attach_person_recipients_puts_the_actor_on_the_film(self):
        credits = [
            {
                "key": "film",
                "categoryID": "Q106291",
                "year": 2025,
                "won": True,
                "title": "A Real Pain",
                "wikidataID": "Q123",
                "imdbID": "tt21823606",
                "work": {"kind": "movie", "movieID": 1},
            },
            {
                "key": "person",
                "categoryID": "Q106291",
                "year": 2025,
                "won": True,
                "title": "Kieran Culkin",
                "wikidataID": "Q313204",
            },
            {
                "key": "picture",
                "categoryID": "Q102427",
                "year": 2024,
                "won": True,
                "title": "Oppenheimer",
                "wikidataID": "Q108669",
                "imdbID": "tt15398776",
            },
        ]
        links = [
            {
                "personID": "Q313204",
                "workID": "Q123",
                "categoryID": "Q106291",
                "year": 2025,
                "won": True,
                "name": "Kieran Culkin",
                "imdbID": "nm0000342",
            }
        ]
        updated = builder.attach_person_recipients(credits, links)
        film = next(credit for credit in updated if credit["key"] == "film")
        self.assertEqual(film["recipients"][0]["imdbID"], "nm0000342")
        self.assertEqual(film["recipients"][0]["name"], "Kieran Culkin")
        picture = next(credit for credit in updated if credit["key"] == "picture")
        self.assertNotIn("recipients", picture)
        person = next(credit for credit in updated if credit["key"] == "person")
        self.assertNotIn("recipients", person)

    def test_collect_person_links_asks_for_humans_then_their_prizes(self):
        queries = []

        def fetch(query):
            queries.append(query)
            if "pq:P1686" in query:
                return [
                    {
                        "person": {
                            "type": "uri",
                            "value": "http://www.wikidata.org/entity/Q313204",
                        },
                        "personLabel": {"type": "literal", "value": "Kieran Culkin"},
                        "personImdb": {"type": "literal", "value": "nm0000342"},
                        "work": {"type": "uri", "value": "http://www.wikidata.org/entity/Q123"},
                        "category": {
                            "type": "uri",
                            "value": "http://www.wikidata.org/entity/Q106291",
                        },
                        "year": {"type": "literal", "value": "2025"},
                        "outcome": {"type": "literal", "value": "won"},
                    }
                ]
            return [
                {"person": {"type": "uri", "value": "http://www.wikidata.org/entity/Q313204"}}
            ]

        links = builder.collect_person_links(["Q313204", "Q1"], fetch, sleep=lambda _seconds: None)
        self.assertEqual(links[0]["personID"], "Q313204")
        self.assertEqual(links[0]["workID"], "Q123")
        self.assertEqual(links[0]["imdbID"], "nm0000342")
        self.assertTrue(links[0]["won"])
        self.assertTrue(any("wdt:P31 wd:Q5" in query and "P1686" not in query for query in queries))
        self.assertTrue(any("wd:Q313204" in query and "P1686" in query for query in queries))
        self.assertFalse(any("wd:Q1" in query and "P1686" in query for query in queries))

    def test_entity_payload_reads_the_person_the_work_and_the_year(self):
        payload = {
            "entities": {
                "Q313204": {
                    "id": "Q313204",
                    "claims": {
                        "P31": [
                            {"mainsnak": {"datavalue": {"value": {"id": "Q5"}}}},
                        ],
                        "P345": [
                            {"mainsnak": {"datavalue": {"value": "nm0000342"}}},
                        ],
                        "P166": [
                            {
                                "mainsnak": {"datavalue": {"value": {"id": "Q106291"}}},
                                "qualifiers": {
                                    "P1686": [
                                        {"datavalue": {"value": {"id": "Q123690368"}}},
                                    ],
                                    "P585": [
                                        {
                                            "datavalue": {
                                                "value": {"time": "+2025-00-00T00:00:00Z"}
                                            }
                                        },
                                    ],
                                },
                            }
                        ],
                    },
                },
                "Q1": {
                    "id": "Q1",
                    "claims": {
                        "P31": [
                            {"mainsnak": {"datavalue": {"value": {"id": "Q5"}}}},
                        ],
                    },
                },
            }
        }
        links = builder.links_from_entity_payload(payload)
        self.assertEqual(
            links,
            [
                {
                    "personID": "Q313204",
                    "workID": "Q123690368",
                    "categoryID": "Q106291",
                    "year": 2025,
                    "won": True,
                    "imdbID": "nm0000342",
                }
            ],
        )

        film = {
            "entities": {
                "Q123": {
                    "id": "Q123",
                    "claims": {
                        "P31": [
                            {"mainsnak": {"datavalue": {"value": {"id": "Q11424"}}}},
                        ],
                        "P166": [
                            {
                                "mainsnak": {"datavalue": {"value": {"id": "Q102427"}}},
                                "qualifiers": {
                                    "P1686": [{"datavalue": {"value": {"id": "Q999"}}}],
                                    "P585": [
                                        {"datavalue": {"value": {"time": "+2024-03-10T00:00:00Z"}}}
                                    ],
                                },
                            }
                        ],
                    },
                }
            }
        }
        self.assertEqual(builder.links_from_entity_payload(film), [])


if __name__ == "__main__":
    unittest.main()

