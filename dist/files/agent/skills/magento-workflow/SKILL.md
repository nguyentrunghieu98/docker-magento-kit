---
name: magento-workflow
description: Knowledge for running Magento commands in Docker, the gate matrix, Git and merge request conventions, and the package's worktree rules. Load when running checks for a change, when committing or creating an MR, or when switching worktree.
---

# magento-workflow

This is knowledge about how to work, not a work sequence. The harness's process skill set decides the sequence.

`AGENTS.md` in the Docker root is the source of the hard boundary, how to run commands and the worktree rules. This skill only expands three parts:

- `references/gates.md` — gate matrix per change surface, evidence template.
- `references/git-mr.md` — branch, commit, push, merge request, review conventions.
- `references/worktree.md` — `bin/wt` and changing the checkout the stack serves.

Every PHP and Magento command runs through the Docker root with `bin/cli` or `bin/magento`. If the containers are stopped, run `bin/start`.
