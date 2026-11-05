#!/usr/bin/env bash
# install.sh - install magento-docker-kit into a Docker root.
#
#   curl -fsSL https://raw.githubusercontent.com/nguyentrunghieu98/magento-docker-kit/main/install.sh \
#     | bash -s -- new <dir> [--version vX.Y.Z]
#
#   install.sh new <dir> [--domain x.test] [--setup --magento <version>] [--version vX.Y.Z] [--source <directory|tarball>]
#   install.sh adopt <dir> [--dry-run] [--force] [--version vX.Y.Z] [--source <directory|tarball>]
#
# Without --source it downloads the tarball for the tag (the latest by default), so
# the target machine needs no git. --source is for offline runs (CI and tests).
# Environment variable: KIT_REPO=<owner>/<repo> changes the source repo.
set -Eeuo pipefail

KIT_REPO="${KIT_REPO:-nguyentrunghieu98/magento-docker-kit}"
WORK=''

die() {
  printf 'install.sh: %s\n' "$*" >&2
  exit 1
}

usage() {
  cat <<'EOF'
Usage:
  install.sh new <dir> [--domain x.test] [--setup --magento <version>] [--version vX.Y.Z] [--source <directory|tarball>]
  install.sh adopt <dir> [--dry-run] [--force] [--version vX.Y.Z] [--source <directory|tarball>]

  new <dir>          write package files and templates into <dir>, touch nothing else
  adopt <dir>        turn a running Docker root into a package-managed one, leave the stack alone
  --dry-run          (adopt) print the plan only, write nothing
  --force            (adopt) back up conflicting files to .kit/backup/<timestamp>/ then overwrite
  --domain x.test    fill KIT_DOMAIN in the newly created project/profile.env
  --setup            after install, run bin/download then bin/setup (needs --domain and --magento)
  --magento <ver>    Magento version for bin/download, only used together with --setup
  --version vX.Y.Z   pin the version, defaults to the latest tag
  --source <source>  use the package checkout directory or a tarball, no network needed
EOF
}

cleanup() {
  if [[ -n "$WORK" && -d "$WORK" ]]; then
    rm -rf "$WORK"
  fi
  return 0
}
trap cleanup EXIT

