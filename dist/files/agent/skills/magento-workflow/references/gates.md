# Gate matrix

Run the gates that apply to the surface you changed. Record one evidence line per gate. Run commands from the Docker root as described in `AGENTS.md`.

| Change surface | Gate | Command | Passes when |
|---|---|---|---|
| Every PHP file | syntax | `bin/cli php -l <file>` for each changed file | no syntax error |
| Every PHP file | coding standard | `bin/cli php vendor/bin/phpcs --standard=Magento2 --report=summary <path>` | 0 errors, warnings read |
| Class, plugin, preference, observer, controller, CLI, cron, autoload | DI compile | `bin/cli php bin/magento setup:di:compile` | exit 0 |
| `db_schema.xml`, data patch, enabling a module | schema | `bin/magento setup:upgrade` then `cache:flush` | exit 0 |
| Layout, template, JS, LESS, CSS | frontend build | `npx grunt less:<theme>` or the project command | exit 0 |
| Layout, template, JS, LESS, CSS | UI | Playwright at 1440 and 390, screenshots | matches the design, no horizontal overflow |
| Has `Test/Unit` | unit test | `bin/cli php vendor/bin/phpunit -c dev/tests/unit/phpunit.xml.dist <test directory>` | pass |
| i18n strings | static test | `bin/cli php vendor/bin/phpunit -c dev/tests/static/phpunit.xml.dist` (narrow scope) | pass |
| Queue, consumer, cron | real run | restart the consumer or run cron, read `var/log` | no new errors |
| `app/etc/config.php` | diff | `git diff -- app/etc/config.php` | only your module's lines |
| No automated test | manual check | list the steps and expected results | the user confirms |

## Notes

- `setup:di:compile` and `setup:upgrade` are slow, run them once per change rather than per file.
- The schema is shared across every worktree. Tell the user before running `setup:upgrade`.
- The UI gate needs a running stack. Without Playwright, state that it was not checked, do not attach fake screenshots.
- Do not report PASS from memory or from a previous run. Re-run after the last edit.
- A gate failing because of pre-existing code is recorded as FAIL with the error line, do not fix code outside the scope.

## Evidence template

```
php -l app/code/Vendor/Module/Model/Foo.php     | PASS
phpcs --report=summary app/code/Vendor/Module    | PASS (0 errors, 2 warnings)
setup:di:compile                                | N/A (no DI touched)
unit test (Vendor_Module)                       | PASS (12 tests)
Playwright 1440/390                             | PASS (screenshots saved)
```
