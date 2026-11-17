# Merge request body

Write the body in the project's language (see `Language` in `AGENTS.md`). Keep commands, paths and
module names as they are. Do not open the MR or suggest a merge while a required section is missing.
A section that does not apply says `N/A` with a one-line reason; never delete it.

## Always required

| Section | Content |
| --- | --- |
| Business issue | What the customer or operator cannot do today, with the ticket or note |
| Modules changed | Paths under `app/code/...`, theme or config files |
| Approach | The minimal change and why this seam |
| Verification evidence | Table Gate, Command, Result: the gates of `testing.md` run after the last edit |
| Deploy notes | `setup:upgrade`, `setup:di:compile`, static content, queue/consumer restart, cache flush: yes or no each. Every `yes` gets a `Command:` line |
| Rollback | How to undo. Default: revert the MR and deploy the previous SHA |

## Required by condition

| When the MR... | Add |
| --- | --- |
| changes storefront or admin UI | screenshots at the project's widths, forbidden details removed |
| has a schema change, data patch or enables a module | data plan: DB dump command, when `setup:upgrade` runs, why a code revert is not enough |
| touches payment, webhook, RMA, inventory or order sync | step-by-step rollback and log checks (file, keyword, expected result) |
| adds a queue, consumer or cron | its name, how to restart it, how to confirm it ran |
| adds a one-off script | data scope, the copy it was tried on, how to undo the data change |
| has a gate that could not run | a `Skipped` row with the real reason, never an empty cell |
