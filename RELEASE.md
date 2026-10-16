# Releases

Dev, TestFlight, and the App Store share one version file and one git history.
TestFlight is a tagged commit you archive once. The App Store is that same
commit, tagged again and submitted in App Store Connect.

## Channels

| Channel | How you install | Bundle ID | Display name | Git |
| --- | --- | --- | --- | --- |
| Dev | Xcode Run (Debug) | `com.collinbrowse.thesilverscreen.dev` | Silver Dev | any branch |
| TestFlight | archive of a `testflight/` tag | `com.collinbrowse.thesilverscreen` | Silver Screen | tag `testflight/0.1.1+2` |
| App Store | the TestFlight build, submitted | same as TestFlight | Silver Screen | tag `v0.1.1` on that same commit |

Debug uses a separate bundle ID so a dev install sits beside the beta instead
of replacing it. Favorites and other on-device data do not carry across.

Scheme settings already match this: Run is Debug, Archive is Release.

## Numbers

[`Version.xcconfig`](Version.xcconfig) is the only place the shipping version
is set.

- **Marketing version** (`MARKETING_VERSION`) is `major.minor.patch`, shown to
  people in the App Store.
- **Build** (`CURRENT_PROJECT_VERSION`) is a single counter. Each TestFlight
  cut adds one. It does not reset when the marketing version changes.

Dev runs keep whatever build is committed. They do not upload and do not
advance the counter.

The app target must not set `MARKETING_VERSION` or `CURRENT_PROJECT_VERSION`
in `project.pbxproj`. Those lines override the xcconfig. Test targets keep
their own numbers; they are not uploaded.

## Git

`main` is the only long-lived branch. Feature work merges there through PRs.

- `testflight/<marketing>+<build>` — the commit to archive and upload.
- `v<marketing>` — that same commit, once you submit it to the App Store.

There is no release branch on the normal path. A hotfix branches from the
`v` tag, then merges back to `main`.

## Commands

From the repo root:

```bash
python3 scripts/release.py status
python3 scripts/release.py notes
python3 scripts/release.py bump patch|minor|major
python3 scripts/release.py cut
python3 scripts/release.py archive
python3 scripts/release.py archive --upload
python3 scripts/release.py tf-notes
python3 scripts/release.py promote
python3 scripts/release.py rollout --start
python3 scripts/release.py rollout --halt
```

`check` runs in CI. It fails if the app target hardcodes a version, if
`Version.xcconfig` is malformed, if the export options disagree with the
signing team, or if Debug/Release channel branding is wrong — Release must
ship as `com.collinbrowse.thesilverscreen` / Silver Screen, never the Dev
bundle id or Silver Dev. `archive` re-checks the built app's Info.plist
before export so a contaminated binary cannot upload.

### TestFlight

1. Optionally preview with `python3 scripts/release.py notes`.
2. `python3 scripts/release.py cut` on clean `main`.
3. Push `main` and the `testflight/<marketing>+<build>` tag it prints.
4. GitHub Actions (`.github/workflows/release.yml`) archives, uploads, syncs
   TestFlight “What to Test” from the changelog, and uploads dSYMs to Sentry.
5. Install the build from TestFlight and QA it.

The release job does not rerun unit tests. CI already tested the cut commit
when it landed on `main`. It also waits up to 15 minutes for App Store Connect
to register the upload before it sets “What to Test”.

A tag push runs the workflow file at the tagged commit. If the workflow was
fixed after the cut, rerun the tag from Actions → Release → Run workflow on
`main` with `ref` set to the tag. Leave **upload** off to archive and export
only. That checks signing on the runner without shipping a build.

To archive from a Mac instead of Actions: check out the tag and run
`python3 scripts/release.py archive --upload`, then
`python3 scripts/release.py tf-notes --wait 900`.

`archive` also refuses a binary without a usable Sentry DSN, a direct-TMDB binary
without a TMDB token, and a proxy binary that still contains one.
In `Secrets.xcconfig`, write the DSN as `https:/$()/…` because xcconfig treats
`//` as a comment. The release job escapes the `SENTRY_DSN` secret for you, so
the secret can hold the plain `https://` DSN.

`cut` requires a clean tree on `main`. It finds the latest `testflight/*` tag
that is an ancestor of `HEAD`, turns each merged pull request since then into
one changelog bullet (PR title from the merge commit body, or the squash-merge
subject), commits `Version.xcconfig` and `CHANGELOG.md`, and creates the
`testflight/` tag. Small commits inside a PR are omitted. Optional bullets
under `## [Unreleased]` are prepended when you want curated wording above the
PR list. For a hotfix branch, pass `--branch hotfix/0.1.2` and be on that
branch.

