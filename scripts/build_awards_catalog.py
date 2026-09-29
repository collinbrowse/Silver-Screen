#!/usr/bin/env python3
"""Rebuild TheSilverScreen/Data/Resources/AwardsCatalog.json from Wikidata.

Queries one award family at a time. A failed query exits before the file is
replaced, so a timeout cannot wipe the catalog. Already-resolved TMDB ids are
copied forward and are not sent through /find again.

No third-party packages. Tests import this module and never hit the network.
"""

from __future__ import annotations

import argparse
import json
import os
import re
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
from datetime import datetime, timezone

WIKIDATA_URL = "https://query.wikidata.org/sparql"
WIKIDATA_ENTITIES = "https://www.wikidata.org/w/api.php"
TMDB_FIND = "https://api.themoviedb.org/3/find/"
TMDB_TV = "https://api.themoviedb.org/3/tv/"
USER_AGENT = (
    "TheSilverScreenAwardsCatalog/1.0 "
    "(https://github.com/collinbrowse/The-Silver-Screen)"
)
IMDB_ID = re.compile(r"^tt\d+$")
PERSON_IMDB = re.compile(r"^nm\d+$")

# P31 or P361 points at the prize body. Acting credits also come from people
# via qualifier P1686 (for work), not only from the film or episode item.
FAMILIES = (
    {"id": "academy", "qid": "Q19020", "prefer": "movie"},
    {"id": "bafta", "qid": "Q732997", "prefer": "movie"},
    {"id": "emmy", "qid": "Q1044427", "prefer": "tv"},
)

CATEGORY_PREFIXES = (
    "Academy Award for ",
    "Academy Awards for ",
    "British Academy Film Award for ",
    "British Academy Film Awards for ",
    "BAFTA Award for ",
    "Primetime Emmy Award for ",
    "Primetime Emmy for ",
    "Emmy Award for ",
)


class QueryFailure(Exception):
    """Wikidata did not return a usable payload. The catalog file must stay put."""


class ResolveFailure(Exception):
    """TMDB rejected the run (auth or repeated server errors). Do not publish."""


def short_category(label: str) -> str:
    for prefix in CATEGORY_PREFIXES:
        if label.startswith(prefix):
            return label[len(prefix) :]
    return label


def credit_key(family: str, category_id: str, year: int, won: bool, wikidata_id: str) -> str:
    outcome = "won" if won else "nominated"
    return f"{family}|{category_id}|{year}|{outcome}|{wikidata_id}"


def qid_from_uri(uri: str) -> str:
    return uri.rstrip("/").split("/")[-1]


def binding_value(binding: dict, name: str) -> str | None:
    item = binding.get(name)
    if not isinstance(item, dict):
        return None
    value = item.get("value")
    if value is None:
        return None
    return str(value)


def family_pattern(qid: str) -> str:
    return f"{{ ?category wdt:P31 wd:{qid} }} UNION {{ ?category wdt:P361 wd:{qid} }}"


def category_list_query(family_qid: str) -> str:
    return f"""
SELECT ?category ?categoryLabel WHERE {{
  {family_pattern(family_qid)}
  ?category rdfs:label ?categoryLabel . FILTER(LANG(?categoryLabel) = "en")
}}
""".strip()


def category_credits_query(category_qid: str, won: bool) -> str:
    """Wins or nominations for one category.

    A family-wide query times out. Acting awards live on the person, with the
    film or episode in qualifier P1686, so both shapes are read together.
    """
    predicate = "P166" if won else "P1411"
    return f"""
SELECT ?work ?workLabel ?imdb ?year ?person ?personLabel ?personImdb WHERE {{
  {{
    ?work p:{predicate} ?stmt .
    ?stmt ps:{predicate} wd:{category_qid} .
  }} UNION {{
  ?person p:{predicate} ?stmt .
    ?stmt ps:{predicate} wd:{category_qid} .
  ?stmt pq:P1686 ?work .
  }}
  OPTIONAL {{ ?stmt pq:P585 ?time . BIND(YEAR(?time) AS ?year) }}
  OPTIONAL {{ ?work wdt:P345 ?imdb }}
  OPTIONAL {{ ?work rdfs:label ?workLabel . FILTER(LANG(?workLabel) = "en") }}
  OPTIONAL {{ ?person rdfs:label ?personLabel . FILTER(LANG(?personLabel) = "en") }}
  OPTIONAL {{ ?person wdt:P345 ?personImdb }}
}}
""".strip()


