# Epic: People View

The detail screen for a person, opened from a person row elsewhere in the app.

| # | Story | Done |
| --- | --- | --- |
| 1 | When you click on a person from the Movie Detail View, you land on a People page. This page shows: their name, profile photo, birthday, death day (if deceased, hidden if not), place of birth, IMDB icon, and biography. | [x] |
| 2 | Underneath the above, a carousel of images of the person. UI should just show an image. Clicking on an image makes it full screen (and can be dismissed). | [x] |
| 3 | Underneath that, a carousel of the first 5 movies they are in as cast. If they have no cast roles, this is hidden. UI shows: poster image and movie name. | [x] |
| 4 | Underneath that, a carousel of the first 5 movies they are in as crew. If they have no crew roles, this is hidden. UI shows: poster image and movie name. For both carousels above, if they have more than 10 credits in either, show a "View All" button. Clicking it moves you to a Movie List View showing all movies in that section; each cell contains: movie title, poster image, genres, and release date. | [x] |
| 5 | Under the biography, list awards given to this person, such as Best Supporting Actor. Each row shows the trophy, the award name, and the movie or episode it was for. Awards given to the title, such as Best Picture, are not listed. Hide the section when there is nothing to show. | [x] |
