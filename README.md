# magento-docker-kit

[English](README.md) | [Tiếng Việt](README.vi.md)

A small overlay for a [markshust/docker-magento](https://github.com/markshust/docker-magento)
Docker root: one stack serving many Git worktrees, one unit test runner, and agent hooks.
Docker itself comes from upstream; this kit only adds what upstream does not have.
There is no installer, no profile file and no generated configuration.

## What is in it

| Path | Purpose |
|---|---|
| `docker/bin/wt` | Create, switch and clean worktrees in `.worktrees/`. One stack, one DB, one `vendor/` |
| `docker/compose.worktree.yaml` | Overlay that mounts `.active-src` (the active worktree) |
| `docker/bin/docker-compose` | Upstream file plus one block that loads the overlay when `.active-src` is a symlink |
| `docker/bin/test/unit` | The one unit test runner: serial, `--parallel` (ParaTest), `--wt`, `--xdebug`, `--coverage` |
| `docker/bin/phpcs` | Upstream file plus `--wt <name>` |
| `docker/bin/watch` | Frontend watcher that follows `.active-src` |
| `docker/conf/php/opcache.ini` | OPcache settings for development |
| `agents/hooks/ui-conventions.sh` | Agent hook that injects the project's UI rules when a UI file is edited |

## Add it to a Docker root

Set up the Docker root with upstream first, then copy the overlay over it:

```bash
cp -a magento-docker-kit/docker/. /path/to/docker-root/
git -C /path/to/docker-root/src config wt.from origin/master    # base of new worktrees
git -C /path/to/docker-root/src config wt.into origin/staging   # target used by prune
```

Copying overwrites files with the same name. On a Docker root that already has its own
`compose.worktree.yaml` or `bin/docker-compose`, compare them file by file instead.
The overlay covers `app` and `phpfpm`. Upstream's `phpfpm-xdebug` still mounts `./src`,
so `--xdebug` runs against `src/`, not the active worktree.

`wt.from` / `wt.into` live in `src/.git/config`. They are not committed and can be
replaced per call with `--from` / `--into`. Without either, `bin/wt` stops and says how to set them.

## Worktrees

```bash
bin/wt create feat/checkout-rework   # new branch from wt.from (or --from <remote>/<branch>)
bin/wt use feat-checkout-rework      # the stack now serves that worktree (only app and phpfpm restart)
bin/wt status
bin/wt list
bin/wt run <name> <command...>       # run a command for that checkout in a throwaway container
bin/wt prune --dry-run               # merged into wt.into (or --into) and review worktrees
bin/wt doctor                        # compare the phpfpm mount with .active-src
```

## Unit tests

```bash
bin/test/unit --info                                 # what the runner will do: read this first
bin/test/unit <path> --filter <regex>                # serial, on the active checkout
bin/test/unit --parallel <path>                      # ParaTest
bin/test/unit --wt <name> [--parallel] <path>        # throwaway container (what agents use)
bin/test/unit --xdebug <path>                        # through upstream bin/debug-cli
bin/test/unit --coverage <path>                      # HTML report in dev/tests/unit/report
```

- The command comes from the project's composer scripts `test:unit` / `test:unit:parallel`.
  Without them: `vendor/bin/phpunit` / `vendor/bin/paratest -p ${TEST_PROCESSES:-2}` with
  `dev/tests/unit/phpunit.xml.dist`.
- `--parallel` without ParaTest exits 2 with the install command. It never falls back to serial.
- `--wt` always uses a new container: same image as `phpfpm`, no network, checkout and shared
  `vendor/` read-only, tmpfs for `generated/`, `var/` and `dev/tests/unit/tmp`. Several runs at
  once never share those directories. A `composer.lock` that differs from the active checkout's
  (the lock the shared `vendor/` follows) stops the run.
- Exit code 2 is a usage or prerequisite error, anything else is the tests' exit code.

## UI rules hook

```json
{
  "hooks": {
    "PreToolUse": [{
      "matcher": "Edit|Write|MultiEdit",
      "hooks": [{ "type": "command", "timeout": 10,
        "command": "\"$CLAUDE_PROJECT_DIR\"/.agents/hooks/ui-conventions.sh docs/agents/ui-conventions.md" }]
    }]
  }
}
```

The argument is the rules file relative to the Magento root. The hook reads it from the
edited checkout, else from `src/`, and warns on stderr when it is missing.

## Tests

```bash
bash tests/run-all.sh
```

The tests need bash, git and jq. Docker is replaced by a fake that logs its calls.