def credits_from_bindings(
    bindings: list[dict],
    family: str,
    won: bool,
    category_id: str | None = None,
    category_label: str | None = None,
) -> list[dict]:
    credits: list[dict] = []
    for binding in bindings:
        work_uri = binding_value(binding, "work")
        category_uri = binding_value(binding, "category")
        resolved_category_id = qid_from_uri(category_uri) if category_uri else category_id
        if not work_uri or not resolved_category_id:
            continue
        year_raw = binding_value(binding, "year")
        if not year_raw:
            continue
        try:
            year = int(float(year_raw))
        except ValueError:
            continue
        label = binding_value(binding, "categoryLabel") or category_label
        if not label or _looks_like_qid(label):
            continue
        wikidata_id = qid_from_uri(work_uri)
        title = binding_value(binding, "workLabel") or wikidata_id
        if _looks_like_qid(title):
            title = wikidata_id
        imdb = _clean_imdb(binding_value(binding, "imdb"))
        credit = {
            "key": credit_key(family, resolved_category_id, year, won, wikidata_id),
            "family": family,
            "category": short_category(label),
            "categoryID": resolved_category_id,
            "won": won,
            "year": year,
            "title": title,
            "imdbID": imdb,
            "wikidataID": wikidata_id,
        }
        recipient = _recipient_from_binding(binding)
        if recipient:
            credit["recipients"] = [recipient]
        credits.append(credit)
    return collapse(credits)


def collapse(credits: list[dict]) -> list[dict]:
    """One row per key. Prefer the copy that already has an IMDb id, and keep every person."""
    by_key: dict[str, dict] = {}
    for credit in credits:
        existing = by_key.get(credit["key"])
        if existing is None:
            chosen = dict(credit)
            recipients = _merge_recipients(credit)
        elif not existing.get("imdbID") and credit.get("imdbID"):
            chosen = dict(credit)
            recipients = _merge_recipients(existing, credit)
        else:
            chosen = dict(existing)
            recipients = _merge_recipients(existing, credit)
        if recipients:
            chosen["recipients"] = recipients
        else:
            chosen.pop("recipients", None)
        by_key[credit["key"]] = chosen
    return list(by_key.values())


def _merge_recipients(*credits: dict) -> list[dict]:
    by_id: dict[str, dict] = {}
    for credit in credits:
        for recipient in credit.get("recipients") or []:
            if not isinstance(recipient, dict):
                continue
            qid = recipient.get("wikidataID")
            if not isinstance(qid, str) or not qid:
                continue
            current = by_id.get(qid)
            if current is None or (not current.get("imdbID") and recipient.get("imdbID")):
                by_id[qid] = {part: item for part, item in recipient.items() if item is not None}
    return sorted(by_id.values(), key=lambda item: (str(item.get("name", "")).casefold(), item["wikidataID"]))


def _recipient_from_binding(binding: dict) -> dict | None:
    person_uri = binding_value(binding, "person")
    if not person_uri:
        return None
    name = binding_value(binding, "personLabel")
    if not name or _looks_like_qid(name):
        return None
    recipient = {"name": name, "wikidataID": qid_from_uri(person_uri)}
    imdb = _clean_person_imdb(binding_value(binding, "personImdb"))
    if imdb:
        recipient["imdbID"] = imdb
    return recipient


def apply_previous_resolutions(credits: list[dict], previous: dict) -> list[dict]:
    """Copy a stored TMDB work when the IMDb id has not changed."""
    prior = {item.get("key"): item for item in previous.get("credits", []) if item.get("key")}
    merged: list[dict] = []
    for credit in credits:
        copy = dict(credit)
        old = prior.get(copy["key"])
        if old and old.get("work") and old.get("imdbID") == copy.get("imdbID"):
            copy["work"] = old["work"]
        merged.append(copy)
    return merged


def public_credit(credit: dict) -> dict:
    cleaned = {}
    for key, value in credit.items():
        if key.startswith("_") or value is None:
            continue
        if key == "work" and isinstance(value, dict):
            cleaned[key] = {part: item for part, item in value.items() if item is not None}
        elif key == "recipients" and isinstance(value, list):
            people = [
                {part: item for part, item in recipient.items() if item is not None}
                for recipient in value
                if isinstance(recipient, dict)
            ]
            if people:
                cleaned[key] = people
        else:
            cleaned[key] = value
    return cleaned


