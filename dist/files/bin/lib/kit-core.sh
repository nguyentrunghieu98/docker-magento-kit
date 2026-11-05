#!/usr/bin/env bash
# bin/lib/kit-core.sh - install and update planning core, shared by
# `install.sh new` and `bin/self-update`. Source-only, never run directly.
#
# The caller must define a `die <message>` function (print an error and exit) before calling.
#
# The plan is a file, one line per entry `<action><TAB><mode><TAB><path>`.
# The three-way algorithm runs over the union of the old and the new manifest:
#   write      not present locally: write it
#   overwrite  local matches the install-time checksum: overwrite with the new version
#   skip       local already matches the new version: skip
#   keep       the new version leaves this file unchanged but local was edited: keep the hand edit
#   conflict   local differs from both the install-time and the new version: update conflict
#   remove     the new version drops the file, local was not edited: remove it
#   orphan     the new version drops the file, local was edited: keep it and warn
#   template   template not present locally: create it (never overwrite)
# Basic tools only (awk, cp, mv, chmod, find, sort, sha256sum or
# shasum), no git needed.

sha256_of() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$1" | cut -d' ' -f1
  else
    shasum -a 256 "$1" | cut -d' ' -f1
  fi
}

# Set the mode from the number in the manifest, only distinguishing executable or not.
apply_mode() {
  case "$1" in
    755) chmod 755 "$2" ;;
    *) chmod 644 "$2" ;;
  esac
}

# kit_verify_source <kit_root>: every file in dist/files must match dist/manifest.
verify_source() {
  local root="$1" sum mode path bad=0
  while read -r sum mode path; do
    [[ -n "$path" ]] || continue
    if [[ ! -f "$root/dist/files/$path" ]] || [[ "$(sha256_of "$root/dist/files/$path")" != "$sum" ]]; then
      printf 'source differs from the manifest: %s\n' "$path" >&2
      bad=1
    fi
  done < "$root/dist/manifest"
  [[ "$bad" -eq 0 ]] || die 'source does not match the manifest, stopping before any write'
}

# --------------------------------------------------------------------------
# Fetching the source (used by bin/self-update; install.sh has its own copy
# because it runs before this core exists)
# --------------------------------------------------------------------------

