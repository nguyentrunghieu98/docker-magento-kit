# magento-docker-kit

[English](README.md) | [Tiếng Việt](README.vi.md)

An installable Docker environment for Magento 2 projects — a pinned snapshot of
[markshust/docker-magento](https://github.com/markshust/docker-magento) plus prebuilt PHP images,
a single-stack worktree tool, and a small knowledge kit for coding agents.

![test](https://github.com/nguyentrunghieu98/docker-magento-kit/actions/workflows/test.yml/badge.svg)

## What you get

- A Docker root that runs Magento 2 with app, php-fpm, MariaDB or MySQL, Redis/Valkey, OpenSearch, RabbitMQ and a local mail catcher.
- Prebuilt PHP 8.2, 8.3 and 8.4 images with an optional Xdebug variant, published to GHCR.
- `bin/wt`, which keeps one stack and one database while you switch between Git worktrees.
- A project profile (`project/profile.env`) that holds everything project-specific, so the same package serves many projects.
- Three-way updates with checksummed manifests and a backup path, plus `adopt` for roots that already run.
- An agent kit: `AGENTS.md`, `CLAUDE.md`, three roles and the `magento-workflow` skill, installed for both Claude Code and Codex.

## Requirements

- Docker Engine with Compose v2, at least 6 GB of memory available to Docker.
- `bash`, `git`, `curl`, and `tar`.
- Magento credentials for `bin/download` when installing from scratch (`auth.json` or `bin/setup-composer-auth`).

## Install a new project

From a checkout of this package (works without a published tag):

```bash
git clone https://github.com/nguyentrunghieu98/docker-magento-kit.git
cd docker-magento-kit
./install.sh new ../shop --source . --domain shop.test
```

From a published release tag:

```bash
curl -fsSL https://raw.githubusercontent.com/nguyentrunghieu98/docker-magento-kit/v1.0.0/install.sh \
  | bash -s -- new shop --domain shop.test
```

`install.sh new` writes package files and templates into the target directory and changes nothing else.
Pass `--setup --magento 2.4.7-p3` to run `bin/download` and `bin/setup` afterwards, or run them yourself:

```bash
cd ../shop
bin/download community 2.4.7-p3
bin/setup
bin/start
```

Open `https://shop.test` after adding the host entry (see `bin/setup-domain` and `bin/setup-ssl`).

## Adopt an existing Docker root

`adopt` turns a running Docker root into a package-managed one without touching containers or data.
Every difference is treated as a conflict, nothing is written unless the plan is clean or `--force` is given.

```bash
./install.sh adopt ../existing-site --dry-run   # print the plan only
./install.sh adopt ../existing-site             # write when there is no conflict
./install.sh adopt ../existing-site --force     # back up conflicts to .kit/backup/<timestamp>/
```

## Update an installed project

Each root records the installed manifest in `.kit/`. Updates are three-way: local file, installed checksum and new checksum.

```bash
cd shop
bin/self-update --dry-run      # print the plan
bin/self-update                # apply a clean update
bin/self-update --force        # back up conflicts, then overwrite
bin/self-update --version v1.2.0
```

A conflict stops the update before writing. Files the project owns (profile, env files, `project/`) are never overwritten.

## Project profile

`project/profile.env` is the only place for project settings. Secrets stay in `env/*.env`, never in the profile.

| Key | Default | Meaning |
|---|---|---|
| `KIT_PROJECT_NAME` | directory name | Compose project name, also prefixes containers and volumes |
| `KIT_DOMAIN` | required | Public host name, used by `bin/setup`, `bin/setup-domain`, `bin/setup-ssl` |
| `KIT_GIT_REMOTE` | required | Remote used by `bin/wt` and the agent kit |
| `KIT_GIT_BASE_BRANCH` | required | Base branch for new worktrees, never pushed |
| `KIT_GIT_TARGET_BRANCH` | required | Merge request target branch, never pushed |
| `KIT_PHP_VERSION` | `8.3` | PHP image tag, one of `8.2`, `8.3`, `8.4` |
| `KIT_PHP_VARIANT` | empty | Runtime Xdebug variant, managed by `bin/xdebug` |
| `KIT_DB_ENGINE` | `mariadb` | `mariadb` or `mysql`, selects the Compose overlay |
| `KIT_DB_VERSION` | `11.4` / `8.4` | Database image version for the selected engine |
| `KIT_REDIS_IMAGE` | `valkey/valkey:8.1-alpine` | Redis-compatible image |
| `KIT_HTTP_PORT` / `KIT_HTTPS_PORT` | `80` / `443` | Exposed web ports |
| `KIT_DB_PORT` / `KIT_REDIS_PORT` | `3306` / `6379` | Exposed service ports |
| `KIT_OPENSEARCH_PORT` / `KIT_OPENSEARCH_HEAP` | `9200` / `1g` | Search port and JVM heap |
| `KIT_RABBITMQ_PORT` / `KIT_RABBITMQ_MANAGEMENT_PORT` | `5672` / `15672` | Queue ports |
| `KIT_STATIC_LOCALES` | `en_US` | Locales for `bin/deploy` |
| `KIT_COMPOSE_PROFILES` | empty | Compose profiles to enable, for example `cloudflared` |
| `KIT_MODEL_<HARNESS>_<TIER>` | package table | Overrides one model cell for the agent kit |

## Worktrees

One Docker root serves exactly one checkout at a time. `bin/wt` creates worktrees in `.worktrees/`,
switches the single stack between them, and keeps one database, one `vendor/` and one `pub/media/`.

```bash
bin/wt create feat/checkout-rework   # from <remote>/<base branch>
bin/wt use feat-checkout-rework      # stack now serves that worktree
bin/wt status                        # what is being served, plus container state
bin/wt list
bin/wt prepare                       # copy core files missing from a fresh checkout
bin/wt adopt ../path/to/wrong-place  # move a stray worktree into .worktrees/
bin/wt prune --dry-run               # review merged and review worktrees, then prune
bin/wt doctor                        # compare phpfpm mounts with .active-src and check config
```

Only `app` and `phpfpm` are recreated when switching. The database is never touched.

## Agent kit

`bin/agent install` writes the shared guidance and adapters into the current directory:

- `AGENTS.md` from the package template plus profile values, with up to 20 extra project lines from `project/agent/AGENTS.project.md`.
- `CLAUDE.md` that imports `AGENTS.md`.
- `.claude/skills/` and `.agents/skills/`, including the `magento-workflow` skill and its references for gates, Git/MR conventions and worktrees.
- Roles for Claude Code in `.claude/agents/` and for Codex in `${CODEX_HOME:-~/.codex}/agents/magento-*.toml`.

| Role | Permission | Model tier |
|---|---|---|
| `magento-researcher` | read-only | fast |
| `magento-developer` | write | deep |
| `magento-reviewer` | read-only | default |

Model tiers come from the package table. Override one cell in `project/profile.env`, for example
`KIT_MODEL_CODEX_DEEP=deepseek-v4-pro:max` or `KIT_MODEL_CLAUDE_FAST=inherit`.
Codex reads agents only from its own home, so adapters are installed there with a `magento-` prefix.

## PHP images

Images live at `ghcr.io/nguyentrunghieu98/magento-php` with tags `<php>-fpm-<n>` and `<php>-fpm-<n>-xdebug`.
The `<n>` counter matches `images/php/IMAGE_VERSION`. The Compose file pins that counter, so bumping the
image directory means bumping the version and the pin together. Build locally with `docker build` in
`images/php`, or let the `image-php` workflow publish new tags.

## Cloudflare tunnel

Set `KIT_COMPOSE_PROFILES=cloudflared` in the profile, put the tunnel token in `env/cloudflare.env`,
and manage ingress in the Cloudflare dashboard. See [dist/files/docs/cloudflared.md](dist/files/docs/cloudflared.md).

## Repository layout

```text
install.sh              installer: new, adopt
dist/files/             files owned by the package (copied to the Docker root)
dist/templates/         project files created once (profile, env files, .gitignore)
dist/manifest           checksums and modes for dist/files
images/php/             Dockerfile, pinned PHP versions, S3 checks
tests/                  bash test suite, no network required
tools/release           manifest, check and release commands
.github/workflows/      CI: tests, shellcheck, manifest, PHP images
```

## Development

```bash
bash tests/run-all.sh          # all suites, no network
tools/release manifest         # regenerate dist/manifest
tools/release check            # fail when dist/files and the manifest disagree
shellcheck -x install.sh tools/release tests/*.sh
```

Each test file is a standalone suite. `bin/wt` and installer tests build a sandbox Docker root in a
temporary directory and use a fake `docker` that records calls.

## Release

`tools/release vX.Y.Z` regenerates the manifest, records the version tag and prints the release steps.
The `test` workflow runs on every push and checks manifest, tests and shellcheck. The `image-php`
workflow builds PHP images when `images/php/**` changes and refuses to overwrite existing tags.

## License

MIT. The upstream snapshot, its tag and commit are recorded in [NOTICE](NOTICE).
