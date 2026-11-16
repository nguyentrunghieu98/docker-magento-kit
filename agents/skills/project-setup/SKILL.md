---
name: project-setup
description: Set up a new project on the kit, or adopt an existing Docker root - place the overlay, write AGENTS.md from the project's own facts, link the harness files and verify. Use when the user says set up this project with the kit.
---

# project-setup

One project, one Docker root. This skill places the overlay and writes the project layer. The
agent root is the main checkout (`<Docker root>/src`): it is the Git repository, the harness is
opened there, and `AGENTS.md`, `.agents/`, `.claude/` and `.scratch/` live there. `bin/` stays in
the Docker root, one level up. Magento is the worked example in `references/examples/magento/`.

## 1. Facts

Ask for what the code cannot answer, then read the rest. Two groups, one message: what changes the
layout (root, repository directory, branch a change starts from, branch a merge request targets)
and what changes the commands (how commands run, the exact test command, the gates, the standard).

## 2. Place the overlay

- Run `sync --target <Docker root> --apply` in the kit, then `sync --target <Docker root>` again:
  it must print `0 added, 0 changed`. The Docker overlay lands in the Docker root, the agent layer
  in `src/.agents/`.
- Create the harness links in the agent root, so one physical copy serves every harness:
  - `CLAUDE.md -> AGENTS.md`
  - `.claude/skills -> ../.agents/skills`
  - `.claude/agents/`: one symlink per role to `../../.agents/agents/<role>.md`
- Keep the layer out of Git unless the project commits it: `git status --short` in `src/` must not
  list `AGENTS.md`, `.agents/` or `.claude/`. Add them to `src/.git/info/exclude` when it does.
- Wire the hooks: `.claude/settings.json` runs `.agents/hooks/ui-conventions.sh <rules path>` and
  `.agents/hooks/guard-paths.sh` on every write, plus `.agents/hooks/kit-drift.sh <kit path>
  [skip path...]` at session start. `.codex/hooks.json` runs the first two. A harness with no hook
  system reads the rules file through `AGENTS.md`, nothing to wire.
- Share the layer with worktrees: `bin/wt create`, `prepare` and `use` link `AGENTS.md`,
  `CLAUDE.md`, `.agents`, `.claude`, `.codex`, `.omp`, `project` and `.scratch` of `src/` into the
  worktree. For every other directory an agent must read there (project docs, a glossary), run
  `git -C <Docker root>/src config --add wt.link <path>`. Ask the user which ones.

## 3. Write AGENTS.md

Write it by hand, never a generator, in the agent root. Sections in this order: Hard boundary,
Running commands, Checkouts, How to work, Project references, Git, Project specifics. Keep it under
120 lines: every line is loaded on every turn. State that the Docker commands run from the Docker
root (`../bin/...` from the agent root).

Then copy the four project references from `references/examples/magento/` and edit them for this
project: `architecture.md`, `testing.md`, `code-standards.md`, `ui-testing.md`. The skills and
roles read them, and `AGENTS.md` points at them. Copy `ui-conventions.md` to the rules path the
hook is wired with, keep the platform rules that apply, and add the project's own design rules
(theme, class prefix, widths, what the design forbids). Ask the user for the UI facts the code
does not hold: the base URL, how to log in, which browser tool takes the screenshots.

## 4. Verify

- `sync --target <Docker root>` prints `0 added, 0 changed`.
- The checkout command lists the main checkout.
- The test command's info mode prints what it will run.
- Feed the hook a UI path, expect the rules once, then a reminder. Feed it a non-UI path, expect
  silence.
- Take one screenshot with the commands of `ui-testing.md`, at each width it lists: the image
  shows the served checkout's home page and the console check prints a count.
- Open one harness session at the agent root: `AGENTS.md` is loaded and the four skills
  (`plan-create`, `plan-orchestrate`, `project-update`, `project-setup`) are in the catalog.
- Create a worktree with the checkout command: `AGENTS.md` and `.agents/skills` resolve inside it,
  and `git status --short` there lists none of the links.

## Rules

- Never invent project facts: an unknown fact is an open question for the user.
- Never copy the example references unchanged: they describe another project.