kit_find_root() {
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

kit_latest_tag() {
  local repo="$1" json
  json="$(curl -fsSL "https://api.github.com/repos/$repo/tags?per_page=100")" || die 'cannot fetch the tag list'
  printf '%s\n' "$json" \
    | grep -Eo '"name"[[:space:]]*:[[:space:]]*"v[0-9]+\.[0-9]+\.[0-9]+"' \
    | grep -Eo 'v[0-9]+\.[0-9]+\.[0-9]+' \
    | sort -t. -k1.2,1n -k2,2n -k3,3n \
    | tail -n 1
}

# kit_fetch_source <work_dir> <source|''> <version|''> <repo>: sets KIT_ROOT and VERSION.
kit_fetch_source() {
  local work="$1" source="$2" version="$3" repo="$4"
  if [[ -n "$source" ]]; then
    if [[ -d "$source" ]]; then
      KIT_ROOT="$(cd "$source" && pwd -P)"
    elif [[ -f "$source" ]]; then
      mkdir -p "$work/src"
      tar -xzf "$source" -C "$work/src" || die "cannot extract $source"
      KIT_ROOT="$(kit_find_root "$work/src")" || die "tarball does not contain dist/: $source"
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
      version="$(kit_latest_tag "$repo")"
      [[ -n "$version" ]] || die 'the repo has no release tag yet'
    fi
    curl -fsSL "https://github.com/$repo/archive/refs/tags/$version.tar.gz" -o "$work/kit.tar.gz" \
      || die "cannot download tag $version"
    mkdir -p "$work/src"
    tar -xzf "$work/kit.tar.gz" -C "$work/src" || die "cannot extract tag $version"
    KIT_ROOT="$(kit_find_root "$work/src")" || die "tarball $version does not contain dist/"
    [[ -f "$KIT_ROOT/dist/manifest" ]] || die "tag $version is missing dist/manifest"
  fi
  export VERSION="$version"
}

# --------------------------------------------------------------------------
# Planning
# --------------------------------------------------------------------------

# kit_plan <root> <old_manifest|''> <new_manifest> <template_dir|''>
# Print the plan to stdout, sorted by path. Writes nothing into <root>.
kit_plan() {
  local root="$1" oldm="$2" newm="$3" tpl="$4" empty='' path old new mode local_sum rel action
  if [[ -z "$oldm" ]]; then
    empty="$(mktemp)"
    oldm="$empty"
  fi
  while IFS=$'\t' read -r path old new mode; do
    [[ -n "$path" ]] || continue
    local_sum=''
    if [[ -e "$root/$path" || -L "$root/$path" ]]; then
      if [[ -f "$root/$path" && ! -L "$root/$path" ]]; then
        local_sum="$(sha256_of "$root/$path")"
      else
        local_sum='!' # symlink or directory: matches no checksum
      fi
    fi
    if [[ "$new" != '-' ]]; then
      if [[ -z "$local_sum" ]]; then
        action='write'
      elif [[ "$local_sum" == "$new" ]]; then
        action=skip
      elif [[ "$old" != '-' && "$local_sum" == "$old" ]]; then
        action=overwrite
      elif [[ "$old" == "$new" ]]; then
        action=keep
      else
        action=conflict
      fi
    else
      if [[ -z "$local_sum" ]]; then
        action=skip
      elif [[ "$local_sum" == "$old" ]]; then
        action=remove
      else
        action=orphan
      fi
      mode=644
    fi
    printf '%s\t%s\t%s\n' "$action" "$mode" "$path"
  done < <(
    awk -v OFS='\t' '
      FILENAME == ARGV[1] { old[$3] = $1; paths[$3] = 1; next }
      { new[$3] = $1; mode[$3] = $2; paths[$3] = 1 }
      END {
        for (p in paths)
          print p, (p in old ? old[p] : "-"), (p in new ? new[p] : "-"), (p in mode ? mode[p] : "-")
      }' "$oldm" "$newm" | LC_ALL=C sort
  )
  if [[ -n "$tpl" && -d "$tpl" ]]; then
    while IFS= read -r rel; do
      rel="${rel#./}"
      if [[ ! -e "$root/$rel" && ! -L "$root/$rel" ]]; then
        if [[ -x "$tpl/$rel" ]]; then mode=755; else mode=644; fi
        printf 'template\t%s\t%s\n' "$mode" "$rel"
      fi
    done < <(cd "$tpl" && find . -type f -print | LC_ALL=C sort)
  fi
  if [[ -n "$empty" ]]; then rm -f "$empty"; fi
  return 0
}

# kit_plan_count <plan> <action>
kit_plan_count() {
  local n
  n="$(awk -F'\t' -v a="$2" '$1 == a { n++ } END { print n + 0 }' "$1")"
  printf '%s' "$n"
}

# --------------------------------------------------------------------------
# Apply
# --------------------------------------------------------------------------

# Write through a temp file then mv so the whole inode is replaced. The running
# script (bin/self-update overwrites itself) can still read the old copy until it exits.
_kit_install_file() {
  local src="$1" dest="$2" mode="$3" tmp
  mkdir -p "$(dirname "$dest")"
  tmp="$dest.kit-tmp.$$"
  if ! { cp "$src" "$tmp" && apply_mode "$mode" "$tmp" && mv -f "$tmp" "$dest"; }; then
    rm -f "$tmp"
    return 1
  fi
}

# kit_apply <root> <plan> <files_dir> <template_dir|''> <force 0|1> <backup_dir>
# Apply the plan. A conflict is only written when force=1, and is moved into
# <backup_dir>/<path> first. Does not write the manifest or the version.
kit_apply() {
  local root="$1" plan="$2" files="$3" tpl="$4" force="$5" backup="$6" action mode path dir
  while IFS=$'\t' read -r action mode path; do
    case "$action" in
      write | overwrite) _kit_install_file "$files/$path" "$root/$path" "$mode" ;;
      template) _kit_install_file "$tpl/$path" "$root/$path" "$mode" ;;
      conflict)
        [[ "$force" -eq 1 ]] || die "unhandled conflict: $path"
        mkdir -p "$backup/$(dirname "$path")"
        mv "$root/$path" "$backup/$path"
        _kit_install_file "$files/$path" "$root/$path" "$mode"
        ;;
      remove)
        rm -f "$root/$path"
        dir="$(dirname "$path")"
        while [[ "$dir" != '.' && "$dir" != '/' ]] && rmdir "$root/$dir" 2>/dev/null; do
          dir="$(dirname "$dir")"
        done
        ;;
    esac
  done < "$plan"
}

