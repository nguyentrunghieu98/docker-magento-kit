# Code standards (Magento example)

The standard is the Magento2 PHPCS ruleset the project installs, plus the review rules a machine
cannot check. Neither replaces the other: a clean PHPCS run does not make a change correct, a good
review does not excuse a PHPCS error.

## PHPCS gate

```bash
bin/wt run <name> vendor/bin/phpcs --standard=Magento2 --report=summary <changed paths>
```

- Use exactly this command. Do not wrap it in a script that adds `--ignore-annotations` or raises
  the severity: the count changes and justified `phpcs:ignore` lines stop being checked.
- Run it on the changed paths, not the whole tree, after the last edit.
- Fix every error you introduced. An error that was already there is FAIL with the line: do not
  fix code outside the scope and do not add a blanket ignore. A targeted `phpcs:ignore` needs a
  reason on the same line.

## Rules

- Four spaces in PHP and XML. Namespaces `Vendor\Module`, PSR-4.
- Constructor injection. Never use the `ObjectManager` directly.
- Controllers, plugins and observers stay thin. Business logic belongs in a service, queries in a
  repository, resource model or collection.
- Validate input, check ACL and escape output where data enters or leaves.
- Reuse the pattern a neighbouring module already uses before adding a new one. Follow the existing
  RequireJS, layout and theme conventions. UI work follows the project's UI rules file.
- Third-party code in `app/code` and `vendor/` is read-only: change behavior with a plugin,
  preference or composer patch owned by a first-party module (`module-map.md`).
- Do not edit generated files. Do not widen the change beyond the scope.
- Prose rules for messages, UI text and documents are in `AGENTS.md`.

## Review checks

Logic errors, crossed boundaries (`vendor/`, secrets, read-only branches), missing gates for the
changed surface (`testing.md`), changes outside the scope, tests that would not fail on a real
defect, state shared between tests that breaks a parallel run, callers of changed code that no test
covers.
