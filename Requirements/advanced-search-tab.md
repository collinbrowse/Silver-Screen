# Epic: Advanced Search Tab

Unified search across Movies, TV, and People. An empty field opens the award and genre shelves. Typing shows a Spotify-style preview; View all / Enter expands into a ranked list with niche and Genre filters. People float first only when result scoring says so, and that order stays frozen for the query.

| # | Story | Done |
| --- | --- | --- |
| 1 | Empty, unfocused Search shows award shelves and Genre cards (not popular lists). | [x] |
| 2 | Typeahead fetches movies, TV, and people together and shows the top five of each in separate sections. | [x] |
| 3 | When the strongest matched person outranks the strongest matched title, People stay first for that query (order does not flip after first paint). Otherwise Movies → TV → People. | [x] |
| 4 | View all / Enter opens a ranked list (match then popularity); people-first queries list people above titles. | [x] |
| 5 | View all exposes Movies / TV / People niche pills and a Genre filter over the cached hits (client-side). | [x] |
| 6 | Editing the query returns to the typeahead preview and clears niche / Genre filters. | [x] |
| 7 | View-all lists are paginated per media type still in play. | [x] |
| 8 | TV UI: cell shows main image, TV name, genres, and first air date. | [x] |
| 9 | People UI: cell shows profile image, name, and known-for department. Clicking a cell takes you to that person. | [x] |