# kit_write_state <root> <new_manifest> <version>: written last. Manifest first,
# version after, each file through mv so it is never half done.
kit_write_state() {
  local root="$1" manifest="$2" version="$3"
  mkdir -p "$root/.kit"
  cp "$manifest" "$root/.kit/manifest.tmp"
  mv -f "$root/.kit/manifest.tmp" "$root/.kit/manifest"
  printf '%s\n' "$version" > "$root/.kit/version.tmp"
  mv -f "$root/.kit/version.tmp" "$root/.kit/version"
}

# --------------------------------------------------------------------------
# Extra information for bin/self-update
# --------------------------------------------------------------------------

# kit_changelog <CHANGELOG.md> <from> <to>: print the `## vX.Y.Z` entries between two
# versions. An upgrade prints (from, to], a downgrade prints (to, from].
kit_changelog() {
  [[ -f "$1" ]] || return 0
  awk -v from="$2" -v to="$3" '
    function key(v,   a, n) {
      sub(/^v/, "", v); sub(/[-+].*$/, "", v)
      n = split(v, a, ".")
      return sprintf("%06d%06d%06d", a[1] + 0, a[2] + 0, a[3] + 0)
    }
    BEGIN { f = key(from); t = key(to); lo = (f < t) ? f : t; hi = (f < t) ? t : f; on = 0 }
    /^## / {
      v = $2; gsub(/[\[\]]/, "", v)
      k = key(v)
      on = (v ~ /^v?[0-9]/ && k > lo && k <= hi)
    }
    on { print }
  ' "$1"
}

