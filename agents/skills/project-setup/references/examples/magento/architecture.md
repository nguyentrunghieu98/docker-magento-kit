# Architecture (Magento example)

How this project is laid out and run. Module ownership is in `module-map.md`. Replace every
`<placeholder>` with the project's own fact, and delete what does not apply.

## Docker root

Mark Shust's docker-magento with the kit's overlay (`bin/wt`, `bin/test/unit`, `bin/phpcs --wt`,
`compose.worktree.yaml`). The Docker root is not a Git repository. Magento lives in `src/`, its own
Git repository, mounted at `/var/www/html`. `src/` is also the agent root: the harness is opened
there and this file lives under it. `vendor/`, `generated/` and `pub/static/` are output.

Services and images: read `compose.yaml` and `bin/docker-compose ps`, do not trust a copy here.
`phpfpm` runs the image `<image reference>`.

## Commands

No PHP on the host: every PHP and Magento command runs from the Docker root, one level above the
agent root (`cd ..` first, or `../bin/<command>`).

```bash
bin/start | bin/stop | bin/status
bin/cli <command>        # any command in phpfpm, paths relative to /var/www/html
bin/magento <cmd> | bin/composer <cmd> | bin/grunt less:<theme>
bin/watch                # clears pub/static links on JS/LESS/phtml change, follows .active-src
```

## Checkouts

One stack, one database, one `vendor/`, `node_modules/` and `pub/media/` for every worktree. Only
the checkout `.active-src` points at is served.

```bash
bin/wt create <type>/<slug>      # new branch from <remote>/<base branch> (git config wt.from)
bin/wt status                    # the served checkout: run it before any Magento command
bin/wt list | path <name> | shell <name>
bin/wt use <name>                # serve that worktree, recreates app and phpfpm only
bin/wt run <name> <command...>   # one command for that checkout in a throwaway container
bin/wt prune --dry-run           # merged into <remote>/<target branch> (git config wt.into)
bin/wt doctor                    # compare the phpfpm mount with .active-src
```

- `bin/wt` is the only way to create and switch worktrees. Never edit `.active-src`, never use
  `git worktree add`, `mv` or `cp -r` for worktrees.
- The database is shared: a schema change or `composer install` affects every worktree. Tell the
  user before `setup:upgrade`.
- `src/.gitignore` is a whitelist, so a fresh worktree lacks generated core files. `bin/wt create`
  and `prepare` copy them. A 404 right after a switch usually means they are missing.

## Searching

- Never `find /` or `find ~`: it scans the whole disk and runs into the command timeout.
- Code: `rg -n` scoped to the custom code directories or one module, never the whole `vendor/`,
  `generated/`, `pub/static/` or `var/`.
- Locate first, then read: `rg -n` for the line, then `sed -n '<from>,<to>p'` around it. Never cat
  a whole template, test or class over about 150 lines.
- Git: `git status --short`, `git diff --stat` first, then `git diff -- <file>` for the files you
  need. Never a bare `git diff` on a whole branch.
- `AGENTS.md` is already loaded: never read it again. Read a reference once per session, only the
  one the task needs.

## Setup

`<memory, ports and local URLs>`.