# Find the package root (the one holding dist/) inside an extracted directory.
find_kit_root() {
  local dir="$1" sub
  if [[ -d "$dir/dist" ]]; then
    printf '%s\n' "$dir"
    return 0
  fi
  for sub in "$dir"/*/; do
    if [[ -d "${sub}dist" ]]; then
      printf '%s\n' "${sub%/}"
      return 0
    fi
  done
  return 1
}

extract_tarball() {
  local tarball="$1" out="$2"
  mkdir -p "$out"
  tar -xzf "$tarball" -C "$out" || die "cannot extract $tarball"
}

latest_tag() {
  local json
  json="$(curl -fsSL "https://api.github.com/repos/$KIT_REPO/tags?per_page=100")" || die 'cannot fetch the tag list'
  printf '%s\n' "$json" \
    | grep -Eo '"name"[[:space:]]*:[[:space:]]*"v[0-9]+\.[0-9]+\.[0-9]+"' \
    | grep -Eo 'v[0-9]+\.[0-9]+\.[0-9]+' \
    | sort -t. -k1.2,1n -k2,2n -k3,3n \
    | tail -n 1
}

# Set KIT_ROOT (the package directory) and VERSION.
resolve_source() {
  local source="$1" version="$2"
  WORK="$(mktemp -d "${TMPDIR:-/tmp}/kit-install.XXXXXX")"
  if [[ -n "$source" ]]; then
    if [[ -d "$source" ]]; then
      KIT_ROOT="$(cd "$source" && pwd -P)"
    elif [[ -f "$source" ]]; then
      extract_tarball "$source" "$WORK/src"
      KIT_ROOT="$(find_kit_root "$WORK/src")" || die "tarball does not contain dist/: $source"
    else
      die "--source does not exist: $source"
    fi
    [[ -d "$KIT_ROOT/dist/files" && -f "$KIT_ROOT/dist/manifest" ]] || die "source is missing dist/files or dist/manifest: $source"
    if [[ -z "$version" ]]; then
      version="$(tr -d '[:space:]' < "$KIT_ROOT/dist/version" 2>/dev/null || true)"
      [[ -n "$version" ]] || version='dev'
    fi
  else
    command -v curl >/dev/null 2>&1 || die 'curl is required'
    if [[ -z "$version" ]]; then
      version="$(latest_tag)"
      [[ -n "$version" ]] || die 'the repo has no release tag yet'
    fi
    curl -fsSL "https://github.com/$KIT_REPO/archive/refs/tags/$version.tar.gz" -o "$WORK/kit.tar.gz" \
      || die "cannot download tag $version"
    extract_tarball "$WORK/kit.tar.gz" "$WORK/src"
    KIT_ROOT="$(find_kit_root "$WORK/src")" || die "tarball $version does not contain dist/"
    [[ -f "$KIT_ROOT/dist/manifest" ]] || die "tag $version is missing dist/manifest"
  fi
  VERSION="$version"
  [[ -f "$KIT_ROOT/dist/files/bin/lib/kit-core.sh" ]] || die "source is missing bin/lib/kit-core.sh"
  # shellcheck source=dist/files/bin/lib/kit-core.sh
  source "$KIT_ROOT/dist/files/bin/lib/kit-core.sh"
}

cmd_new() {
  local target="$1" domain="${2:-}" setup="${3:-0}" magento="${4:-}" sum mode path existing=() rel
  [[ -n "$target" ]] || die 'missing <dir>, for example: install.sh new my-shop'
  if [[ -e "$target" && ! -d "$target" ]]; then
    die "$target already exists and is not a directory"
  fi

  if [[ "$setup" == 1 ]]; then
    [[ -n "$magento" ]] || die '--setup needs --magento <version>, for example: --magento 2.4.7'
    [[ -n "$domain" ]] || die '--setup needs --domain, because bin/setup takes the domain from KIT_DOMAIN'
  fi

  verify_source "$KIT_ROOT"

  if [[ -d "$target" ]]; then
    if [[ -e "$target/.kit" ]]; then
      existing+=('.kit')
    fi
    while read -r sum mode path; do
      [[ -n "$path" ]] || continue
      if [[ -e "$target/$path" || -L "$target/$path" ]]; then
        existing+=("$path")
      fi
    done < "$KIT_ROOT/dist/manifest"
  fi
  if [[ "${#existing[@]}" -gt 0 ]]; then
    printf 'install.sh: %s already has package files:\n' "$target" >&2
    printf '  %s\n' "${existing[@]:0:5}" >&2
    [[ "${#existing[@]}" -le 5 ]] || printf '  ... and %d more files\n' "$((${#existing[@]} - 5))" >&2
    printf "To turn the existing project into a package-managed one, use: install.sh adopt %s\n" "$target" >&2
    exit 1
  fi

  mkdir -p "$target"
  target="$(cd "$target" && pwd -P)"

  # Share the planning core with bin/self-update: the old manifest is empty, so every
  # package file is a "write" and a template is created only when absent.
  local profile_created=0 plan="$WORK/plan"
  [[ -e "$target/project/profile.env" ]] || profile_created=1
  kit_plan "$target" '' "$KIT_ROOT/dist/manifest" "$KIT_ROOT/dist/templates" > "$plan"
  kit_apply "$target" "$plan" "$KIT_ROOT/dist/files" "$KIT_ROOT/dist/templates" 0 "$target/.kit/backup"

  # --domain only fills the profile file just created from the template, it never edits an existing file.
  if [[ -n "$domain" && "$profile_created" -eq 1 ]]; then
    sed -i.bak "s|^KIT_DOMAIN=.*|KIT_DOMAIN=$domain|" "$target/project/profile.env"
    rm -f "$target/project/profile.env.bak"
  fi

  # Package state is written last: the manifest, then the version.
  kit_write_state "$target" "$KIT_ROOT/dist/manifest" "$VERSION"

  if [[ "$setup" == 1 ]]; then
    printf 'Installed magento-docker-kit %s into %s, running bin/download then bin/setup\n' "$VERSION" "$target"
    (cd "$target" && bin/download community "$magento" && bin/setup) || die "bin/download or bin/setup failed, fix it and rerun each command in $target"
    return 0
  fi

  cat <<EOF
Installed magento-docker-kit $VERSION into $target

Next steps:
  cd $target
  bin/download community 2.4.7      # download Magento into src/
  bin/setup magento.test            # bring the stack up and install Magento
EOF
}

print_adopt_plan() {
  local plan="$1" action mode path n label
  printf 'Adopt plan (%s)\n' "$VERSION"
  while IFS=$'\t' read -r action mode path; do
    case "$action" in
      write) label='new file' ;;
      conflict) label='CONFLICT' ;;
      template) label='create from template' ;;
      *) continue ;;
    esac
    printf '  %s: %s\n' "$label" "$path"
    if [[ "$action" == conflict ]]; then printf '                   hint: %s\n' "$(kit_conflict_hint "$path")"; fi
  done < "$plan"
  n="$(kit_plan_count "$plan" skip)"
  printf '  (%s files with identical content, will be written to the manifest)\n' "$n"
}

print_adopt_conflict_diffs() {
  local plan="$1" target="$2" action mode path
  while IFS=$'\t' read -r action mode path; do
    [[ "$action" == conflict ]] || continue
    printf '\n--- conflict: %s\n' "$path"
    if [[ -f "$target/$path" && ! -L "$target/$path" ]]; then
      diff -u --label "local/$path" --label "$VERSION/$path" "$target/$path" "$KIT_ROOT/dist/files/$path" || true
    else
      printf '(local is not a regular file)\n'
    fi
  done < "$plan"
}

# Adopt a running Docker root. Never calls docker, never touches src/, .worktrees/
# or .active-src. With conflicts and no --force it writes nothing (not even the
# manifest), so you can rerun as many rounds as needed until the conflicts are gone.
cmd_adopt() {
  local target="$1" dry="${2:-0}" force="${3:-0}" plan="$WORK/plan" strays guesses="$WORK/guesses" profile_created=0 conflicts backup
  [[ -n "$target" ]] || die 'missing <dir>, for example: install.sh adopt ~/Sites/shop'
  [[ -d "$target" ]] || die "$target is not a directory. For a new project use: install.sh new $target"
  target="$(cd "$target" && pwd -P)"
  [[ -f "$target/compose.yaml" ]] || die "$target has no compose.yaml, so it does not look like a Docker root. For a new project use: install.sh new $target"
  if [[ -e "$target/.kit/manifest" ]]; then
    die "$target is already package-managed (it has .kit/manifest). Update it with: bin/self-update"
  fi

  verify_source "$KIT_ROOT"
  [[ -e "$target/project/profile.env" ]] || profile_created=1

  # No old manifest yet: a file with different content is a conflict, an identical one is a skip.
  kit_plan "$target" '' "$KIT_ROOT/dist/manifest" "$KIT_ROOT/dist/templates" > "$plan"
  print_adopt_plan "$plan"

  conflicts="$(kit_plan_count "$plan" conflict)"
  if [[ "$conflicts" -gt 0 ]]; then print_adopt_conflict_diffs "$plan" "$target"; fi

  strays="$(kit_stray_files "$target" "$KIT_ROOT/dist/manifest" "$KIT_ROOT/dist/templates")"
  if [[ -n "$strays" ]]; then
    printf '\nStray files (not owned by the package, reported only, never deleted):\n'
    printf '%s\n' "$strays" | sed 's/^/  /'
  fi

  : > "$guesses"
  if [[ "$profile_created" -eq 1 ]]; then
    kit_adopt_guess "$target" > "$guesses"
    printf '\nproject/profile.env will be created with keys guessed from files (KIT_DOMAIN left empty):\n'
    sed 's/^/  /' "$guesses"
  fi

  if [[ "$conflicts" -gt 0 && "$force" -eq 0 ]]; then
    printf '\ninstall.sh: %s update conflicts, nothing written yet. Move the customizations into extension points and rerun adopt, or use --force to back up and overwrite.\n' "$conflicts" >&2
    exit 1
  fi
  if [[ "$dry" -eq 1 ]]; then
    printf '\nDry run (--dry-run), nothing written.\n'
    exit 0
  fi

  backup="$target/.kit/backup/$(date +%Y%m%d-%H%M%S)"
  kit_apply "$target" "$plan" "$KIT_ROOT/dist/files" "$KIT_ROOT/dist/templates" "$force" "$backup"
  if [[ "$profile_created" -eq 1 && -s "$guesses" ]]; then
    kit_profile_apply_guesses "$target/project/profile.env" "$guesses"
  fi
  kit_write_state "$target" "$KIT_ROOT/dist/manifest" "$VERSION"

  printf '\nAdopted %s into package %s. The stack, src/ and .worktrees/ were left alone.\n' "$target" "$VERSION"
  if [[ "$conflicts" -gt 0 ]]; then printf 'Backed up %s conflicting files into %s\n' "$conflicts" "${backup#"$target"/}"; fi
  cat <<EOF

Next steps:
  - check project/profile.env, fill KIT_DOMAIN and every "adopt guess" line
  - Compose files may have changed: compare bin/docker-compose config before bin/restart (adopt does not restart the stack)
EOF
}

main() {
  local cmd='' dir='' version='' source='' domain='' setup=0 magento='' dry=0 force=0
  if [[ $# -eq 0 ]]; then
    usage >&2
    exit 2
  fi
  cmd="$1"
  shift
  case "$cmd" in
    -h | --help | help)
      usage
      exit 0
      ;;
    new | adopt) ;;
    *)
      printf 'install.sh: invalid command: %s\n' "$cmd" >&2
      usage >&2
      exit 2
      ;;
  esac
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --version)
        [[ $# -ge 2 ]] || die '--version needs a vX.Y.Z value'
        version="$2"
        shift 2
        ;;
      --version=*)
        version="${1#*=}"
        shift
        ;;
      --domain)
        [[ $# -ge 2 ]] || die '--domain needs a value, for example x.test'
        domain="$2"
        shift 2
        ;;
      --domain=*)
        domain="${1#*=}"
        shift
        ;;
      --setup)
        setup=1
        shift
        ;;
      --magento)
        [[ $# -ge 2 ]] || die '--magento needs a version, for example 2.4.7'
        magento="$2"
        shift 2
        ;;
      --magento=*)
        magento="${1#*=}"
        shift
        ;;
      --dry-run)
        dry=1
        shift
        ;;
      --force)
        force=1
        shift
        ;;
      --source)
        [[ $# -ge 2 ]] || die '--source needs a directory or a tarball'
        source="$2"
        shift 2
        ;;
      --source=*)
        source="${1#*=}"
        shift
        ;;
      -*) die "invalid option: $1" ;;
      *)
        [[ -z "$dir" ]] || die "extra argument: $1"
        dir="$1"
        shift
        ;;
    esac
  done
  if [[ -n "$version" && ! "$version" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    die "--version must look like vX.Y.Z, got: $version"
  fi
  if [[ -n "$domain" && ! "$domain" =~ ^[A-Za-z0-9]([A-Za-z0-9.-]*[A-Za-z0-9])?$ ]]; then
    die "--domain is invalid: $domain"
  fi
  if [[ "$cmd" == new && ("$dry" -eq 1 || "$force" -eq 1) ]]; then
    die '--dry-run and --force are only used with adopt'
  fi
  if [[ "$cmd" == adopt ]]; then
    [[ -z "$domain" ]] || die 'adopt leaves KIT_DOMAIN empty, fill it in project/profile.env'
    [[ "$setup" -eq 0 && -z "$magento" ]] || die '--setup and --magento are only used with new'
  fi
  case "$cmd" in
    new)
      resolve_source "$source" "$version"
      cmd_new "$dir" "$domain" "$setup" "$magento"
      ;;
    adopt)
      resolve_source "$source" "$version"
      cmd_adopt "$dir" "$dry" "$force"
      ;;
  esac
}

main "$@"
