# Stories

These files are the stories the app was built from. Every story shipped. The [README](../README.md) describes the app as it works today.

A few names changed while the stories were being built:

- Favorites became Library: Watched, Watchlist, and lists you create. Movies & TV and People are separate libraries.
- Now Playing and Upcoming are windows on Browse, not their own tabs.
- Search covers movies, TV, and people. An empty field opens the Oscar, BAFTA, and Emmy shelves.

The tables keep the original scope. Where the shipping screen diverged, the epic says so at the top.

## Epics

| Epic | What shipped |
| --- | --- |
| [Top Movies](top-movies.md) | The list that became Browse: posters, sort, and a visible failure. |
| [Favorites & Bookmarking](favorites.md) | Saving titles and people. Shipped as Library, not a single Favorites tab. |
| [Movie Detail View](movie-detail-view.md) | Movie page: facts, images, cast, crew, similar titles, collections, reviews. |
| [Tab Bar](tab-bar.md) | Browse, Search, and Library. Media, window, and sort live on Browse. |
| [Now Playing](now-playing-tab.md) | The Now Playing window on Browse. |
| [Upcoming](upcoming-tab.md) | The Upcoming window on Browse. |
| [Search](search-tab.md) | Type-ahead search that keeps its results. |
| [People](people-view.md) | Person page: biography, images, credits, and prizes given to that person. |
| [Collections](collections-view.md) | A movie collection and the films in it. |
| [TV Series](tv-series-view.md) | Series page: seasons, cast, crew, recommendations, reviews. |
| [TV Season](tv-series-season-view.md) | Season page: images, cast, crew, episodes. |
| [TV Episode](tv-episode.md) | Episode page: images, cast, guest stars, crew. |
| [TV Watch Progress](tv-watch-progress.md) | Episode ledger, In Progress list, Watched auto-moves, cold-launch season refresh. |
| [Search scopes](advanced-search-tab.md) | Movies, TV, and People on Search. |

## Where the data comes from

TMDB exposes overlapping data through different endpoints — for example, [Credits](https://developer.themoviedb.org/reference/credit-details) and [Person Details](https://developer.themoviedb.org/reference/person-details). Each screen uses the endpoint that matches what it shows.
