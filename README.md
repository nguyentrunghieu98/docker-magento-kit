# magento-docker-kit

[English](README.md) | [Tiếng Việt](README.vi.md)

A small overlay for a [markshust/docker-magento](https://github.com/markshust/docker-magento)
Docker root: one stack serving many Git worktrees, one unit test runner, four skills and five agent
roles. Docker itself comes from upstream; this kit only adds what upstream does not have.
`sync` copies the overlay into a Docker root or reports what drifted.
There is no installer, no profile file and no generated configuration.

## What is in it

| Path | Purpose |
|---|---|
| `sync` | Copy the overlay into a Docker root, or report what drifted |
| `docker/bin/wt` | Create, switch and clean worktrees in `.worktrees/`. One stack, one DB, one `vendor/` |
| `docker/compose.worktree.yaml` | Overlay that mounts `.active-src` (the active worktree) |
| `docker/bin/docker-compose` | Upstream file plus one block that loads the overlay when `.active-src` is a symlink |
| `docker/bin/test/unit` | The one unit test runner: serial, `--parallel` (ParaTest), `--wt`, `--xdebug`, `--coverage` |
| `docker/bin/phpcs` | Upstream file plus `--wt <name>` |
| `docker/bin/watch` | Frontend watcher that follows `.active-src` |
| `docker/conf/php/opcache.ini` | OPcache settings for development |
| `agents/skills/` | Four skills: `plan-create`, `plan-orchestrate`, `project-update`, `project-setup` |
| `agents/agents/` | Five roles: `code-researcher`, `devils-advocate`, `tdd-worker`, `standards-enforcer`, `diff-reviewer` |
| `agents/hooks/ui-conventions.sh` | Agent hook that injects the project's UI rules when a UI file is edited |

## Add it to a Docker root

Set up the Docker root with upstream first, then copy the overlay from the kit:

```bash
./sync --target /path/to/docker-root          # list what is missing or different
./sync --target /path/to/docker-root --apply  # copy it
git -C /path/to/docker-root/src config wt.from origin/master    # base of new worktrees
git -C /path/to/docker-root/src config wt.into origin/staging   # target used by prune
```

`sync` only adds and updates. It never deletes, so a file the kit drops is removed in the project by
hand. A file you changed in the project shows up as `M`: decide per file instead of applying blindly.
`--skip <path>` leaves one file alone, for a file the project owns itself (for example its own
`compose.worktree.yaml`).
On a Docker root that already has its own `compose.worktree.yaml` or `bin/docker-compose`, compare
the two before the first `--apply`.
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

## The project layer

The kit carries the shared layer only. A project writes its own `AGENTS.md` (the single source) and
`project/agent/references/{architecture,testing,code-standards}.md`, and links the harness files to
the shared ones:

```
CLAUDE.md                -> AGENTS.md
.claude/skills           -> ../.agents/skills
.claude/agents/<role>.md -> ../../.agents/agents/<role>.md
```

A harness with agent types (Claude Code `.claude/agents`, OMP `.omp/agents`) calls a role by name.
Every other harness reads `.agents/agents/<role>.md`, drops the frontmatter and passes the body to
its subagent tool.

`project-setup` does this once per project. `project-update` runs `sync` and checks that `AGENTS.md`
still answers what the skills read. `agents/skills/project-setup/references/examples/magento/` is the
worked example for the three references.

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
  `vendor/` read-only, tmpfs for `generated/`, `var/` and `dev/tests/unit`. Several runs at
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