def sorted_credits(credits: list[dict]) -> list[dict]:
    return sorted(
        (public_credit(credit) for credit in credits),
        key=lambda credit: (
            credit.get("family", ""),
            credit.get("category", ""),
            -int(credit.get("year", 0)),
            str(credit.get("title", "")).casefold(),
            credit.get("key", ""),
        ),
    )


def comparable_credits(catalog: dict) -> list[str]:
    return sorted(
        json.dumps(public_credit(credit), sort_keys=True) for credit in catalog.get("credits", [])
    )


def catalogs_differ(previous: dict, current: dict) -> bool:
    return comparable_credits(previous) != comparable_credits(current)


def diff_summary(previous: dict, current: dict) -> str:
    old = {credit["key"]: credit for credit in previous.get("credits", []) if credit.get("key")}
    new = {credit["key"]: credit for credit in current.get("credits", []) if credit.get("key")}
    added = [new[key] for key in sorted(set(new) - set(old))]
    removed = [old[key] for key in sorted(set(old) - set(new))]
    updated = [
        key
        for key in sorted(set(old) & set(new))
        if public_credit(old[key]) != public_credit(new[key])
    ]
    lines = [
        f"Added {len(added)} credits. Removed {len(removed)} credits.",
        "",
    ]
    if updated:
        lines.extend([f"Updated {len(updated)} credits.", ""])
    lines.extend(_sample("Added", added))
    lines.extend(_sample("Removed", removed))
    return "\n".join(lines).rstrip() + "\n"


def render_pr_body(summary: str) -> str:
    return f"""## Summary

Weekly rebuild of the bundled awards catalog from Wikidata. This pull request exists because the credit list changed. Merging it is the approval; nothing auto-merges.

## Decision Tree and Rationale

The Monday workflow rebuilds `TheSilverScreen/Data/Resources/AwardsCatalog.json` and opens a pull request only when credits change. A quiet week leaves main alone. Already-resolved TMDB ids stay in the file so later runs do not call `/find` for the whole history. `GITHUB_TOKEN` does not trigger the CI workflow on this pull request, so the review is the check.

## Test Plan

How to verify this PR (commands, screens, edge cases).

- [ ] `python3 scripts/validate-rules.py`
- [ ] `python3 scripts/validate-tests.py`
- [ ] `python3 scripts/validate-pr-body.py --pr <number>` (or pipe the body on stdin)
- [ ] `xcodebuild test -scheme TheSilverScreen -only-testing:TheSilverScreenTests`
- [ ] Screenshot path (if UI changed): None

Catalog diff:

{summary.rstrip()}

## AI Harness notes

None. The workflow and builder already live on main; this pull request only updates the JSON catalog.
"""


def assemble_catalog(credits: list[dict], previous: dict, resolve, generated_at: str) -> tuple[dict, bool]:
    """Merge stored ids, resolve the rest, and skip the write when credits match."""
    merged = apply_previous_resolutions(credits, previous)
    for credit in merged:
        if credit.get("work") or not credit.get("imdbID"):
            continue
        credit["work"] = resolve(credit)
    catalog = {"generatedAt": generated_at, "credits": sorted_credits(merged)}
    if not catalogs_differ(previous, catalog):
        return previous, False
    return catalog, True


def needs_network_resolution(credits: list[dict]) -> bool:
    return any(not credit.get("work") and credit.get("imdbID") for credit in credits)


def fetch_bindings(query: str, opener=None, timeout: int = 60) -> list[dict]:
    delay = 2.0
    last_error = "Wikidata query failed"
    for attempt in range(4):
        try:
            return _fetch_bindings_once(query, opener, timeout)
        except QueryFailure as error:
            last_error = str(error)
            if attempt == 3 or not _retryable(last_error):
                raise
            time.sleep(delay)
            delay *= 2
    raise QueryFailure(last_error)