Build 1 has never been uploaded. The first cut publishes build 2.

### App Store

1. Install the TestFlight build and decide it is the one to ship.
2. Check out that `testflight/` tag.
3. `python3 scripts/release.py promote`
4. Push the `v` tag it prints.
5. In App Store Connect, select **that build** and submit it for review.
6. After approval, start phased release with
   `python3 scripts/release.py rollout --start`. Halt with
   `python3 scripts/release.py rollout --halt` if Sentry release health looks bad
   (see [`OBSERVABILITY.md`](OBSERVABILITY.md)).

`promote` does not change version numbers and does not archive. If App Review
rejects the binary, fix it, `cut` again, upload the new build, and run
`python3 scripts/release.py promote --retarget`. That moves the local `v` tag
onto the newer TestFlight commit. Pushing it replaces the remote tag.

### Next marketing version

After a version is on the store (or you want the next beta to show a new
number):

```bash
python3 scripts/release.py bump patch   # or minor, or major
```

Commit that yourself with the work it belongs to. The build counter stays
put until the next `cut`.

### Hotfix

```bash
git checkout -b hotfix/0.1.2 v0.1.1
python3 scripts/release.py bump patch
# fix, commit
python3 scripts/release.py cut --branch hotfix/0.1.2
```

Merge the hotfix back to `main` and keep the higher build number. If `main`
already moved the marketing version forward, keep that newer marketing
version and the higher build.

## Upload credentials

`archive` writes `build/SilverScreen.xcarchive` and
`build/export/SilverScreen.ipa`. `build/` is gitignored.

`--upload`, `tf-notes`, and `rollout` need an App Store Connect API key:

- `ASC_KEY_ID`
- `ASC_ISSUER_ID`
- The `.p8` file named `AuthKey_<ASC_KEY_ID>.p8` in `~/private_keys`,
  `~/.private_keys`, `~/.appstoreconnect/private_keys`, or the directory in
  `API_PRIVATE_KEYS_DIR`. `ASC_KEY_PATH` pointing at the `.p8` file sets that
  directory for you. On CI, set `ASC_KEY_PATH` to the written key file so
  `xcodebuild` can use `-authenticationKeyPath` for non-interactive signing.

GitHub Actions repository secrets for [`.github/workflows/release.yml`](.github/workflows/release.yml):

| Secret | Purpose |
| --- | --- |
| `ASC_KEY_ID` / `ASC_ISSUER_ID` / `ASC_API_KEY_P8` | App Store Connect API key (`.p8` body). Use the Admin role: signing on a fresh runner needs cloud-managed certificates. |
| `DEV_CERT_P12_BASE64` / `DEV_CERT_PASSWORD` | One Apple Development certificate and its private key (`.p12`, base64) so archives reuse it instead of creating a certificate per run |
| `TMDB_ACCESS_TOKEN` | Release binary networking, only while `TMDB_PROXY_URL` is unset |
| `SENTRY_DSN` | Crash reporting in the uploaded build |
| `SENTRY_AUTH_TOKEN` / `SENTRY_ORG` / `SENTRY_PROJECT` | dSYM upload |

Repository variable `TMDB_PROXY_URL` (Settings → Secrets and variables → Actions →
Variables) is the deployed [TMDB proxy](worker/README.md), including `/3`. When it is
set, the release job writes it as `TMDB_BASE_URL` and the binary ships without the TMDB
token. When it is unset, the job falls back to the `TMDB_ACCESS_TOKEN` secret and warns.

The TMDB health check and weekly digest reuse some of these, and the digest
reads Sentry with its own `SENTRY_READ_TOKEN`. See
[Scheduled checks](OBSERVABILITY.md#scheduled-checks) for the full list.

To make the development certificate secret, open Keychain Access → My
Certificates and pick a certificate whose team (Get Info → Organizational
Unit) is the app's `DEVELOPMENT_TEAM`, `84XX2W7G34`. Certificates for other
teams share the same “Apple Development: <name>” label. Export an unexpired “Apple Development” certificate with its
private key as a `.p12`, then:

```bash
base64 -i development.p12 | gh secret set DEV_CERT_P12_BASE64
gh secret set DEV_CERT_PASSWORD
rm development.p12
```

Without it the job still runs, but each archive creates a new “Created via
API” development certificate, and Apple caps how many a team can hold.
Replace the secret when that certificate expires.

`*.p8` files are gitignored. Create the key in App Store Connect → Users and
Access → Integrations.

The export plist keeps `manageAppVersionAndBuildNumber` off so Xcode cannot
replace the numbers from `Version.xcconfig` during export. `archive` reads
the archived app's Info.plist and stops if the version, shipping bundle id,
or display name disagree.
