# Agent instructions: {{KIT_PROJECT_NAME}}

Magento 2 runs in Docker. The Docker root is `{{KIT_ROOT}}`, Magento code is in `src/`, the site is `https://{{KIT_DOMAIN}}`.

## Hard boundary

- Stop at a `<type>/<slug>` branch pushed to `{{KIT_GIT_REMOTE}}` with a merge request targeting `{{KIT_GIT_TARGET_BRANCH}}`. A human deploys.
- `{{KIT_GIT_BASE_BRANCH}}` and `{{KIT_GIT_TARGET_BRANCH}}` are read-only: no push, no force-push into these two branches.
- Do not deploy, do not SSH into production, do not write production data.
- `vendor/`, `generated/`, `pub/static/` are output: edit the source and let the commands regenerate them.
- Secrets (`auth.json`, `env/*.env`, tokens) stay out of commits.

## Running commands

The host has no PHP. Every PHP and Magento command runs through the Docker root:

```bash
cd {{KIT_ROOT}} && bin/cli <command>        # or bin/magento, bin/composer
```

If the containers are stopped, run `bin/start`. Git runs in the branch checkout, `src/` or `.worktrees/<dir>`.

## Worktree

- Create one with `bin/wt create <type>/<slug>`, the worktree lives in `.worktrees/<dir>`, the branch is cut from `{{KIT_GIT_REMOTE}}/{{KIT_GIT_BASE_BRANCH}}`.
- One stack, one DB, one `vendor/` for every worktree. Run `bin/wt status` before a Magento command, switch with `bin/wt use <name>`.
- `bin/wt` is the only way to create and switch worktrees: `git worktree add` and hand-editing `.active-src` make the stack mount the wrong place.

## Knowledge

- Skill `magento-workflow`: load it when running a gate, committing, creating an MR or switching worktree.
- `project/agent/references/`: read when the work touches modules, the deploy hand-off or project-specific conventions.
