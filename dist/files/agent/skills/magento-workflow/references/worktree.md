# Worktree

One stack, one DB, one `vendor/`, one `node_modules/` and one `pub/media/` for every worktree. Only one checkout is served at a time.

## Commands

- `bin/wt create <type>/<slug>`: create a worktree in `.worktrees/<dir>`, branch cut from `<remote>/<base branch>`.
- `bin/wt create --review-mr <id> [--ref <branch>]`: create a detached `review-mr<id>` worktree to review an MR.
- `bin/wt use <name|path>`: switch the served checkout. It only accepts the main checkout and paths under `.worktrees/`.
- `bin/wt status`: show the served checkout. Run it before every Magento command.
- `bin/wt prepare`: copy the core files the checkout still lacks and install the agent kit.
- `bin/wt adopt <path>`: move a misplaced worktree to the standard location, then `prepare`.
- `bin/wt prune --dry-run`: print the list that will be deleted. `bin/wt prune` deletes exactly that list and keeps the branch.
- `bin/wt doctor`: compare the real phpfpm mount with the `.active-src` target, warn when `base_url` differs from `KIT_DOMAIN` and when a profile key is wrong.

## Rules

- `bin/wt` is the only way to create and switch worktrees. Hand-editing `.active-src` or `git worktree add` makes the stack mount the wrong place.
- `prune` keeps worktrees with changes, the served worktree and unmerged worktrees. Review `--dry-run` before deleting.
- Worktrees share a DB, so a schema change affects every worktree.
