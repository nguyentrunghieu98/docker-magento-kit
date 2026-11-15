# Testing and TDD

Rules for a change that alters behavior. `gates.md` still decides which gates apply, this file decides how the unit test gate is earned and what evidence counts.

## RED, GREEN, REFACTOR

Work one behavior at a time. A behavior is something a user, an admin or a caller can observe, not a function name.

1. **RED.** Write the test first. Run it. It must fail because the behavior is missing or wrong. A failure from a missing dependency, a broken bootstrap or a typo is not RED, fix that and run again. A report from the user or the parent that already shows the test failing for the right reason counts as RED, do not rerun it only to watch it fail.
2. **GREEN.** Change the least code that makes the test pass. Run the target test, then the unit suite of the module.
3. **REFACTOR.** Clean structure without changing behavior. Run the affected tests again after each change.

Choose the smallest test that observes the behavior. Reuse an existing test when it already proves the requirement and say so, do not edit code or invent a failure to force a RED. Do not test a function name, a message wording, source text or plain wiring.

TDD is N/A for documentation, configuration with no executable behavior and generated files. Write `TDD N/A` with the reason in the evidence, never leave it blank.

If the harness keeps test execution with the parent, hand over a checkpoint with the test only, take the RED result from the parent, then write the implementation. Do not skip RED to get around that limit.

## Commands

Run the unit tests on the checkout the stack serves, after `bin/wt status` shows the right branch:

```bash
bin/test/unit <test-path>
```

A project may ship an isolated runner for worktrees the stack does not serve. When `project/agent/references/` documents one, use it, with its serial and parallel modes, as described there.

## When to run in parallel

- **RED and debugging: serial.** It accepts `--filter`, the output is in order and a failure points at one test.
- **GREEN and final verification: parallel,** when the runner offers it, for unit tests that need no shared state. A parallel mode usually takes a file or a directory instead of `--filter`.
- **Never in parallel:** integration tests, anything that touches the database, Redis, a queue, an external API, the browser or a fixed file path outside the temp directory the bootstrap provides.
- A suite that passes serial and fails parallel is a FAIL of the parallel gate. Find the shared state and fix it, or record the suite as serial only with the evidence. Never delete a test to get a green run.
- Do not claim a speed gain without a measurement. A small suite can be slower in parallel.

## What to run when

- A worker runs the tests of its own behavior. The final owner runs the whole `Test/Unit` of every module the change touches, and the suites of known callers. Do not run the whole Magento tree out of habit.
- Do not start several full runs at once. They compete for the same CPU and the same sandbox.
- A test result belongs to the code it ran against. After any later edit, including one from a formatter or a reviewer, run it again before handoff.

## Evidence

One row per requirement:

```
requirement | test | RED command and result | GREEN command and result | final verification
```

Paste the real command and the real result line. Do not report a PASS from memory or from a run on another checkout. A gate that did not run is listed as not checked with the reason.
