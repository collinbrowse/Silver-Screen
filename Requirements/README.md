# Requirements

This is the backlog for the The Silver Screen assessment. It is **intentionally larger than anyone could finish** — beyond the required work below, pick whatever you want, in any order, and go as deep or wide as you like. You are not expected to complete everything, so please don't try.

Each file below is an **epic** containing a table of **stories**. Tick the `Done` box for each story you complete.

All new work is SwiftUI. See the [main README](../README.md) for ground rules, tooling guidance, and submission details.

## Required Work (in order)

Only the following is required. Everything else in the backlog is optional.

1. Complete the [Top Movies](top-movies.md) epic first — it fixes bugs and gaps in the existing list screen and gives you the foundation (networking, models, navigation) the rest of the backlog builds on.
2. Then complete stories **1 and 2** of [Favorites & Bookmarking](favorites.md) (add bookmarking UI, and a Favorites tab).

After that, pick anything you like.

## Epics


| Epic                                              | Description                                                                                                                                                 |
| ------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------- |
| [Top Movies](top-movies.md)                       | **Required — do first.** Bug fixes and improvements to the existing Top Ranked Movies list: cell layout, scrolling performance, error handling and sorting. |
| [Favorites & Bookmarking](favorites.md)           | **Stories 1 & 2 required** (after Top Movies). Bookmark movies/TV/people and browse them in a Favorites tab with filtering and search.                      |
| [Movie Detail View](movie-detail-view.md)         | Full detail screen for a movie: metadata, image carousel, cast, crew, similar movies, collections, and paginated reviews.                                   |
| [Tab Bar](tab-bar.md)                             | Browse, Search, and Library. Browse holds media, window, and sort on one screen.                                                                            |
| [Now Playing Tab](now-playing-tab.md)             | The Now Playing window on Browse.                                                                                                                           |
| [Upcoming Tab](upcoming-tab.md)                   | The Upcoming window on Browse.                                                                                                                              |
| [Search Tab](search-tab.md)                       | Type-ahead movie search with persistent results.                                                                                                            |
| [People View](people-view.md)                     | Person detail screen with bio, images, cast/crew credits, and prizes given to that person.                                                                   |
| [Collections View](collections-view.md)           | Movie collection screen listing its parts.                                                                                                                  |
| [TV Series View](tv-series-view.md)               | TV series detail screen with seasons, cast, crew, recommendations, and reviews.                                                                             |
| [TV Series Season View](tv-series-season-view.md) | Season detail screen with images, cast, crew, and episodes.                                                                                                 |
| [TV Episode](tv-episode.md)                       | Episode detail screen with images, cast, guest stars, and crew.                                                                                             |
| [Advanced Search Tab](advanced-search-tab.md)     | Segmented search across Movies, TV, and People.                                                                                                             |




## Progress at a Glance

Update the `Completed / Total` column as you go.


| Epic                                              | Completed / Total |
| ------------------------------------------------- | ----------------- |
| [Top Movies](top-movies.md)                       | 4 / 4             |
| [Favorites & Bookmarking](favorites.md)           | 9 / 9             |
| [Movie Detail View](movie-detail-view.md)         | 7 / 7             |
| [Tab Bar](tab-bar.md)                             | 2 / 2             |
| [Now Playing Tab](now-playing-tab.md)             | 2 / 2             |
| [Upcoming Tab](upcoming-tab.md)                   | 2 / 2             |
| [Search Tab](search-tab.md)                       | 4 / 4             |
| [People View](people-view.md)                     | 5 / 5             |
| [Collections View](collections-view.md)           | 3 / 3             |
| [TV Series View](tv-series-view.md)               | 7 / 7             |
| [TV Series Season View](tv-series-season-view.md) | 5 / 5             |
| [TV Episode](tv-episode.md)                       | 5 / 5             |
| [Advanced Search Tab](advanced-search-tab.md)     | 6 / 6             |




## A Note on Endpoints

TMDB exposes overlapping data through different endpoints — for example, [Credits](https://developer.themoviedb.org/reference/credit-details) vs [Person Details](https://developer.themoviedb.org/reference/person-details). Part of the exercise is investigating the API and deciding which endpoints best serve each screen. This is something to explore, not a blocker.