# kit_profile_missing <profile> <template>: print `KEY=default` for every key in the
# new template that the profile file does not have yet (commented-out included). Writes nothing.
kit_profile_missing() {
  local profile="$1" template="$2"
  [[ -f "$template" ]] || return 0
  awk '
    FILENAME == ARGV[1] {
      if (match($0, /^#? ?KIT_[A-Z0-9_]+=/)) {
        k = substr($0, RSTART, RLENGTH); sub(/^#? ?/, "", k); sub(/=$/, "", k)
        have[k] = 1
      }
      next
    }
    match($0, /^#? ?KIT_[A-Z0-9_]+=/) {
      k = substr($0, RSTART, RLENGTH); sub(/^#? ?/, "", k); sub(/=$/, "", k)
      v = substr($0, RSTART + RLENGTH)
      if (!(k in have) && !(k in done)) {
        done[k] = 1
        if (v == "") print k "=\t(required, no default)"
        else print k "=" v
      }
    }
  ' "${profile:-/dev/null}" "$template"
}

# --------------------------------------------------------------------------
# Adopting a project (install.sh adopt)
# --------------------------------------------------------------------------

# kit_conflict_hint <path>: the extension point to use when moving customizations
# out of a conflicting package file.
kit_conflict_hint() {
  case "$1" in
    compose*.yaml | compose*.yml)
      printf 'structure changes (services, mounts, build, command) -> compose.override.yaml; versions, ports, images -> project/profile.env; container variables -> env/*.env'
      ;;
    bin/*) printf 'project-specific commands -> project/bin/<command>; configuration values -> project/profile.env; container variables -> env/*.env' ;;
    Makefile) printf 'project-specific targets -> project/bin/<command>' ;;
    conf/* | template/* | .vscode/*) printf 'mount your own copy through compose.override.yaml, or send the change to the package repo' ;;
    *) printf 'values -> project/profile.env; Compose structure -> compose.override.yaml; container variables -> env/*.env; project commands -> project/bin/' ;;
  esac
}

# kit_stray_files <root> <manifest> <template_dir>: print stray files (not owned
# by the package, not a template, not package state). A directory whose files are
# all stray is collapsed into `dir/`. Never walks into src/, .worktrees/, .git/,
# .kit/ or project/.
kit_stray_files() {
  local root="$1" manifest="$2" tpl="$3" known
  known="$(mktemp)"
  {
    awk '{print $3}' "$manifest"
    if [[ -d "$tpl" ]]; then (cd "$tpl" && find . -type f -print | sed 's|^\./||'); fi
    printf '%s\n' compose.override.yaml .active-src
  } > "$known"
  (
    cd "$root" || exit 0
    find . \( -path ./src -o -path ./.worktrees -o -path ./.git -o -path ./.kit -o -path ./project \) -prune -o \
      \( -type f -o -type l \) -print | sed 's|^\./||' | LC_ALL=C sort
  ) | awk -v known="$known" '
    BEGIN {
      while ((getline line < known) > 0) {
        isknown[line] = 1
        n = split(line, p, "/"); acc = ""
        for (i = 1; i < n; i++) { acc = (acc == "" ? p[i] : acc "/" p[i]); knowndir[acc] = 1 }
      }
    }
    {
      if ($0 in isknown) next
      n = split($0, p, "/"); out = $0; acc = ""
      for (i = 1; i < n; i++) {
        acc = (acc == "" ? p[i] : acc "/" p[i])
        if (!(acc in knowndir)) { out = acc "/"; break }
      }
      if (!(out in seen)) { seen[out] = 1; print out }
    }'
  rm -f "$known"
}

# Read compose.yaml, uncommented lines only. Print `service<TAB>kind<TAB>value`
# where kind is image, port (host:container) or javaopts (the value of *_JAVA_OPTS).
_kit_compose_facts() {
  awk '
    function clean(s) { sub(/^[ \t]+/, "", s); sub(/[ \t]+#.*$/, "", s); gsub(/["\047]/, "", s); sub(/[ \t]+$/, "", s); return s }
    /^[ \t]*#/ { next }
    /^services:/ { ins = 1; next }
    /^[A-Za-z]/ { ins = 0 }
    !ins { next }
    /^  [A-Za-z0-9_.-]+:[ \t]*($|#)/ { svc = $1; sub(/:$/, "", svc); sect = ""; next }
    svc == "" { next }
    /^[ \t]+image:/ { v = $0; sub(/^[ \t]+image:/, "", v); print svc "\timage\t" clean(v); next }
    /^[ \t]+(ports|environment):[ \t]*($|#)/ { sect = ($1 == "ports:") ? "ports" : "env"; next }
    /^[ \t]+[A-Za-z_]+:/ { sect = ""; next }
    /^[ \t]+-[ \t]/ && sect != "" {
      v = $0; sub(/^[ \t]+-[ \t]+/, "", v); v = clean(v)
      if (sect == "env") { if (v ~ /_JAVA_OPTS=/) { sub(/^[^=]*=/, "", v); print svc "\tjavaopts\t" v } }
      else print svc "\tport\t" v
    }
  ' "$1"
}

# kit_adopt_guess <root>: print `KEY=value` guessed from files alone (no DB read,
# no Docker call). Drop any key that is uncertain, never guess blindly.
kit_adopt_guess() {
  local root="$1" name facts remote branches base='' target='' v ver image spec svc cport key
  name="$(basename "$root" | tr '[:upper:]' '[:lower:]' | sed -e 's/[^a-z0-9_-]//g' -e 's/^[_-]*//')"
  [[ -z "$name" ]] || printf 'KIT_PROJECT_NAME=%s\n' "$name"

  if [[ -e "$root/src/.git" ]] && command -v git >/dev/null 2>&1; then
    remote="$(git -C "$root/src" remote 2>/dev/null || true)"
    if [[ -n "$remote" && "$(printf '%s\n' "$remote" | wc -l)" -eq 1 ]]; then
      branches="$(git -C "$root/src" for-each-ref --format='%(refname:strip=3)' "refs/remotes/$remote/" 2>/dev/null || true)"
      if printf '%s\n' "$branches" | grep -qx 'master'; then
        base=master
      elif printf '%s\n' "$branches" | grep -qx 'main'; then
        base=main
      fi
      if printf '%s\n' "$branches" | grep -qx 'staging'; then target=staging; fi
      if [[ -n "$base" && -n "$target" ]]; then
        printf 'KIT_GIT_REMOTE=%s\nKIT_GIT_BASE_BRANCH=%s\nKIT_GIT_TARGET_BRANCH=%s\n' "$remote" "$base" "$target"
      fi
    fi
  fi

  [[ -f "$root/compose.yaml" ]] || return 0
  facts="$(_kit_compose_facts "$root/compose.yaml")"
  [[ -n "$facts" ]] || return 0

  image="$(printf '%s\n' "$facts" | awk -F'\t' '$1 == "phpfpm" && $2 == "image" { print $3; exit }')"
  ver="$(printf '%s\n' "$image" | sed -n 's/^[^:]*php[^:]*:\([0-9][0-9]*\.[0-9][0-9]*\)[.-].*/\1/p' | head -n 1)"
  case "$ver" in 8.2 | 8.3 | 8.4) printf 'KIT_PHP_VERSION=%s\n' "$ver" ;; esac

  image="$(printf '%s\n' "$facts" | awk -F'\t' '$1 == "db" && $2 == "image" { print $3; exit }')"
  case "$image" in
    mysql:[0-9]*) printf 'KIT_DB_ENGINE=mysql\nKIT_DB_VERSION=%s\n' "${image#mysql:}" ;;
    mariadb:[0-9]*) printf 'KIT_DB_ENGINE=mariadb\nKIT_DB_VERSION=%s\n' "${image#mariadb:}" ;;
  esac

  image="$(printf '%s\n' "$facts" | awk -F'\t' '$1 == "redis" && $2 == "image" { print $3; exit }')"
  [[ -z "$image" || "$image" == *'$'* ]] || printf 'KIT_REDIS_IMAGE=%s\n' "$image"

  for spec in 'app 8000 KIT_HTTP_PORT' 'app 8443 KIT_HTTPS_PORT' 'db 3306 KIT_DB_PORT' 'redis 6379 KIT_REDIS_PORT' \
    'opensearch 9200 KIT_OPENSEARCH_PORT' 'rabbitmq 5672 KIT_RABBITMQ_PORT' 'rabbitmq 15672 KIT_RABBITMQ_MANAGEMENT_PORT'; do
    read -r svc cport key <<< "$spec"
    v="$(printf '%s\n' "$facts" | awk -F'\t' -v s="$svc" -v c="$cport" '
      $1 == s && $2 == "port" {
        n = split($3, p, ":"); sub(/\/.*$/, "", p[n])
        if (n >= 2 && p[n] == c && p[n - 1] ~ /^[0-9]+$/) { print p[n - 1]; exit }
      }')"
    [[ -z "$v" ]] || printf '%s=%s\n' "$key" "$v"
  done

  v="$(printf '%s\n' "$facts" | awk -F'\t' '$1 == "opensearch" && $2 == "javaopts" {
      if (match($3, /-Xmx[0-9]+[kKmMgG]/)) { print tolower(substr($3, RSTART + 4, RLENGTH - 4)); exit } }')"
  [[ -z "$v" ]] || printf 'KIT_OPENSEARCH_HEAP=%s\n' "$v"
  return 0
}

# kit_profile_apply_guesses <profile> <guesses_file>: fill the guessed keys into the
# profile file just created from the template. Each guessed line gets `# adopt guess, verify it`.
kit_profile_apply_guesses() {
  local profile="$1" guesses="$2" tmp
  tmp="$profile.kit-tmp.$$"
  awk '
    FILENAME == ARGV[1] { i = index($0, "="); if (i > 1) { g[substr($0, 1, i - 1)] = substr($0, i + 1); order[++n] = substr($0, 1, i - 1) } next }
    {
      if (match($0, /^#? ?KIT_[A-Z0-9_]+=/)) {
        k = substr($0, RSTART, RLENGTH); sub(/^#? ?/, "", k); sub(/=$/, "", k)
        if ((k in g) && !(k in done)) {
          done[k] = 1
          print k "=" g[k] "  # adopt guess, verify it"
          next
        }
      }
      print
    }
    END { for (j = 1; j <= n; j++) if (!(order[j] in done)) print order[j] "=" g[order[j]] "  # adopt guess, verify it" }
  ' "$guesses" "$profile" > "$tmp" && mv -f "$tmp" "$profile"
}