def collect_family(family: dict, fetch) -> list[dict]:
    """One family, one category at a time. A family-wide query times out and must not wipe the file."""
    credits: list[dict] = []
    categories = _categories(family, fetch)
    first = True
    for category in categories:
        for won in (True, False):
            if not first:
                time.sleep(0.2)
            first = False
            bindings = fetch(category_credits_query(category["id"], won))
            credits.extend(
                credits_from_bindings(
                    bindings,
                    family["id"],
                    won,
                    category_id=category["id"],
                    category_label=category["label"],
                )
            )
        print(f"  {category['label']}", flush=True)
    return collapse(credits)


def write_catalog(path: str, catalog: dict) -> None:
    directory = os.path.dirname(path) or "."
    os.makedirs(directory, exist_ok=True)
    temporary = path + ".tmp"
    with open(temporary, "w", encoding="utf-8") as handle:
        json.dump(catalog, handle, indent=2, sort_keys=True)
        handle.write("\n")
    os.replace(temporary, path)


def load_catalog(path: str) -> dict:
    if not os.path.exists(path):
        return {"generatedAt": "1970-01-01T00:00:00Z", "credits": []}
    with open(path, encoding="utf-8") as handle:
        return json.load(handle)


def make_tmdb_resolver(api_key: str, opener=None):
    found: dict[str, dict | None] = {}
    series_names: dict[int, str] = {}

    def resolve(credit: dict):
        imdb = credit.get("imdbID")
        if not imdb:
            return None
        if imdb in found:
            cached = found[imdb]
            return None if cached is None else json.loads(json.dumps(cached))
        time.sleep(0.05)
        payload = _tmdb_json(tmdb_find_path(imdb), api_key, opener)
        work = _pick_work(payload, credit.get("family"))
        if work and work.get("kind") in {"series", "season", "episode"} and work.get("seriesID"):
            series_id = int(work["seriesID"])
            if series_id not in series_names:
                series_names[series_id] = _series_name(series_id, api_key, opener)
            if series_names[series_id]:
                work["seriesName"] = series_names[series_id]
        found[imdb] = work
        return None if work is None else json.loads(json.dumps(work))

    return resolve


def person_subject_qids(credits: list[dict]) -> list[str]:
    """Wikidata ids that never resolved to a title. People and unresolved works both land here."""
    work_ids: set[str] = set()
    loose: set[str] = set()
    for credit in credits:
        qid = credit.get("wikidataID")
        if not isinstance(qid, str) or not qid:
            continue
        if credit.get("imdbID") or credit.get("work"):
            work_ids.add(qid)
        else:
            loose.add(qid)
    return sorted(loose - work_ids)


def human_qids_query(qids: list[str]) -> str:
    values = " ".join(f"wd:{qid}" for qid in qids)
    return f"""
SELECT ?person WHERE {{
  VALUES ?person {{ {values} }}
  ?person wdt:P31 wd:Q5 .
}}
""".strip()


def person_award_links_query(qids: list[str]) -> str:
    """Person, the title in P1686, and whether the statement is a win."""
    values = " ".join(f"wd:{qid}" for qid in qids)
    return f"""
SELECT ?person ?personLabel ?personImdb ?work ?category ?year ?outcome WHERE {{
  VALUES ?person {{ {values} }}
  ?person wdt:P31 wd:Q5 .
  {{
    ?person p:P166 ?stmt .
    ?stmt ps:P166 ?category .
    BIND("won" AS ?outcome)
  }} UNION {{
    ?person p:P1411 ?stmt .
    ?stmt ps:P1411 ?category .
    BIND("nominated" AS ?outcome)
  }}
  ?stmt pq:P1686 ?work .
  OPTIONAL {{ ?person rdfs:label ?personLabel . FILTER(LANG(?personLabel) = "en") }}
  OPTIONAL {{ ?person wdt:P345 ?personImdb }}
  OPTIONAL {{ ?stmt pq:P585 ?time . BIND(YEAR(?time) AS ?year) }}
}}
""".strip()


