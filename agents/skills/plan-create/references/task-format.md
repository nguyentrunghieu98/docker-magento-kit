# Plan and task format

A plan lives in `.scratch/<feature>/` at the agent root. It is working state: never committed.
After the merge request is merged, delete `spec.md`, `critique.md` and `issues/`, and leave
`evidence/` where it is.

```
.scratch/<feature>/
├── spec.md              goal, scope, success criteria, task table, dependency graph
├── critique.md          written by devils-advocate
├── issues/NN-slug.md    one task per file, numbered from 01
└── evidence/            gate output, UI screenshots and backups worth keeping after the merge
```

## spec.md

```markdown
# <Feature>

Status: draft | approved
Branch: (written after approval, when the branch exists)

## Goal
## Scope
In: ...  Out: ...
## Success criteria
## Decisions
- <decision> (default unless the user said otherwise)
## Open questions
- [Critical|Important] <question>
## Tasks
| # | Task | Blocked by | Files | Serial |
## Dependency graph
01 ─┬─> 03
02 ─┘
```

## issues/NN-slug.md

```markdown
# NN: <what the task delivers>

Status: ready-for-agent
Blocked by: 01, 02
Files: <path>, <path>
Serial: no
Retry: 0

## Description
Two to four sentences: what and why.

## Context
- Files to read, the pattern to follow, the module that owns the behavior.

## Requirements (test names)
- [ ] `testSavesShippingAddressAsDefaultWhenCustomerHasNone`
- [ ] `testKeepsExistingDefaultWhenFlagIsOff`

## Implementation notes
(written by the worker)

## Comments
```

## Fields

- `Status`: `ready-for-agent` → `in-progress` → `done` | `blocked`. Before execution a task may
  also be `needs-info` or `ready-for-human` (the triage labels of the project).
- `Blocked by`: task numbers, or `None`. Must form a graph without cycles.
- `Files`: every file the task creates or edits, test files included, relative to the root of the
  checkout, not to the directory above it. Two tasks whose `Files` overlap never run at the same
  time.
- `Serial: yes`: the task touches a schema, a data patch, module enabling, a queue or another
  shared resource. It runs alone, and only after the user approves it.
- `Retry`: failed attempts so far. At 3 the task becomes `blocked`.
- Requirements: 3 to 7 test names per task. Each one is the exact name of the test method that
  proves it, so the project's test runner can select it by name and grep can find it. A requirement
  that cannot be a unit test says so, `- [ ] manual: <step and expected result>` or
  `- [ ] gate: <gate>`, and does not count toward the 7. Gates that cover the whole change belong in
  `spec.md`, not in a task.
- A ticked requirement carries the real result line of the command that proved it.

## UI tasks

What a user sees cannot be a unit test name. It is a `ui:` requirement, proved by a screenshot:

```markdown
## Requirements (UI)
- [ ] ui: /customer/account/create @ 390 | the form is one column and nothing scrolls sideways
- [ ] ui: /customer/account/create @ 1440 | an empty submit shows the error under each field
- [ ] ui: admin sales/order/view, any order @ 1440 | the "Complaint" button opens a modal with a title and two buttons
```

- Form: `ui: <page> @ <width> | <what must be visible>`. The page is a path, or the screen and the
  steps to reach it. The width is in CSS pixels, from the project's UI testing reference. What must
  be visible is one observation a person can confirm on the screenshot, never "looks good".
- A task with a `ui:` requirement is a UI task: 1 to 7 `ui:` requirements and no test names. Put
  the PHP behavior behind the screen in its own task and make the UI task `Blocked by` it.
- `Files` lists the view files: layout, templates, styles, scripts, UI component XML.
- A UI task runs with the `ui-worker` role, on the served checkout, and alone: one checkout is
  served at a time.
- A ticked `ui:` requirement carries the screenshot path in `evidence/`, named
  `NN-<requirement number>-<width>.png`, and the console errors the change added, for example
  `evidence/03-1-390.png, console: 0 new errors`.
