# Testing and gates (Magento example)

The project facts the workflow needs: which command runs the tests, which gates apply to which
change, and what counts as evidence. The TDD loop itself is in the `tdd-worker` role.

## Unit tests

```bash
bin/test/unit --info --wt <name>                          # read first: script, ParaTest, mode
bin/test/unit --wt <name> <file> --filter <test>          # RED, debugging (serial)
bin/test/unit --wt <name> --parallel <module>/Test/Unit   # GREEN, final check
```

- Agents always pass `--wt <name>`, also for the served checkout (`--wt main` for `src/`). Every run
  gets its own throwaway container, so several runs at once are safe.
- Paths are relative to the Magento root, for example `app/code/<Vendor>/<Module>/Test/Unit`.
- `--parallel` only when `--info` shows a parallel script. Otherwise run serial and write
  `parallel: unavailable` in the evidence.
- `--filter` is serial only. With `--parallel` pick a file or a directory.
- Exit 2 is a prerequisite error, not a test result. The common one: the worktree's `composer.lock`
  differs from the served checkout, so the shared `vendor/` does not match. Do not install
  anything: report it, the user decides.
- A suite that passes serial and fails parallel is a FAIL. Find the shared state, or mark the suite
  serial only with the evidence. Never delete a test to get a green run.
- Integration tests, or anything touching the database, Redis, a queue, an external API or the
  browser: serial, on the served checkout, after `bin/wt status`.

## Gate matrix

Run the gates for the surfaces you changed, after the last edit, and record one line per gate.

| Change surface | Gate | Command | Passes when |
|---|---|---|---|
| Every PHP file | syntax | `bin/wt run <name> php -l <file>` | no syntax error |
| Every PHP/phtml file | coding standard | see `code-standards.md` | 0 new errors, warnings read |
| Behavior change | TDD | RED then GREEN per requirement | every requirement has a real RED, or names the existing test that proves it, or says `TDD N/A` with the reason |
| Module with `Test/Unit` | unit tests | `bin/test/unit --wt <name> [--parallel] <module>/Test/Unit` | pass |
| Class, plugin, preference, observer, controller, CLI, cron | DI compile | `bin/cli php bin/magento setup:di:compile` on the served checkout | exit 0 |
| `db_schema.xml`, data patch, enabling a module | schema | `bin/magento setup:upgrade` then `cache:flush`, tell the user first | exit 0 |
| Layout, template, JS, LESS, CSS, UI component | frontend build | the rebuild table in `ui-testing.md` | exit 0, the page shows the change |
| Layout, template, JS, LESS, CSS, UI component | UI | one screenshot per `ui:` requirement, see `ui-testing.md` | shows what the requirement says, no horizontal overflow, console clean |
| Shared LESS or `_extend.less`, layout `default.xml`, a theme `.phtml` or `.js` used on many pages | UI regression | `ui-regression` command of `ui-testing.md` | no diff beyond the tolerance, baselines untouched |
| Queue, consumer, cron | real run | restart the consumer or run cron, read `var/log` | no new errors |
| `app/etc/config.php` | diff | `git diff -- app/etc/config.php` | only your module's line |
| No automated test | manual check | list the steps and expected results | the user confirms |

DI compile, schema and UI gates need the branch served (`bin/wt use <name>`). Ask before switching
when another worktree is being served.

## Evidence

- Each requirement checkbox is ticked only with the real result line of the command that proved
  it, for example `OK (12 tests, 31 assertions)`.
- A gate is one line: `gate | command | PASS/FAIL/N/A | note`.
- Evidence belongs to the last revision. Any later edit makes earlier results stale: run them again.
- Never report PASS from memory, from a run on another checkout, or from a worker's word without
  its output.
- A gate failing on code that was already broken is FAIL with the error line. Do not fix code
  outside the scope.
