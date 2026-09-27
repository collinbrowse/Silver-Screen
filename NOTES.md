# NOTES.md

## Hello 
Hey, Nuuly (Sean, Eric, Sean, Allison, Kevin)

Thanks for taking the time to look over my project. It's always fun getting to start something
new and see where it goes. I've tried to give an informative but short description on each
part of the assignment and I'm looking forward to reviewing it with you all in person. 

Thanks! 

## Approach

The goal was to set up a repeatable AI workflow with deterministic quality and then push tasks 
through that process and evaluate the code and the results. If the agent missed any steps 
or the results were not of sufficient quality I would stop, fix the issue/add more to the harness 
and ensure it didn't happen again. As I built trust in the process I started providing larger tasks. 
I have a general design principle that established design styles & navigation
are best for UX unless a brand new design is specifically warranted and validated. 
For a quick take home interview project, this holds true. I used ai design tools (google stitch) 
and my own intuition modeling the app after the AppleTV app which has a clean, intuitive and pleasant UI to use. 

- **Foundation (the harness + architecture):** before and alongside feature
  work, I built the in-repo AI harness (rules, skills, hooks, CI gates —
  described below) and the layered architecture the app sits on. This is a
  large part of the effort and shaped how every story was implemented.
- **Features:** after the required stories (in order), I let the same judgment the
  harness enforces drive scope: go deep where it makes the app feel finished —
  detail and people screens, and a library of lists that stays in sync across
  every screen — rather than chase completion count across the backlog.

## Process

- One story (or one logical foundation slice) per commit, kept small and
  reviewable; shared foundation landed ahead of the stories that need it.
- Work shipped through PRs whose bodies follow
  `.github/pull_request_template.md` in full (Summary, Decision Tree, Test Plan,
  Stories completed, AI Harness notes).
- A story is only marked `Done` in `Requirements/` after both unit tests and a
  visual check against the comps.

### Toolchain

- Swift 6 language mode with strict concurrency, Observation, iOS 26 target.
- Bumped `project.pbxproj` off Swift 5 / iOS 15.2 during the Top Movies epic,
  alongside the async/await conversion Swift 6 mode requires.
- No 3rd-party dependencies.
- Setup: copy `Secrets.example.xcconfig` → `Secrets.xcconfig` and set
  `TMDB_API_KEY` to the provided key. It's gitignored; a missing key fails fast
  at launch by design.

### Architecture Decisions I Made

Strict layering, one direction only:

`View (SwiftUI) → ViewModel → Repository → Service (TMDB / persistence)`

- **MVVM**: one `@Observable @MainActor` view model per screen. View models
  import `Foundation` only.
- **Single explicit state enum** (`LoadState` + nested `LoadActivity`) instead
  of parallel `isLoading` / `error` / `data` flags, so "loading" and "has
  content" can never disagree. Refresh, paging, and refresh-failure keep the
  current content on screen; only a cold failure is full-screen.
- **Repositories are concrete types** that own their API service, mapping,
  caching, and persistence, and return domain models or throw `AppError`.
- **DI, no singletons**: dependencies are built once in the composition root
  (`AppDependencies`) and injected down — init injection for view models,
  `Environment` for views.
- **Navigation**: `AppRouter` owns the selected tab and one `NavigationRouter`
  (with its own `path`) per tab. Views push routes, never construct
  destinations.
- **Minimal protocols**: only where a real boundary needs substitution —
  `HTTPClient` (network), the Library lists store (disk), and
  `AppLogging`. No `MovieRepositoryProtocol`, no protocol-per-type.

## AI Infrastructure / Harness

The harness lives in the repo under `.cursor/` and is part of the workflow:

- **Rules** (`.cursor/rules/*.mdc`): an always-on architecture rule plus scoped
  rules for concurrency, SwiftUI, the legacy UIKit screen, the data layer,
  image loading, secrets, errors/logging, accessibility, documentation,
  testing, commits, and pull requests. `AGENTS.md` is the source of truth for
  the assessment constraints.

- **Skills** (`.cursor/skills/`): `implement-story` (smallest reviewable slice
  with tests + screenshot + Done only after verification) and `visual-qa`
  (screenshot the booted simulator and compare against the comps).
- **Hooks** (`.cursor/hooks.json`):
  - `beforeShellExecution` → `block-third-party-deps.sh` (fail-closed guard
    against adding dependencies).
  - `stop` → `run-unit-tests.sh` (runs the unit tests when the agent finishes).
- **CI gates** (`scripts/`):
  - `validate-tests.py` — bans empty tests and fails a PR that ticks a story
    `Done` without touching `TheSilverScreenTests/`.
  - `validate-pr-body.py` — enforces the PR template sections.
  - `validate-rules.py` — validates the rule files.
- **MCP**: 
  - Use MobAI as an MCP connection to let the agent control the simulator to validate its work.


## Testing

Unit tests cover the completed work (repositories, view models, library
lists) under `TheSilverScreenTests/`. Tests substitute only real external boundaries
(HTTP, disk) — repositories and view models are not hidden behind a protocol and faked. 


## What I'd do next/differently

- Search:
  - Right now the app is more of a "Learn about top movies" but a search functionality 
  would change it to "An app where I can keep track of my favorite movies "
- Then continue the backlog in this order:
  - TV Show page
  - TV Series/Season Pages
  - Movie Collections Page
  - Advanced Search
  - Now Playing / Upcoming
- Snapshot tests for the design-system components in
  `Features/Shared/DesignSystem/`.
- Add a network reachability service to monitor for no-service scenarios, so the
  UI can react to connectivity changes proactively rather than only on a failed
  request.
- Switch to a v4 bearer token for TMDB for a more secure process. 
  I didn't want to sign up for another TMDB account just to mint a token for this project. 
  I did move the key out of source (gitignored `xcconfig` → `Info.plist`, read at launch) and keep it out of logs.