def links_from_bindings(bindings: list[dict]) -> list[dict]:
    links: list[dict] = []
    seen: set[tuple] = set()
    for binding in bindings:
        person_uri = binding_value(binding, "person")
        work_uri = binding_value(binding, "work")
        category_uri = binding_value(binding, "category")
        if not person_uri or not work_uri or not category_uri:
            continue
        year_raw = binding_value(binding, "year")
        if not year_raw:
            continue
        try:
            year = int(float(year_raw))
        except ValueError:
            continue
        outcome = binding_value(binding, "outcome")
        if outcome not in {"won", "nominated"}:
            continue
        link = {
            "personID": qid_from_uri(person_uri),
            "workID": qid_from_uri(work_uri),
            "categoryID": qid_from_uri(category_uri),
            "year": year,
            "won": outcome == "won",
        }
        name = binding_value(binding, "personLabel")
        if name and not _looks_like_qid(name):
            link["name"] = name
        imdb = _clean_person_imdb(binding_value(binding, "personImdb"))
        if imdb:
            link["imdbID"] = imdb
        identity = (link["personID"], link["workID"], link["categoryID"], link["year"], link["won"])
        if identity in seen:
            continue
        seen.add(identity)
        links.append(link)
    return links


def attach_person_recipients(credits: list[dict], links: list[dict]) -> list[dict]:
    """Copy each person onto the title credit for that category and year. Person-only rows stay as they are."""
    names: dict[str, str] = {}
    for credit in credits:
        qid = credit.get("wikidataID")
        title = credit.get("title") or ""
        if (
            isinstance(qid, str)
            and title
            and not _looks_like_qid(title)
            and not credit.get("imdbID")
            and not credit.get("work")
        ):
            names.setdefault(qid, title)
    person_ids = {link["personID"] for link in links} | set(names)
    result = [dict(credit) for credit in credits]
    index: dict[tuple, list[int]] = {}
    for i, credit in enumerate(result):
        wikidata_id = credit.get("wikidataID")
        if not isinstance(wikidata_id, str) or not wikidata_id:
            continue
        if wikidata_id in person_ids and not credit.get("imdbID") and not credit.get("work"):
            continue
        try:
            year = int(credit.get("year"))
        except (TypeError, ValueError):
            continue
        key = (credit.get("categoryID"), year, bool(credit.get("won")), wikidata_id)
        index.setdefault(key, []).append(i)
    for link in links:
        name = link.get("name") or names.get(link["personID"])
        if not name or _looks_like_qid(name):
            continue
        recipient = {"name": name, "wikidataID": link["personID"]}
        if link.get("imdbID"):
            recipient["imdbID"] = link["imdbID"]
        key = (link["categoryID"], link["year"], link["won"], link["workID"])
        for i in index.get(key, []):
            merged = _merge_recipients(result[i], {"recipients": [recipient]})
            if merged:
                result[i]["recipients"] = merged
    return result


def _chunks(items: list[str], size: int):
    for start in range(0, len(items), size):
        yield items[start : start + size]


def links_from_entity_payload(payload: dict) -> list[dict]:
    """Wins and nominations that name a work, read from wbgetentities claims."""
    links: list[dict] = []
    seen: set[tuple] = set()
    for qid, entity in (payload.get("entities") or {}).items():
        if not isinstance(entity, dict) or entity.get("missing"):
            continue
        if not _entity_is_human(entity):
            continue
        person_id = entity.get("id") if isinstance(entity.get("id"), str) else qid
        imdb = _entity_imdb(entity)
        claims = entity.get("claims") or {}
        for prop, won in (("P166", True), ("P1411", False)):
            for claim in claims.get(prop) or []:
                if not isinstance(claim, dict):
                    continue
                category = _snak_qid(claim.get("mainsnak"))
                work = _qualifier_qid(claim, "P1686")
                year = _qualifier_year(claim)
                if not category or not work or year is None:
                    continue
                link = {
                    "personID": person_id,
                    "workID": work,
                    "categoryID": category,
                    "year": year,
                    "won": won,
                }
                if imdb:
                    link["imdbID"] = imdb
                identity = (person_id, work, category, year, won)
                if identity in seen:
                    continue
                seen.add(identity)
                links.append(link)
    return links


def collect_entity_links(qids: list[str], fetch_json, sleep=time.sleep) -> list[dict]:
    """One wbgetentities call per 50 people. Much smaller than asking SPARQL for every prize."""
    links: list[dict] = []
    batches = list(_chunks(qids, 50))
    for index, batch in enumerate(batches, start=1):
        print(f"  people {index}/{len(batches)}", flush=True)
        payload = fetch_json(_entity_url(batch))
        links.extend(links_from_entity_payload(payload))
        sleep(0.15)
    return links


