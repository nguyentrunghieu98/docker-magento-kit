---
name: plan-create
description: Plan a feature or a change across several files with the user, as tasks whose requirements are test names, critiqued before any code. Use when the user asks for a feature, an enhancement or a multi-file change that `AGENTS.md` sends to the plan lane. Not for a quick-lane fix, a one-line fix, a question or documentation.
---

# plan-create

Planning is done with the user. Execution is `plan-orchestrate`. This skill writes no production
code and creates no branch until the user approves the plan.

Read first: `AGENTS.md`, then the project references it names. If `AGENTS.md` defines a quick lane
and the change fits it (small, no heavy trigger) and the user did not ask for a plan, stop: say it
fits the quick lane and work it there. The number of files alone never decides the lane. The plan format is in
`references/task-format.md` of this skill.

## Steps

1. **Explore.** Read the code that owns the behavior. When the scope is wide, send
   `code-researcher` with a precise question. List what already exists against the request, and
   the design axes the request leaves open.

2. **Ask.** Two groups, in one message:
   - *must answer*: questions that change scope, data, schema or architecture;
   - *default unless you say otherwise*: each with the default you will use.
   Wait for the answers to the first group. Do not ask what the code can answer.

3. **Write `spec.md`** in `.scratch/<feature>/` with `Status: draft`.

4. **Split into tasks** in `issues/NN-slug.md`:
   - each task is one observable piece of behavior with 3 to 7 requirements written as test names;
   - declare `Blocked by` and `Files` completely, including test files;
   - mark `Serial: yes` for schema, data patch, module enabling, queue or other shared state;
   - check the dependency graph has no cycle and that no two independent tasks share a file
     (make one block the other instead);
   - fill the task table and the dependency graph in `spec.md`.

5. **Critique.** Start the `devils-advocate` role on the plan directory. It writes `critique.md`
   and fixes Critical and Important findings in the task files. Read what it changed.

6. **Approve with the user.** Present the goal, the task table, the graph, the remaining open
   questions and what `devils-advocate` changed. You may suggest the `grilling` skill. Only after
   an explicit yes:
   - set `Status: approved` in `spec.md`;
   - create the branch with the worktree command in `AGENTS.md` and write it on the `Branch:` line;
   - tell the user the next step is `plan-orchestrate`.

## Rules

- Never `git checkout -b` or `git worktree add`: the branch comes from the command in `AGENTS.md`.
- Never write production code or tests here. The plan is the output.
- Never commit anything under `.scratch/`.
- A requirement that is not a test name is a manual step or a named gate, written as such.
