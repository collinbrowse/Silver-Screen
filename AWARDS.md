# Awards shelves and catalog

Search’s empty field is a shelf of award lists. Movie, series, season, and episode detail screens show those prizes in the same card a person screen uses. The lists come from a JSON catalog in the app. Wikidata is compiled during development and on a Monday job. The phone never queries Wikidata.

TMDB has no awards endpoint and no Oscars filter. Movie details do not include wins or nominations. The Academy’s database is the record of truth and has no public API, so the catalog is a Wikidata snapshot joined to TMDB by IMDb id.

## What a person sees

1. Open Search with the field empty and unfocused. The Movies / TV / People control stays hidden. Three cards are on screen: Oscar Winners, BAFTAs, Emmys. They come from `AwardShelf.home`, which is one card per `AwardFamily`. Each card is that ceremony’s lockup, with no title set beside it. BAFTA and the Emmys swap to a dark picture in dark mode. The Oscars mark is clear, and the card behind it is white or black.
2. A card opens that prize body’s categories (Best Picture, Outstanding Drama Series, and so on).
3. A category opens a title list with a Winners / Nominees control. Newest ceremony year is first. Each page is 20 credits.
4. A row matches a Browse row, with the ceremony year directly under the title, then genres, then a personal rating when one exists, then the list button. The release date is omitted. Tapping a row uses the existing movie, series, season, or episode route.
5. On a movie, series, season, or episode screen, prizes for that title sit in the same card as a person screen, after the facts. Each row shows the trophy, the category (`Best Picture`, or `Best Picture nominee`), and a second line. When the prize names people, that line is their names and the ceremony year (`Cillian Murphy · 2024`). A title prize such as Best Picture shows only the year. A win hides the nomination for that same category and year. Other nominations stay. The section is hidden when nothing matches. These rows are not buttons. VoiceOver names the prize body, because the trophy is decorative.
6. On a person screen, prizes given to that person sit under the biography, in that same card. Each row shows the trophy, the category (`Best Supporting Actor`, or `Best Supporting Actor nominee`), and the title plus ceremony year (`A Real Pain · 2025`). Best Picture and other title prizes are not listed. The section is hidden when the person’s IMDb id matches nothing. A win hides the nomination for that same title, category, and year. Tapping a row opens the title when the catalog has a TMDB id.

A category with fewer than eight resolved credits stays off the menu. Eight is `AwardsRepository.minimumListedCredits`. A short stub would look like the whole history.

Credits that cannot open a detail screen are skipped. That means the catalog row has no `work`, or `work` is missing the id that route needs.

## Where the data lives

The file is [`TheSilverScreen/Data/Resources/AwardsCatalog.json`](TheSilverScreen/Data/Resources/AwardsCatalog.json). It is listed in the Xcode project. Leave it pretty-printed and sorted. Do not hand-edit credits. A failed rebuild must not replace this file.

```json
{
  "generatedAt": "2026-09-27T20:14:01Z",
  "credits": [
    {
      "key": "academy|Q102427|2024|won|Q108669",
      "family": "academy",
      "category": "Best Picture",
      "categoryID": "Q102427",
      "won": true,
      "year": 2024,
      "title": "Oppenheimer",
      "imdbID": "tt15398776",
      "wikidataID": "Q108669",
      "work": { "kind": "movie", "movieID": 872585 }
    }
  ]
}
```

`generatedAt` is ISO-8601. `family` is `academy`, `bafta`, or `emmy`. `key` is `family|categoryID|year|won-or-nominated|wikidataID` and stays stable across rebuilds so a resolved TMDB id can be copied forward. `work.kind` is `movie`, `series`, `season`, or `episode`, with the ids those screens already navigate with. Season and episode works also store `seriesName` when TMDB returned one.

Credits with no IMDb id stay in the file and stay out of the lists.

A prize given to a person also stores `recipients`. Title prizes such as Best Picture omit the field. Each recipient has `name`, `wikidataID`, and `imdbID` when Wikidata has an `nm` id. Person screens match that `nm` id. Two people nominated for the same title stay on one credit.

```json
"recipients": [
  { "imdbID": "nm0000342", "name": "Kieran Culkin", "wikidataID": "Q313204" }
]
```

## How the app loads it

`AwardsRepository` is a concrete actor, built in `AppDependencies` and passed down. `SceneDelegate` calls `prepare()` at launch.

1. Read the bundle and the cache in Application Support (`AwardsCatalog.json` next to `AwardsCatalog.stamp.json`).
2. Keep whichever file has the newer `generatedAt`. A missing or unreadable side leaves the other. Both missing means an empty catalog.
3. At most once every seven days, download the copy on `main`:

   `https://raw.githubusercontent.com/collinbrowse/The-Silver-Screen/main/TheSilverScreen/Data/Resources/AwardsCatalog.json`

4. Replace the in-memory catalog and the cache only when the download decodes and its `generatedAt` is newer. A failed download leaves the current catalog on screen.

The stamp is written when the attempt starts. A failure still waits seven days before the next try. Lookup after `prepare()` is in memory.

## How a rebuild works

[`scripts/build_awards_catalog.py`](scripts/build_awards_catalog.py) queries Wikidata, then asks TMDB `/find` for each new IMDb id. [`.github/workflows/awards-catalog.yml`](.github/workflows/awards-catalog.yml) runs that script every Monday at 10:00 UTC (4:00 AM Denver during daylight time, 3:00 AM in winter) and on `workflow_dispatch`.

