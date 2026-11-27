---
name: no-comments
description: Clean the comments a branch added - run the comment-sicko role, check its deletions, fix the accepted MUST KILL flags in scope and offer a test or type for each claimed constraint. Use when the user says no comments, clean comments or /no-comments, or when plan-orchestrate turns comment-sicko on.
---

# no-comments

Run `comment-sicko`, then act on what you accept. Its rules are the `Comments` section of the
project's `code-standards.md`: do not restate them here or to the role.

## Scope

The files or diff the user gives. Otherwise the diff from the merge base with the target branch
named in `AGENTS.md`, working tree included, in the `bin/wt` checkout of the branch. Never the
main checkout.

## Steps

1. **Spawn.** Run the `comment-sicko` role with the scope, the Docker root, the checkout and the
   PHPCS gate command of `code-standards.md`. Use the model `AGENTS.md` gives the role. Pass the
   role body when the harness has no agent type for it.
2. **Inspect.** Read its report and `git diff` of the files it touched. Reject the run if it
   changed a code line, a signature, an XML node or template output, touched a file or line outside
   the scope, deleted a keep the `Comments` section protects, or gave a false reason for a
   `MUST KILL`. A keep about our own code survives only with proof that the behaviour comes from
   something we cannot change: otherwise delete it yourself. Before you accept or overrule a kill
   of `IMPORTANT` or `do not remove`, trace the symbol and read its history (`git log -L`,
   `git log -S`). An ambiguous kill stays killed. A rejected run: revert its edits with
   `git checkout -p` on its hunks only, then rerun it once with the failure named. A second
   rejection: revert, report it open and stop.
3. **Fix trivial flags.** Delete a dead path, drop an unused parameter, rename a symbol, use the
   real API, move an order constraint into `sortOrder` or `before`/`after`. Stay inside the scope.
   A flag whose fix changes behaviour or needs a design is not trivial: write a short sketch of the
   shape (which class, which seam) and report it open. Do not implement it here. A fix that grows
   into a heavy trigger of `AGENTS.md` goes back to the user for the lane.
4. **Root cause, no guards.** Fix the reason the comment was needed and remove the workaround it
   excused. Never add a guard to silence a symptom. A root cause outside the scope: land the
   smallest in-scope fix and report the rest.
5. **Constraints.** For each `do not remove`, `must run before X` or `ask X before changing` that
   holds, offer the cheapest encoding in scope: a unit test, a type, an XML order, a runtime check.
   Wait for the user. Encode on approval, then the comment goes. Without approval the comment still
   goes and the constraint is reported open.
6. **Gates.** Run the PHPCS gate of `code-standards.md` and the `Test/Unit` of every touched module
   again. Evidence belongs to this last revision.

## Return

Deletion count, comments restored, reruns, fixes made, sketches for open flags, encodings offered
and made, constraints left unenforced, the PHPCS and test result lines.
