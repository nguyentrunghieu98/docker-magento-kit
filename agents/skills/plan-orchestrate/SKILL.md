---
name: plan-orchestrate
description: Execute an approved plan from .scratch/<feature>/ - run its tasks in dependency order with tdd-worker agents, run the gates, review the diff and commit. Use when the user says to run, execute or implement a plan.
---

# plan-orchestrate

Runs a plan that `plan-create` produced and the user approved. The task format is in
`../plan-create/references/task-format.md`. Commands and gates come from the project references
`AGENTS.md` names. Git rules come from `AGENTS.md`.

## 1. Check

- `spec.md` says `Status: approved` and has a `Branch:` line. No open Critical question.
- The checkout of that branch exists (use the command `AGENTS.md` names). Do not switch the
  served checkout unless a gate needs it.
- Run the project's test runner in its info or dry-run mode when it has one, and keep the output
  for the workers.

## 2. Task loop

A task is **ready** when its `Status` is `ready-for-agent`, every `Blocked by` task is `done`,
it is not `Serial: yes` unless the user approved it, and its `Files` do not overlap a task in progress.

Repeat until no task is ready and none is in progress:

- Set each ready task to `in-progress` and start one `tdd-worker` per task. Run them in parallel
  when the harness has background agents, otherwise one after another. A `Serial: yes` task runs
  alone. Start a role by its agent type when the harness has one (Claude Code, `.claude/agents`),
  otherwise read `.agents/agents/<role>.md`, drop the frontmatter, and pass the body plus the task
  details to the subagent tool.
- Give each worker everything it needs, it does not see this conversation: the project root, the
  checkout name and path, the task file path, the test-runner output, and the full text of the
  project references the task needs.
- On `TASK_COMPLETE`: check the task file has every requirement ticked with a real result line,
  then set `Status: done`.
- On `TASK_FAILED: <reason>`: add the reason under `## Comments`, increment `Retry`. Below 3, set
  it back to `ready-for-agent`. At 3, set `blocked` and keep going with other tasks. You may
  suggest `diagnosing-bugs` to the user for a blocked task.
- A test run that exits 2 is a prerequisite error (for example a lockfile mismatch), not a
  failed attempt: stop that task and report it to the user, do not count a retry.

When nothing is ready and tasks remain: print `TASKS_BLOCKED` with each blocked task and its
reason, and stop.

## 3. Standards (optional)

Only when `AGENTS.md` turns `standards-enforcer` on: run it once on the whole diff.

## 4. Final gates

Once, in order, after the last edit. Use the gate matrix in the project's testing reference for
every surface the diff touches, including the full test suite of every touched module. A gate
that needs the served checkout asks first before switching it, and a gate that writes shared
state is announced before it runs. Write one line per gate to `evidence/gates.md`.

## 5. Review

Run `diff-reviewer` on the diff from the merge base with the target branch. For each Critical or
High finding, add a fix task (`ready-for-agent`, `Blocked by: None`) and go back to step 2.
Any fix makes earlier evidence stale: run step 4 again before committing.

## 6. Commit

- Stage specific paths only, never `git add -A`, never `.scratch/`.
- Message and published-text checks follow `AGENTS.md` (commit format, `publishing.md`).
- Show the user the commit, the gate lines and the review result.

## 7. Push and merge request

Only after the user confirms, with the command in `AGENTS.md`. Stop there: a human deploys.
After the merge, delete `spec.md`, `critique.md` and `issues/`, keep `evidence/`.
