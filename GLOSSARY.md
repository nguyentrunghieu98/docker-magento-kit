# magento-docker-kit

A package that ships a Docker environment for a Magento 2 project, together with worktree tools and an agent kit, installed and updated into multiple projects.

## Package and project

**Package**:
The `magento-docker-kit` distribution at a specific semver version, including every file managed by the package.
_Avoid_: kit (when talking about the whole package), template, fork

**Project**:
A specific installation of the package for one Magento codebase, for example Format.
_Avoid_: project instance, site

**Docker root**:
The root directory of a project, where the package is installed and which holds `src/`.
_Avoid_: project root (easily confused with the Magento root)

**Package file**:
A file owned by the package, overwritten on update and tracked by checksum.
_Avoid_: core file, base file

**Project file**:
A file owned by the project, created only once from a template and never overwritten by the package.
_Avoid_: local file, override

**Project profile**:
The set of the profile file, the env files, the Compose override file and the `project/` directory, describing everything specific to a project.
_Avoid_: config, settings

**Profile file**:
The single file holding the values the package reads to configure itself for a project, such as the domain, the remote and the Git branches. It holds no secrets.
_Avoid_: config, `.env`, settings

**Runtime state**:
Local values written by package commands while they run, for example whether Xdebug is on or off. It is not committed and is not part of the project profile.
_Avoid_: state, cache

**Extension point**:
A valid place for a project to change package behavior without editing package files.
_Avoid_: hook, patch, customization

**Update conflict**:
A package file that was hand-edited in the project and differs from both the installed version and the new version.
_Avoid_: merge conflict, diff

**Adopt project**:
Bring an already running Docker root under package management without rebuilding data.
_Avoid_: migrate, import, overwrite

**Cutover**:
The moment the project stack is stopped and started again on the new file set. Before this moment, rolling back does not stop service.
_Avoid_: deploy, go-live, switch-over

**Stray file**:
A file at the Docker root that belongs neither to the package, nor to a template, nor to package state.
_Avoid_: untracked file, junk

## Worktree

**Main checkout**:
The Magento repo at `src/` of the Docker root.
_Avoid_: main worktree, master checkout

**Worktree**:
A secondary checkout of the Magento repo, located at the canonical location in the Docker root.
_Avoid_: lane, slot, sandbox

**Active worktree**:
The single checkout that the stack mounts and serves at a given time.
_Avoid_: active lane, current slot

**Adopt worktree**:
Bring a misplaced worktree to the canonical location so that it is allowed to serve.
_Avoid_: import, migrate

## Agent

**Harness**:
The tool running the agent that reads the project agent kit, for example Claude Code, Codex or DSH.
_Avoid_: tool, IDE, client

**Agent kit**:
The part of the package that provides Magento knowledge to the agent: how to run commands, verification gates, Git conventions and hard boundaries. It does not define the workflow.
_Avoid_: workflow kit, agent workflow

**Process skill set**:
The set of skills installed into the harness that decides the work sequence, such as grill, spec, ticket, implement and review. It lives outside the package.
_Avoid_: stage, S0 to S6

**Role**:
A named subagent, defined by its permission boundaries rather than by the model that runs it.
_Avoid_: worker, teammate, persona

**Model tier**:
The abstract capability level a role needs (`fast`, `default`, `deep`), mapped to a real model per harness.
_Avoid_: tier, model name
