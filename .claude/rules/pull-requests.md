# Pull requests

When creating or editing a GitHub pull request for this repo, the body **must** follow [`.github/pull_request_template.md`](.github/pull_request_template.md). Do not invent a shorter Summary/Test-plan-only body.

## Required workflow

0. **Review first.** The first PR attempt from a branch is held by `.claude/hooks/require-code-review.sh` until you run the `code-review` skill with `--fix` and commit its verified fixes. Then open the PR again.
1. **Read** [`.github/pull_request_template.md`](.github/pull_request_template.md) before drafting.
2. **Fill every section** with real content (or an explicit `None` where the template allows it):
   - `## Summary`
   - `## Decision Tree and Rationale`
   - `## Test Plan` — keep the template’s validation checkboxes; add UI steps and the screenshot path when UI changed
   - `## AI Harness notes` — describe harness changes, or `None` if app-only
3. **Validate** before claiming the PR is ready:
   ```bash
   gh pr view --json body -q .body | python3 scripts/validate-pr-body.py
   ```
   Or: `python3 scripts/validate-pr-body.py --pr <number>`
4. CI runs the same script on pull requests and **fails** if sections are missing.
5. **Turn on Auto-fix** for the new PR right after opening it (in the Claude desktop app: the `ccd_pr` set-monitor tool with `auto_fix` on). The app then wakes the session on CI failures, merge conflicts, and review comments. The user has approved this for every PR.

## Do not

- Skip Decision Tree or AI Harness notes.
- Replace the template Test Plan checkboxes with an ad-hoc list only.
- Open a PR with a placeholder or truncated body “to fill in later.”

## Auto-merge

After Auto-fix is on, queue the merge: `gh pr merge --auto --merge` (or the `ccd_pr`
auto-merge tool). The user approved this for every PR. GitHub then merges once the
`main` ruleset is satisfied: CI green, plus code-owner approval when the PR touches a
path in [`.github/CODEOWNERS`](.github/CODEOWNERS). See [`AUTOMERGE.md`](AUTOMERGE.md).

- Never merge without `--auto`, and never use an admin bypass. The release gate hook
  asks the user first.
- When a PR touches a gated path, say so in the PR body's Summary and tell the user
  their approval is needed.
- Releases are the user's alone. Never cut, bump, promote, create or push tags, run
  `release.yml`, or create GitHub releases unless the user asks for that specific step
  in chat; the release gate hook then asks them to confirm. GitHub backs this up with
  the release-tag ruleset and the `release` environment's required approval (see
  [`releases.md`](.claude/rules/releases.md)).
