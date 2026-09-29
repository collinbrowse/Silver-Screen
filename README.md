# Silver Screen

It's Letterboxd, but with TV.

Keep track of movies and series on your iPhone. Browse what's popular, in theaters, and coming up. Search titles and people. Save lists, score what you've seen, and look up Oscar, BAFTA, and Emmy history on the title or the person it was for.

No account. Your lists, scores, and notes stay on the device.

<p>
  <img src="docs/screenshots/browse-movies.png" width="240" alt="Browse with Movies selected. A title shows a personal rating and is already on a list.">
  &nbsp;
  <img src="docs/screenshots/movie-detail.png" width="240" alt="A movie page with a backdrop, trailers, genres, the TMDB rating, your rating, and the storyline.">
  &nbsp;
  <img src="docs/screenshots/tv-series.png" width="240" alt="A series page for Severance, with air dates, a trailer, genres, and the storyline.">
</p>

## Features

- **Browse** for movies, series, or both. Filter to now playing or upcoming, and sort by popularity, rating, name, or release date. Sort applies to the full catalog. Now playing and upcoming already have an order.
- **Search** for movies, TV, and people. An empty field opens Oscar, BAFTA, and Emmy shelves. Open a ceremony, pick a category, and switch between winners and nominees. A close spelling still finds the name: Christopher Waltz finds Christoph Waltz. The query stays after you open a result.
- **Rating and notes** Add a rating or a note for a movie, series, season, or episode. Scores run from 0.5 to 10 in half points. Notes are your personal review. 
- **Awards** show on the title and on the person, with the category, the year, and who it was for. A person's prize opens that film or episode.
- **Library** helps you keep track of everything your watching. Start with Watched and Watchlist. Add your own lists to make your own ranked lists or simple your favorites from this year. A series opens its seasons, a season its episodes, and a collection the films in it.

### Browse

<p>
  <img src="docs/screenshots/browse-filters.png" width="240" alt="The Browse filters menu, with window and sort options.">
  &nbsp;
  <img src="docs/screenshots/browse-movies.png" width="240" alt="The Movies list on Browse.">
</p>

### Search

<p>
  <img src="docs/screenshots/search-awards.png" width="240" alt="Search with an empty field, showing Oscar, BAFTA, and Emmy shelves.">
  &nbsp;
  <img src="docs/screenshots/search-results.png" width="240" alt="A TV search for Severance, with Movies, TV, and People scopes.">
  &nbsp;
  <img src="docs/screenshots/award-winners.png" width="240" alt="Best Picture winners, with a Winners and Nominees control.">
</p>

### A title

<p>
  <img src="docs/screenshots/movie-detail.png" width="240" alt="Movie detail with trailers, ratings, and a place to add a note.">
  &nbsp;
  <img src="docs/screenshots/movie-awards.png" width="240" alt="Awards listed on a movie page.">
</p>

### People

<p>
  <img src="docs/screenshots/person-detail.png" width="240" alt="A person page with a portrait, biography, and an IMDb link.">
  &nbsp;
  <img src="docs/screenshots/person-awards.png" width="240" alt="Awards given to a person, each opening the title it was for.">
</p>

### Library

<p>
  <img src="docs/screenshots/library.png" width="240" alt="The library, with Watched and Watchlist under Movies and TV.">
  &nbsp;
  <img src="docs/screenshots/library-watched.png" width="240" alt="The Watched list, filtered across all titles, movies, and TV.">
</p>

## Get it running

Silver Screen is a native iPhone app. To run it from this repo:

1. Install [Xcode 26](https://developer.apple.com/xcode/) or newer.
2. Create a free API key at [The Movie Database](https://www.themoviedb.org/settings/api).
3. Copy `Secrets.example.xcconfig` to `Secrets.xcconfig` and set `TMDB_API_KEY`.
4. Open `TheSilverScreen.xcodeproj` and run the **TheSilverScreen** scheme.

## Data sources

Movie and series information comes from [The Movie Database](https://www.themoviedb.org/). This product uses the TMDB API but is not endorsed or certified by TMDB.

Person pages link out to IMDb. Award credits are compiled from Wikidata and matched to TMDB.