def _entity_url(qids: list[str]) -> str:
    return WIKIDATA_ENTITIES + "?" + urllib.parse.urlencode(
        {
            "action": "wbgetentities",
            "ids": "|".join(qids),
            "props": "claims",
            "format": "json",
        }
    )


def _entity_is_human(entity: dict) -> bool:
    for claim in (entity.get("claims") or {}).get("P31") or []:
        if _snak_qid(claim.get("mainsnak") if isinstance(claim, dict) else None) == "Q5":
            return True
    return False


def _entity_imdb(entity: dict) -> str | None:
    for claim in (entity.get("claims") or {}).get("P345") or []:
        if not isinstance(claim, dict):
            continue
        value = (claim.get("mainsnak") or {}).get("datavalue", {}).get("value")
        if isinstance(value, str):
            imdb = _clean_person_imdb(value)
            if imdb:
                return imdb
    return None


def _snak_qid(snak) -> str | None:
    if not isinstance(snak, dict):
        return None
    value = (snak.get("datavalue") or {}).get("value")
    if isinstance(value, dict) and isinstance(value.get("id"), str):
        return value["id"]
    return None


def _qualifier_qid(claim: dict, prop: str) -> str | None:
    for snak in (claim.get("qualifiers") or {}).get(prop) or []:
        qid = _snak_qid(snak)
        if qid:
            return qid
    return None


def _qualifier_year(claim: dict) -> int | None:
    for snak in (claim.get("qualifiers") or {}).get("P585") or []:
        if not isinstance(snak, dict):
            continue
        value = (snak.get("datavalue") or {}).get("value")
        if not isinstance(value, dict):
            continue
        raw = value.get("time")
        if not isinstance(raw, str) or len(raw) < 5:
            continue
        year_text = raw[1:5] if raw[0] in "+-" else raw[:4]
        if year_text.isdigit() and int(year_text) > 0:
            return int(year_text)
    return None


def fetch_wikidata_json(url: str, opener=None, timeout: int = 60) -> dict:
    request = urllib.request.Request(
        url,
        headers={"Accept": "application/json", "User-Agent": USER_AGENT},
    )
    delay = 1.0
    last_error = "Wikidata query failed"
    for attempt in range(4):
        try:
            with _urlopen(opener, request, timeout) as response:
                status = getattr(response, "status", 200)
                if status != 200:
                    last_error = f"Wikidata status {status}"
                    if status in {429, 500, 502, 503, 504}:
                        time.sleep(delay)
                        delay *= 2
                        continue
                    raise QueryFailure(last_error)
                return json.load(response)
        except urllib.error.HTTPError as error:
            last_error = f"Wikidata status {error.code}"
            if error.code in {429, 500, 502, 503, 504} and attempt < 3:
                time.sleep(delay)
                delay *= 2
                continue
            raise QueryFailure(last_error) from None
        except (urllib.error.URLError, TimeoutError, json.JSONDecodeError) as error:
            last_error = "Wikidata query failed"
            if attempt < 3:
                time.sleep(delay)
                delay *= 2
                continue
            raise QueryFailure(last_error) from error
    raise QueryFailure(last_error)


def collect_person_links(qids: list[str], fetch, sleep=time.sleep) -> list[dict]:
    humans: list[str] = []
    batches = list(_chunks(qids, 80))
    for index, batch in enumerate(batches, start=1):
        print(f"  humans {index}/{len(batches)}", flush=True)
        for binding in fetch(human_qids_query(batch)):
            uri = binding_value(binding, "person")
            if uri:
                humans.append(qid_from_uri(uri))
        sleep(0.25)
    humans = sorted(set(humans))
    print(f"  {len(humans)} people", flush=True)
    links: list[dict] = []
    award_batches = list(_chunks(humans, 20))
    for index, batch in enumerate(award_batches, start=1):
        print(f"  prizes {index}/{len(award_batches)}", flush=True)
        links.extend(links_from_bindings(fetch(person_award_links_query(batch))))
        sleep(0.25)
    return links


