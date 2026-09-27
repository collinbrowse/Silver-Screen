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
python3 scripts/release.py promote
```

`check` runs in CI. It fails if the app target hardcodes a version, if
`Version.xcconfig` is malformed, or if the export options disagree with the
signing team.

### TestFlight

1. Write what changed under `## [Unreleased]` in [`CHANGELOG.md`](CHANGELOG.md).
2. `python3 scripts/release.py cut`
3. Push the branch and the tag it prints.
4. Check out that tag (or stay on it if you have not committed since) and run
   `python3 scripts/release.py archive --upload`.

`cut` requires a clean tree on `main`. It adds one to the build, commits
`Version.xcconfig` and `CHANGELOG.md`, and creates the `testflight/` tag.
For a hotfix branch, pass `--branch hotfix/0.1.2` and be on that branch.

Build 1 has never been uploaded. The first cut publishes build 2.

### App Store

1. Install the TestFlight build and decide it is the one to ship.
2. Check out that `testflight/` tag.
3. `python3 scripts/release.py promote`
4. Push the `v` tag it prints.
5. In App Store Connect, select **that build** and submit it for review.

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

`archive` writes `build/TheSilverScreen.xcarchive` and
`build/export/TheSilverScreen.ipa`. `build/` is gitignored.

`--upload` needs an App Store Connect API key:

- `ASC_KEY_ID`
- `ASC_ISSUER_ID`
- The `.p8` file named `AuthKey_<ASC_KEY_ID>.p8` in `~/private_keys`,
  `~/.private_keys`, `~/.appstoreconnect/private_keys`, or the directory in
  `API_PRIVATE_KEYS_DIR`. `ASC_KEY_PATH` pointing at the `.p8` file sets that
  directory for you.

`*.p8` files are gitignored. Create the key in App Store Connect → Users and
Access → Integrations.

The export plist keeps `manageAppVersionAndBuildNumber` off so Xcode cannot
replace the numbers from `Version.xcconfig` during export. `archive` reads
the archived app's Info.plist and stops if it disagrees.
