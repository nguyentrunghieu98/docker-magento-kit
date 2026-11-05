# Git and merge request

The project's base branch and target branch are read-only. The hard boundary lives in `AGENTS.md`.

## Branch

- Cut from `<remote>/<base branch>`, named `<type>/<slug>`.
- `type` is `feat`, `fix`, `hotfix`, `refactor`, `perf` or `chore`. `slug` is lowercase letters, digits and hyphens, 3 to 50 characters.
- Create it with `bin/wt create <type>/<slug>`, never a manual `git worktree add`.

## Commit

- First line follows the pattern `<type>: <imperative sentence, at most 72 characters>`.
- The commit body states the modules touched, the gate commands run, deploy notes and how to roll back.
- Stage specific paths, never `git add -A`. Do not commit secrets, generated files, `vendor/`, `generated/`, `pub/static/`.

## Push and merge request

- Push the branch, then open an MR into `<target branch>`:

```bash
git push -u <remote> <branch> \
  -o merge_request.create \
  -o merge_request.target=<target branch> \
  -o merge_request.title='<title>'
```

- If the push option is rejected, push normally, print the MR URL and stop.
- The MR targets the project's target branch, not the base branch.
- The user is the one who deploys. The agent stops at the pushed branch and the MR.

## Review

- Review the diff from the merge base with the target branch, not the whole repo.
- Four groups to check: logic errors, crossed boundaries, missing gates for the surface that changed, changes outside the scope.
- Findings are ordered Critical, High, Medium, Low. Only suggest a merge when there is no Critical or High finding.
