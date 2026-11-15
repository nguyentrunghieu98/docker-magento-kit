# Coding standards

The standard is the Magento2 PHPCS ruleset that the project already installs. This file adds the review rules a machine cannot check. It does not add a second ruleset.

## Rules

- Four spaces in PHP and XML. Namespaces `Vendor\Module`, PSR-4.
- Constructor injection. Do not use the `ObjectManager` directly.
- Keep controllers, plugins and observers thin. Business logic belongs in a service, queries in a repository, resource model or collection.
- Validate input, check ACL and escape output at the boundary where the data enters or leaves.
- Reuse the pattern a neighbouring module already uses before adding a new one. Follow the existing RequireJS, layout and theme conventions.
- Do not edit `vendor/` or generated files. Do not widen the change to code outside the scope.
- A change in a Magento prose message, UI text or document has no semicolons.

## The two checks

| Check | Catches | Does not catch |
|---|---|---|
| PHPCS `Magento2` | style, naming, forbidden functions, formatting | wrong behavior, a wrong layer, missing validation |
| Review | behavior against the requirement, boundaries, callers, missing tests | a style rule PHPCS can verify faster |

Neither replaces the other. A clean PHPCS run does not mean the change is correct, and a good review does not excuse a PHPCS error.

## Running PHPCS

From the Docker root:

```bash
bin/cli php vendor/bin/phpcs --standard=Magento2 --report=summary <changed-path>
```

`bin/cli` runs against the checkout the stack serves. Use it only when `bin/wt status` shows the branch you are checking. For a worktree that is not served, switch to it with `bin/wt use`, or use the project's isolated runner when `project/agent/references/` documents one.

Never report PASS from a run on another checkout.

## Using the result

- Run it on the paths you changed, not the whole tree.
- Read the warnings. Fix every error you introduced.
- An error that was already there is recorded as FAIL with the line. Do not fix code outside the scope, and do not silence a rule with a blanket ignore.
- Run it after the last edit. A fix applied after the check makes the check stale.
