---
name: project-setup
description: Set up a new project on the kit, or adopt an existing Docker root - place the overlay, write AGENTS.md from the project's own facts, link the harness files and verify. Use when the user says set up this project with the kit.
---

# project-setup

One project, one Docker root. This skill places the overlay and writes the project layer. Magento
is the worked example in `references/examples/magento/`.

## 1. Facts

Ask for what the code cannot answer, then read the rest. Two groups, one message: what changes the
layout (root, repository directory, branch a change starts from, branch a merge request targets)
and what changes the commands (how commands run, the exact test command, the gates, the standard).

## 2. Place the overlay

- Run `sync --target <project root> --apply` in the kit, then `sync --target <project root>` again:
  it must print `0 added, 0 changed`.
- Create the harness links, so one physical copy serves every harness:
  - `CLAUDE.md -> AGENTS.md`
  - `.claude/skills -> ../.agents/skills`
  - `.claude/agents/`: one symlink per role to `../../.agents/agents/<role>.md`
- Wire the hook to the rules file: `.claude/settings.json` and `.codex/hooks.json` run
  `.agents/hooks/ui-conventions.sh <rules path relative to the checkout>`. A harness with no hook
  system reads the rules file through `AGENTS.md`, nothing to wire.

## 3. Write AGENTS.md

Write it by hand, never a generator. Sections in this order: Hard boundary, Running commands,
Checkouts, How to work, Project references, Git, Project specifics. Keep it under 120 lines: every
line is loaded on every turn.

Then copy the three project references from `references/examples/magento/` and edit them for this
project: `architecture.md`, `testing.md`, `code-standards.md`. The skills read them, and
`AGENTS.md` points at them.

## 4. Verify

- `sync --target <project root>` prints `0 added, 0 changed`.
- The checkout command lists the main checkout.
- The test command's info mode prints what it will run.
- Feed the hook a UI path, expect the rules once, then a reminder. Feed it a non-UI path, expect
  silence.
- Open one harness session at the project root: `AGENTS.md` is loaded and the four skills
  (`plan-create`, `plan-orchestrate`, `project-update`, `project-setup`) are in the catalog.

## Rules

- Never invent project facts: an unknown fact is an open question for the user.
- Never copy the example references unchanged: they describe another project.
