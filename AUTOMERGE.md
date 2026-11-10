# Auto-merge

Agents land work on `main` without a person clicking Merge, as long as CI is green and
the PR doesn't touch a human-gated path. Cutting builds, pushing tags, and shipping stay
with a person.

## What enforces it

| Layer | What it does | Where |
| --- | --- | --- |
| `main` ruleset | PR required; `Validate rules` and `Unit tests` must pass; code-owner approval required; no force-push or deletion | GitHub → Settings → Rules |
| `CODEOWNERS` | Names the human-gated paths: persistence, `Info.plist`, privacy manifest, entitlements, versions, release scripts, the Worker, and the harness itself | [`.github/CODEOWNERS`](.github/CODEOWNERS) |
| Release-tag ruleset | Only admins create, move, or delete `testflight/*` and `v*` tags, so only a person can fire `release.yml` | GitHub → Settings → Rules |
| Repo setting | Auto-merge allowed, so `gh pr merge --auto` waits for checks and approvals | GitHub → Settings → General |
| Release gate hook | Agent `release.py cut / bump / promote / archive --upload`, pushes of tags or `main`, `gh pr merge` without `--auto`, and protection edits all prompt the person first | [`.claude/hooks/gate-release-actions.sh`](.claude/hooks/gate-release-actions.sh) |

Both rulesets let the **admin** role bypass, which is you. Release cuts that commit
straight to `main` keep working from your account.

GitHub reads `CODEOWNERS` from the base branch, so a PR can't remove its own gate.

## Agent identity

The rulesets can only tell an agent from you if the agent uses a different GitHub
account. Until it does, an agent acting with your `gh` login is an admin and can
bypass them, and only the release gate hook and the rules hold it back.

The agent account is a machine user with **Write** access, so it can't bypass. A
GitHub App would also work, but its installation tokens expire every hour and need a
minting step. A machine user's token works with `gh` and `git` as is.

### One-time setup

1. Create a second GitHub account for the agent, for example `silverscreen-agent`, with
   its own email address. Turn on two-factor authentication. GitHub's terms allow one
   free machine account per person.
2. From your own account, invite it with write access:
   ```bash
   gh api -X PUT repos/collinbrowse/Silver-Screen/collaborators/silverscreen-agent -f permission=push
   ```
   Then sign in as the agent and accept the invitation.
3. As the agent, create a **classic** personal access token with the `repo` and
   `workflow` scopes (Settings → Developer settings → Tokens (classic)), set to expire in
   a year. A fine-grained token won't work, because those can only reach repos the
   token's owner owns.
4. In the main checkout, create `.claude/settings.local.json` (git ignores it, and
   [`.worktreeinclude`](.worktreeinclude) copies it into new worktrees):
   ```json
   {
     "env": {
       "GH_TOKEN": "<agent token>",
       "GIT_CONFIG_COUNT": "2",
       "GIT_CONFIG_KEY_0": "credential.helper",
       "GIT_CONFIG_VALUE_0": "",
       "GIT_CONFIG_KEY_1": "credential.helper",
       "GIT_CONFIG_VALUE_1": "!gh auth git-credential"
     }
   }
   ```
   The `GIT_CONFIG_*` lines clear the helper list (the empty value drops `osxkeychain`)
   and put `gh` in its place, so `git push` from Claude uses the agent token instead of
   your keychain login. Your own terminal is unchanged.
5. Check it from a new Claude session:
   ```bash
   gh api user --jq .login
   ```
   It should print the agent account. Its PRs then show the agent as author, and you
   approve any that touch a `CODEOWNERS` path.

Put a reminder in your calendar to rotate the token before it expires.

## Day to day

- An agent opens a PR, turns on Auto-fix, then runs `gh pr merge --auto --merge`.
- If no gated path changed, GitHub merges once CI passes.
- If a gated path changed, the PR waits for your approval. Approve it and it merges.
  Pushing new commits dismisses your approval.
- You cut and ship releases as before (`RELEASE.md`).
