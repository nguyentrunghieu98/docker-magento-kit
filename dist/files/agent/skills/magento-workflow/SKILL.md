---
name: magento-workflow
description: Knowledge for running Magento commands in Docker, the gate matrix, TDD and unit test rules, the coding standard, Git and merge request conventions, and the package's worktree rules. Load when writing or reviewing code, running tests or checks for a change, committing or creating an MR, or switching worktree.
---

# magento-workflow

This is knowledge about how to work, not a work sequence. The harness's process skill set decides the sequence.

`AGENTS.md` in the Docker root is the source of the hard boundary, how to run commands and the worktree rules. This skill only expands five parts:

- `references/gates.md` — gate matrix per change surface, evidence template.
- `references/testing.md` — RED, GREEN, REFACTOR, the isolated unit test commands, when to run in parallel, what counts as evidence.
- `references/coding-standards.md` — the Magento2 PHPCS standard, the review rules a machine cannot check, how to run PHPCS on a worktree.
- `references/git-mr.md` — branch, commit, push, merge request, review conventions.
- `references/worktree.md` — `bin/wt` and changing the checkout the stack serves.

Every PHP and Magento command runs through the Docker root with `bin/cli` or `bin/magento`. If the containers are stopped, run `bin/start`.