def link_people_catalog(previous: dict, fetch_json=None, sleep=time.sleep) -> dict:
    """Add recipients to the catalog already on disk. Does not rebuild categories or call TMDB."""
    credits = previous.get("credits", [])
    qids = person_subject_qids(credits)
    links = collect_entity_links(qids, fetch_json or fetch_wikidata_json, sleep=sleep)
    attached = attach_person_recipients(credits, links)
    generated_at = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
    catalog = {"generatedAt": generated_at, "credits": sorted_credits(attached)}
    if not catalogs_differ(previous, catalog):
        return previous
    return catalog


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--output",
        default="TheSilverScreen/Data/Resources/AwardsCatalog.json",
    )
    parser.add_argument("--summary-out")
    parser.add_argument(
        "--link-people",
        action="store_true",
        help="Attach person recipients to the current catalog without rebuilding every category.",
    )
    args = parser.parse_args(argv)

    if args.link_people:
        return _link_people_command(args)

    previous = load_catalog(args.output)
    credits: list[dict] = []
    try:
        for family in FAMILIES:
            print(f"Querying {family['id']}", flush=True)
            credits.extend(collect_family(family, fetch_bindings))
    except QueryFailure as error:
        print(str(error), file=sys.stderr)
        return 1

    credits = collapse(credits)
    merged = apply_previous_resolutions(credits, previous)
    if needs_network_resolution(merged):
        api_key = os.environ.get("TMDB_API_KEY", "").strip()
        if not api_key:
            print("TMDB_API_KEY is required to resolve new IMDb ids", file=sys.stderr)
            return 1
        resolve = make_tmdb_resolver(api_key)
    else:
        resolve = lambda credit: None  # noqa: E731

    generated_at = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
    try:
        catalog, changed = assemble_catalog(merged, previous, resolve, generated_at)
    except ResolveFailure as error:
        print(str(error), file=sys.stderr)
        return 1

    if not changed:
        print("Catalog unchanged", flush=True)
        return 0

    summary = diff_summary(previous, catalog)
    write_catalog(args.output, catalog)
    if args.summary_out:
        with open(args.summary_out, "w", encoding="utf-8") as handle:
            handle.write(summary)
    print(summary, flush=True)
    return 0


def _categories(family: dict, fetch) -> list[dict]:
    found: dict[str, str] = {}
    for binding in fetch(category_list_query(family["qid"])):
        uri = binding_value(binding, "category")
        label = binding_value(binding, "categoryLabel")
        if not uri or not label or _looks_like_qid(label):
            continue
        found[qid_from_uri(uri)] = label
    return [{"id": qid, "label": label} for qid, label in sorted(found.items(), key=lambda item: item[1].casefold())]


def _fetch_bindings_once(query: str, opener, timeout: int) -> list[dict]:
    url = WIKIDATA_URL + "?" + urllib.parse.urlencode({"query": query})
    request = urllib.request.Request(
        url,
        headers={"Accept": "application/sparql-results+json", "User-Agent": USER_AGENT},
    )
    try:
        with _urlopen(opener, request, timeout) as response:
            status = getattr(response, "status", 200)
            payload = json.load(response)
    except urllib.error.HTTPError as error:
        raise QueryFailure(f"Wikidata status {error.code}") from None
    except (urllib.error.URLError, TimeoutError, json.JSONDecodeError) as error:
        raise QueryFailure("Wikidata query failed") from error
    if status != 200:
        raise QueryFailure(f"Wikidata status {status}")
    try:
        return payload["results"]["bindings"]
    except (KeyError, TypeError) as error:
        raise QueryFailure("Wikidata payload was missing results") from error


def _retryable(message: str) -> bool:
    if message == "Wikidata query failed":
        return True
    for code in ("429", "500", "502", "503", "504"):
        if message.endswith(code):
            return True
    return False


def _pick_work(payload: dict, family: str | None) -> dict | None:
    movies = payload.get("movie_results") or []
    shows = payload.get("tv_results") or []
    seasons = payload.get("tv_season_results") or []
    episodes = payload.get("tv_episode_results") or []
    prefer_movie = family in {None, "academy", "bafta"}
    if prefer_movie and movies:
        return {"kind": "movie", "movieID": movies[0]["id"]}
    episode = _first_episode(episodes)
    if episode:
        return episode
    season = _first_season(seasons)
    if season:
        return season
    if shows:
        return {"kind": "series", "seriesID": shows[0]["id"]}
    if movies:
        return {"kind": "movie", "movieID": movies[0]["id"]}
    return None


