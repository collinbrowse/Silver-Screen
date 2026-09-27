# The Silver Screen — iOS Engineering Assessment

## Overview
The Silver Screen is a small iOS app that uses [The Movie Database (TMDB)](https://developer.themoviedb.org/reference/getting-started) API to display movies. When we're not busy programming, the URBN Mobile Team loves discussing our favorite films and making recommendations — this app is where we track them.

This repo is a coding assessment. It ships with a working UIKit movie list, and a large backlog of new SwiftUI features to build on top of it.

## What we're looking for
We care about **how** you work as much as what you ship: your process, the tooling you reach for, and how you architect and organize your project to move faster and more accurately.

The backlog in [`Requirements/`](Requirements/README.md) is **intentionally larger than anyone could finish** in the time you have. That is by design.

- You are **not** expected to complete everything — please don't try.
- Pick whatever you want, in any order, and go deep or wide as you see fit.
- Check off the stories you complete in the requirement tables as you go.

We are assessing your approach, judgment, and craft — not raw completion count.

## Getting Started
- Make sure you have a Mac running **Xcode 26** (or higher).
- Create a new **private** repo from this project.
- Add the GitHub usernames provided by the recruiting team as collaborators.
- Your **first commit should be the project exactly as-is** (no changes), so we can see your work as a diff.
- Open the project in Xcode. The TMDB API key is in [`TheSilverScreen/Networking/Globals.swift`](TheSilverScreen/Networking/Globals.swift).
- Commit as often as you like.

TMDB API reference: https://developer.themoviedb.org/reference/getting-started

## Ground Rules
- **AI is encouraged.** Use whatever tooling and IDE you prefer — Cursor, Claude Code, Xcode with AI, etc. We want to see how you work with AI, not without it.
- **All new work is SwiftUI.**
- **No 3rd-party dependencies.** You may otherwise modify the existing source however you see fit.
- **Add unit tests** for the work you complete.
- **You're encouraged to build out your own AI infrastructure/harness.**
- AI infrastructure/harness should be scoped for the repo, committed in git and accessible in GitHub.
- **PRs are encouraged** if they help your workflow.
- Feel free to leave comments/notes in the code about your implementation and any suggestions you have.

## How the Work Is Organized
The backlog lives in [`Requirements/`](Requirements/README.md).

- Each **epic** is its own file with a table of stories.
- Each **story** is a single row in that table.
- The `Done` column is a checkbox — tick it as you complete each story.

Start at the [Requirements index](Requirements/README.md) for the full list and an at-a-glance progress view.

## Codebase Tour
A quick map so you can step in fast:

- [`TheSilverScreen/Repositories/MovieRepository.swift`](TheSilverScreen/Repositories/MovieRepository.swift) — movie networking and mapping.
- [`TheSilverScreen/App/RootTabView.swift`](TheSilverScreen/App/RootTabView.swift) — Browse, Search, and Library.

## Submission
- Do your work in your own **private** repo (see Getting Started), with the recruiting-provided GitHub usernames added as collaborators.
- We review the **`main`** branch, so make sure your completed work lands there.
- Please include a short `NOTES.md` describing your approach: your process, the tooling you used, and any AI infrastructure you built along the way.
- Let your recruiter know when you're ready for review.
