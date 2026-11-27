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

## Comments

Code explains itself through names, types and small methods. A comment the branch adds or changes
is deleted unless it fits one of the keeps below. When unsure whether a keep applies, delete it.
Scope is the lines the branch changed: leave existing comments on untouched lines alone.

Keeps:

- License or copyright headers that already exist in the file. Do not add new ones.
- PHPDoc the Magento2 PHPCS standard demands (sniffs `MethodAnnotationStructure`,
  `ClassPropertyPHPDocFormatting`, warnings at severity 5): every method, the constructor included,
  and every property gets a docblock. Keep it minimal: a one-line short description that says
  something the name does not, plus `@param`, `@return`, `@throws`, `@var`. A tags-only method
  docblock fails with `Missing short description`. A method that implements an interface or
  overrides a parent uses `@inheritdoc` alone. A class or interface docblock is optional and, if
  present, must say more than the name (`ClassAndInterfacePHPDocFormatting.InvalidDescription`).
- Type tags that carry what PHP cannot: `@var` in `.phtml` (`/** @var \Magento\Framework\Escaper $escaper */`,
  `/** @var \Vendor\Module\ViewModel\X $viewModel */`), array shapes and generics
  (`@param array<string, int>`, `@return ProductInterface[]`), `@api`, `@deprecated` with its `@see`.
- Behaviour forced by something we cannot change: Magento core, third-party modules, `vendor/`,
  an ERP or payment-gateway protocol, a browser quirk. One line, with the issue or upstream link when
  one exists. A surprise in our own code (the first-party modules in `module-map.md`) is not a keep:
  delete the comment and rename, extract or type the code until the behaviour is obvious.

Delete on sight: narration of what the next line does, section banners in PHP, XML, JS and LESS
(`<!-- Plugins -->`, `// ===== Helpers`), commented-out code (also `Squiz.PHP.CommentedOutCode`),
`TODO` or `fix later` without an issue link, change logs and author names in code, comments in
`di.xml`, `events.xml`, layout XML and `system.xml` that restate the node.

Suppressions are judged by the rule they silence:

- `phpcs:ignore <Sniff> -- <reason>` stays only when the sniff is pedantic or a false positive for
  that line, with the reason on the same line. Never a blanket `phpcs:ignore` or
  `phpcs:disable` without a sniff name.
- A suppression of a correctness or security rule (`Magento2.Security.*`, `Magento2.SQL.RawQuery`,
  escaping, `Magento2.Functions.DiscouragedFunction` on `serialize`, `eval`, file or shell calls)
  is a finding: remove it and fix the code.
- `/* @noEscape */` in a template is a security suppression. It stays only on output that is
  already safe HTML (`$block->getChildHtml()`, `$escaper->escape*()` result, a JSON encoded with
  the Magento serializer into a `data-mage-init` or `x-magento-init`). Anything else uses
  `$escaper`.
- `@SuppressWarnings(PHPMD.*)` and `eslint-disable` follow the same rule: style and size metrics
  may stay on code the branch did not write, never on new code.

A comment that guards a constraint (`do not remove`, `must run before X`) is replaced
by a test, a type, a `sortOrder` or `before`/`after` in XML, or a runtime check that fails when the
constraint breaks. If none fits the scope, delete the comment and report the constraint as open
work in the MR.

List the comment lines a branch added:

```bash
git diff -U0 $(git merge-base <target> HEAD) -- app/code/<Vendor> app/design \
  | grep -nE '^\+\s*(//|#|/\*|\*|<!--)|^\+.*\s//\s'
```

## Review checks

Logic errors, crossed boundaries (`vendor/`, secrets, read-only branches), missing gates for the
changed surface (`testing.md`), changes outside the scope, tests that would not fail on a real
defect, state shared between tests that breaks a parallel run, callers of changed code that no test
covers. Comments the branch added that break the `Comments` section, each with the command
output above that lists it: an added suppression of a correctness or security rule is High, the
rest Low.