def _first_episode(episodes: list[dict]) -> dict | None:
    for episode in episodes:
        series_id = episode.get("show_id")
        season = episode.get("season_number")
        number = episode.get("episode_number")
        if series_id is None or season is None or number is None:
            continue
        return {
            "kind": "episode",
            "seriesID": series_id,
            "seasonNumber": season,
            "episodeNumber": number,
        }
    return None


def _first_season(seasons: list[dict]) -> dict | None:
    for season in seasons:
        series_id = season.get("show_id")
        number = season.get("season_number")
        if series_id is None or number is None:
            continue
        return {"kind": "season", "seriesID": series_id, "seasonNumber": number}
    return None


def _series_name(series_id: int, api_key: str, opener) -> str:
    try:
        payload = _tmdb_json(f"{TMDB_TV}{series_id}", api_key, opener)
    except ResolveFailure:
        return ""
    name = payload.get("name")
    return name if isinstance(name, str) else ""


def tmdb_find_path(imdb: str) -> str:
    """`/find` returns 404 unless the id is tagged as an IMDb id. A 404 is stored as no work."""
    return f"{TMDB_FIND}{urllib.parse.quote(imdb, safe='')}?external_source=imdb_id"


def _tmdb_json(url: str, api_key: str, opener) -> dict:
    query = urllib.parse.urlencode({"api_key": api_key})
    separator = "&" if "?" in url else "?"
    request = urllib.request.Request(
        url + separator + query,
        headers={"Accept": "application/json", "User-Agent": USER_AGENT},
    )
    delay = 1.0
    last_status = 0
    for attempt in range(4):
        try:
            with _urlopen(opener, request, 30) as response:
                status = getattr(response, "status", 200)
                if status == 404:
                    return {}
                if status in {401, 403}:
                    raise ResolveFailure(f"TMDB status {status}")
                if status >= 500 or status == 429:
                    last_status = status
                    time.sleep(delay)
                    delay *= 2
                    continue
                return json.load(response)
        except urllib.error.HTTPError as error:
            last_status = error.code
            if error.code == 404:
                return {}
            if error.code in {401, 403}:
                raise ResolveFailure(f"TMDB status {error.code}") from None
            if error.code == 429 or error.code >= 500:
                time.sleep(delay)
                delay *= 2
                continue
            raise ResolveFailure(f"TMDB status {error.code}") from None
        except urllib.error.URLError:
            time.sleep(delay)
            delay *= 2
    raise ResolveFailure(f"TMDB status {last_status or 'unavailable'}")


def _urlopen(opener, request, timeout):
    if opener is None:
        return urllib.request.urlopen(request, timeout=timeout)
    return opener(request, timeout)


def _sample(label: str, credits: list[dict]) -> list[str]:
    if not credits:
        return []
    lines = [f"{label}:"]
    for credit in credits[:20]:
        outcome = "win" if credit.get("won") else "nomination"
        lines.append(
            f"- {credit.get('year')} {credit.get('category')} ({outcome}): {credit.get('title')}"
        )
    if len(credits) > 20:
        lines.append(f"- … {len(credits) - 20} more")
    lines.append("")
    return lines


def _link_people_command(args) -> int:
    previous = load_catalog(args.output)
    try:
        catalog = link_people_catalog(previous, fetch_wikidata_json)
    except QueryFailure as error:
        print(str(error), file=sys.stderr)
        return 1
    if not catalogs_differ(previous, catalog):
        print("Catalog unchanged", flush=True)
        return 0
    summary = diff_summary(previous, catalog)
    write_catalog(args.output, catalog)
    if args.summary_out:
        with open(args.summary_out, "w", encoding="utf-8") as handle:
            handle.write(summary)
    print(summary, flush=True)
    return 0


def _clean_imdb(raw: str | None) -> str | None:
    if not raw:
        return None
    candidate = raw.strip()
    if IMDB_ID.fullmatch(candidate):
        return candidate
    return None


def _clean_person_imdb(raw: str | None) -> str | None:
    if not raw:
        return None
    candidate = raw.strip()
    if PERSON_IMDB.fullmatch(candidate):
        return candidate
    return None


def _looks_like_qid(value: str) -> bool:
    return len(value) > 1 and value[0] == "Q" and value[1:].isdigit()


if __name__ == "__main__":
    sys.exit(main())

