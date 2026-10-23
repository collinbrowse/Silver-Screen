# Reviewable commits

Commits are for reviewers, not for the agent’s convenience. Prefer several small commits over one large one.

## Size

- **One logical unit per commit.** Examples: “secrets + toolchain”, “data layer”, “list layout”, “ImageLoader”.
- Do **not** land unrelated changes in a single commit.
- If work grew into a mega-commit, rewrite it into reviewable commits on the feature branch **before** asking for review (backup the tip first; force-push only that feature branch).

## Shape

- Commit message: 1–2 sentences on **why**, in the repo’s existing style.
- Include the tests and screenshot for a change in **that change’s** commit when they belong together.
- Shared foundation that several features need (repository, `LoadState`, secrets) may be its own commit(s) ahead of the feature commits.
- Do not mix harness-only changes with app changes unless the harness change is required for that work to verify.

## When implementing

- Commit each logical unit as soon as it is verified, without being asked, rather than accumulating everything until the end.

## Pushing

Every push to a branch with an open PR triggers GitHub CI, which costs usage. So:

- **Before any `git push`, check for an open PR:** `gh pr view --json state -q .state` (prints `OPEN` when the current branch has one).
- **Open PR → do not push.** Commit locally and stop. Tell the user how many commits are waiting (`git log --oneline @{u}..`); they decide when to push. This includes force-pushes after a history rewrite.
- **No open PR → pushing is fine**, e.g. to publish the branch and open the PR the user asked for.
- Push to a branch with an open PR only when the user explicitly asks for that push. One “push it” covers that push, not later ones.
- **Exception: Auto-fix.** When the desktop app sends a `<ci-monitor-event>` for a PR with Auto-fix on, fix the CI failure, merge conflict, or review comment, verify, commit, and push without asking. Turning on Auto-fix is the user's approval for those pushes, and only those.
