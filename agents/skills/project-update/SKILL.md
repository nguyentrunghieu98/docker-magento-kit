---
name: project-update
description: Update a project from the kit after the kit changed - report the drift, show the diff, copy on approval and check that AGENTS.md still gives the skills what they read. Use when the user says update from the kit, or when a kit file changed under them.
---

# project-update

The kit ships `sync`, a script. This skill runs it and checks the project contract. It copies no
file itself and writes no generator output.

## 1. Report

- Read `AGENTS.md` for the Docker root (the parent of the agent root) and for where the kit
  checkout is.
- Run `sync --target <Docker root>` in the kit. It lists `A` (missing) and `M` (different).
- For each `M`, show a short diff when the file changes behavior, not only comments:
  `diff -u <project file> <kit file> | head -40`.

## 2. Approve

Summarize in three lines: how many files, which areas (docker overlay, skills, roles, hook), and
any `X` conflict. Ask before applying.

A file the user edited locally is a decision, not an automatic copy. Offer: keep the local version,
move the edit into the kit, or take the kit version.

## 3. Apply

- `sync --target <Docker root> --apply`.
- Run it again. It must print `0 added, 0 changed`.

`sync` never deletes. When the kit drops a file, the kit's README says so: remove the project copy
by hand, in the same commit.

## 4. Check the contract

The skills read these from `AGENTS.md`. Report anything missing or stale, never invent it:

- the Docker root, the agent root and the checkout directory
- the command that creates, lists and switches a checkout
- the test command and its info mode
- the project references (architecture, testing, standards) and their paths
- the Git rules: branch, commit, push, merge request target
- where plans and evidence live

## Rules

- Never run `--apply` before the user approves the list.
- Never edit files under `.agents/` in the project: they belong to the kit, and the next sync
  would overwrite them. Move the edit into the kit instead.