The job opens a pull request only when the credit list changed. A quiet week pushes nothing. Nothing auto-merges. Merging that pull request is the approval, and it is what later app launches can download. `GITHUB_TOKEN` does not start the normal CI workflow on that pull request, so the review is the check. The pull request body comes from `.github/pull_request_template.md` via `render_pr_body`, with the added and removed credit sample filled in.

Already-resolved ids stay in the file. A later Monday calls `/find` only for credits whose key is new or whose IMDb id changed.

One category at a time. A family-wide SPARQL query times out, and a failed query must exit before `AwardsCatalog.json` is replaced. Wins and nominations are separate queries. Acting awards are read from the person, with the film or episode in Wikidata qualifier “for work” (`P1686`), and also from the work itself. When the statement is on a person, that person is stored in `recipients` on the title credit.

To attach recipients onto a catalog that was built before that field existed, without re-querying every category:

```bash
python3 scripts/build_awards_catalog.py --link-people \
  --output TheSilverScreen/Data/Resources/AwardsCatalog.json
```

That reads Wikidata entity claims for ids that never resolved to a title, and keeps a human’s award only when the statement names a work (`P1686`). It does not call TMDB. A failed request leaves the file in place.

| Family | Wikidata id | `/find` preference |
| --- | --- | --- |
| Academy Awards (`academy`) | Q19020 | movie, then TV |
| BAFTA Film (`bafta`) | Q732997 | movie, then TV |
| Primetime Emmys (`emmy`) | Q1044427 | episode, then season, then series, then movie |

`/find/{imdb}` returns 404 unless the query includes `external_source=imdb_id`. The builder treats 404 as “no work” and would otherwise store a blank id. `tmdb_find_path` sets that parameter. Keep it.

The script needs `TMDB_API_KEY` in the environment. Locally that value is in `Secrets.xcconfig`, which is gitignored. The Monday job reads the `TMDB_API_KEY` repository secret. Do not print the key, and do not log a URL that still has `api_key` in the query.

Rebuild locally from the repo root:

```bash
python3 scripts/test_build_awards_catalog.py
export TMDB_API_KEY="$(python3 -c 'import re; print(re.search(r"^TMDB_API_KEY\s*=\s*(\S+)", open("Secrets.xcconfig").read(), re.M).group(1))')"
python3 scripts/build_awards_catalog.py \
  --output TheSilverScreen/Data/Resources/AwardsCatalog.json \
  --summary-out /tmp/awards-summary.md
```

The builder tests use [`scripts/fixtures/wikidata_award_bindings.json`](scripts/fixtures/wikidata_award_bindings.json). They do not call SPARQL or TMDB. CI runs them from [`.github/workflows/ci.yml`](.github/workflows/ci.yml).

## Adding a prize body

A new category inside Academy, BAFTA Film, or the Primetime Emmys needs no app change. The next catalog rebuild adds it, and the family screen lists it once eight credits resolve.

A new prize body needs both of these, together:

- A case on `AwardFamily` in [`TheSilverScreen/Data/Domain/AwardsCatalog.swift`](TheSilverScreen/Data/Domain/AwardsCatalog.swift), with `title` and `subtitle`. Search home cards follow `AwardFamily.allCases`.
- An entry in `FAMILIES` in [`scripts/build_awards_catalog.py`](scripts/build_awards_catalog.py): the `academy` / `bafta` / `emmy` style id, the Wikidata id of the prize body, and whether `/find` should prefer a movie or a TV result.

Category names in the file drop a leading “Academy Award for ”, “BAFTA Award for ”, “Primetime Emmy Award for ”, and the other prefixes in `CATEGORY_PREFIXES`.

## What to run

- `python3 scripts/test_build_awards_catalog.py`
- `xcodebuild test -scheme TheSilverScreen -only-testing:TheSilverScreenTests/AwardsRepositoryTests -only-testing:TheSilverScreenTests/AwardTitlesViewModelTests -only-testing:TheSilverScreenTests/AwardDetailLabelTests -only-testing:TheSilverScreenTests/SearchViewModelTests`

On device, use the iPhone 17e. Empty Search shows the three cards. A family lists categories. A category lists winners with the ceremony year under the title. A known title, such as Oppenheimer, shows the awards card after the facts. A person with a matching IMDb id shows the same card under the biography.

## Files

| Piece | Path |
| --- | --- |
| Catalog JSON | `TheSilverScreen/Data/Resources/AwardsCatalog.json` |
| Model, shelves, row copy | `TheSilverScreen/Data/Domain/AwardsCatalog.swift` |
| Load, filter, weekly download | `TheSilverScreen/Data/Repositories/AwardsRepository.swift` |
| Search home | `TheSilverScreen/Screens/Search/SearchView.swift`, `SearchViewModel.swift` |
| Category list | `TheSilverScreen/Screens/Search/AwardFamilyView.swift` |
| Title list | `TheSilverScreen/Screens/Search/AwardTitlesView.swift`, `AwardTitlesViewModel.swift` |
| Detail rows | `TheSilverScreen/Screens/Shared/AwardRowsSection.swift` |
| Routes | `TheSilverScreen/Navigation/Route.swift` (`.awardFamily`, `.awardTitles`) |
| Builder and tests | `scripts/build_awards_catalog.py`, `scripts/test_build_awards_catalog.py` |
| Monday job | `.github/workflows/awards-catalog.yml` |
