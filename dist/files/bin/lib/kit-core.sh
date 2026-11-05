#!/usr/bin/env bash
# bin/lib/kit-core.sh - lõi lập kế hoạch cài và cập nhật, dùng chung cho
# `install.sh new` và `bin/self-update`. Chỉ để `source`, không chạy trực tiếp.
#
# Người gọi phải định nghĩa hàm `die <thông báo>` (in lỗi và thoát) trước khi gọi.
#
# Kế hoạch là một file, mỗi dòng `<hành động><TAB><quyền><TAB><đường dẫn>`.
# Thuật toán ba chiều chạy trên hợp của manifest cũ và manifest mới:
#   write      chưa có ở local: ghi
#   overwrite  local trùng checksum lúc cài: ghi đè bản mới
#   skip       local đã trùng bản mới: bỏ qua
#   keep       bản mới không đổi file này nhưng local đã sửa: giữ bản sửa tay
#   conflict   local khác cả bản lúc cài lẫn bản mới: xung đột cập nhật
#   remove     bản mới bỏ file, local chưa sửa: xoá
#   orphan     bản mới bỏ file, local đã sửa: giữ và cảnh báo
#   template   template chưa có ở local: tạo (không bao giờ ghi đè)
# Chỉ dùng công cụ cơ bản (awk, cp, mv, chmod, find, sort, sha256sum hoặc
# shasum), không cần git.

sha256_of() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$1" | cut -d' ' -f1
  else
    shasum -a 256 "$1" | cut -d' ' -f1
  fi
}

# Đặt quyền theo số trong manifest, chỉ phân biệt thực thi hay không.
apply_mode() {
  case "$1" in
    755) chmod 755 "$2" ;;
    *) chmod 644 "$2" ;;
  esac
}

# kit_verify_source <kit_root>: mọi file trong dist/files phải khớp dist/manifest.
verify_source() {
  local root="$1" sum mode path bad=0
  while read -r sum mode path; do
    [[ -n "$path" ]] || continue
    if [[ ! -f "$root/dist/files/$path" ]] || [[ "$(sha256_of "$root/dist/files/$path")" != "$sum" ]]; then
      printf 'nguồn lệch manifest: %s\n' "$path" >&2
      bad=1
    fi
  done < "$root/dist/manifest"
  [[ "$bad" -eq 0 ]] || die 'nguồn không khớp manifest, dừng trước khi ghi'
}

# --------------------------------------------------------------------------
# Tải nguồn (dùng cho bin/self-update; install.sh có bản riêng vì chạy trước
# khi lõi này tồn tại)
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
  json="$(curl -fsSL "https://api.github.com/repos/$repo/tags?per_page=100")" || die 'không lấy được danh sách tag'
  printf '%s\n' "$json" \
    | grep -Eo '"name"[[:space:]]*:[[:space:]]*"v[0-9]+\.[0-9]+\.[0-9]+"' \
    | grep -Eo 'v[0-9]+\.[0-9]+\.[0-9]+' \
    | sort -t. -k1.2,1n -k2,2n -k3,3n \
    | tail -n 1
}

# kit_fetch_source <work_dir> <source|''> <version|''> <repo>: đặt KIT_ROOT và VERSION.
kit_fetch_source() {
  local work="$1" source="$2" version="$3" repo="$4"
  if [[ -n "$source" ]]; then
    if [[ -d "$source" ]]; then
      KIT_ROOT="$(cd "$source" && pwd -P)"
    elif [[ -f "$source" ]]; then
      mkdir -p "$work/src"
      tar -xzf "$source" -C "$work/src" || die "không giải nén được $source"
      KIT_ROOT="$(kit_find_root "$work/src")" || die "tarball không chứa dist/: $source"
    else
      die "--source không tồn tại: $source"
    fi
    [[ -d "$KIT_ROOT/dist/files" && -f "$KIT_ROOT/dist/manifest" ]] || die "nguồn thiếu dist/files hoặc dist/manifest: $source"
    if [[ -z "$version" ]]; then
      version="$(tr -d '[:space:]' < "$KIT_ROOT/dist/version" 2>/dev/null || true)"
      [[ -n "$version" ]] || version='dev'
    fi
  else
    command -v curl >/dev/null 2>&1 || die 'cần curl'
    if [[ -z "$version" ]]; then
      version="$(kit_latest_tag "$repo")"
      [[ -n "$version" ]] || die 'repo chưa có tag phát hành nào'
    fi
    curl -fsSL "https://github.com/$repo/archive/refs/tags/$version.tar.gz" -o "$work/kit.tar.gz" \
      || die "không tải được tag $version"
    mkdir -p "$work/src"
    tar -xzf "$work/kit.tar.gz" -C "$work/src" || die "không giải nén được tag $version"
    KIT_ROOT="$(kit_find_root "$work/src")" || die "tarball $version không chứa dist/"
    [[ -f "$KIT_ROOT/dist/manifest" ]] || die "tag $version thiếu dist/manifest"
  fi
  export VERSION="$version"
}

# --------------------------------------------------------------------------
# Lập kế hoạch
# --------------------------------------------------------------------------

# kit_plan <root> <manifest_cũ|''> <manifest_mới> <thư_mục_template|''>
# In kế hoạch ra stdout, sắp xếp theo đường dẫn. Không ghi gì vào <root>.
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
        local_sum='!' # symlink hoặc thư mục: không khớp checksum nào
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

# kit_plan_count <plan> <hành_động>
kit_plan_count() {
  local n
  n="$(awk -F'\t' -v a="$2" '$1 == a { n++ } END { print n + 0 }' "$1")"
  printf '%s' "$n"
}

# --------------------------------------------------------------------------
# Áp dụng
# --------------------------------------------------------------------------

# Ghi qua file tạm rồi mv để thay nguyên inode. Script đang chạy (bin/self-update
# ghi đè chính nó) nhờ vậy vẫn đọc được bản cũ cho tới khi kết thúc.
_kit_install_file() {
  local src="$1" dest="$2" mode="$3" tmp
  mkdir -p "$(dirname "$dest")"
  tmp="$dest.kit-tmp.$$"
  if ! { cp "$src" "$tmp" && apply_mode "$mode" "$tmp" && mv -f "$tmp" "$dest"; }; then
    rm -f "$tmp"
    return 1
  fi
}

# kit_apply <root> <plan> <thư_mục_files> <thư_mục_template|''> <force 0|1> <thư_mục_backup>
# Áp dụng kế hoạch. conflict chỉ được ghi khi force=1 và được chuyển vào
# <thư_mục_backup>/<đường dẫn> trước. Không ghi manifest và version.
kit_apply() {
  local root="$1" plan="$2" files="$3" tpl="$4" force="$5" backup="$6" action mode path dir
  while IFS=$'\t' read -r action mode path; do
    case "$action" in
      write | overwrite) _kit_install_file "$files/$path" "$root/$path" "$mode" ;;
      template) _kit_install_file "$tpl/$path" "$root/$path" "$mode" ;;
      conflict)
        [[ "$force" -eq 1 ]] || die "xung đột chưa được xử lý: $path"
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

# kit_write_state <root> <manifest_mới> <version>: ghi sau cùng. Manifest trước,
# version sau, mỗi file qua mv nên không bao giờ nửa vời.
kit_write_state() {
  local root="$1" manifest="$2" version="$3"
  mkdir -p "$root/.kit"
  cp "$manifest" "$root/.kit/manifest.tmp"
  mv -f "$root/.kit/manifest.tmp" "$root/.kit/manifest"
  printf '%s\n' "$version" > "$root/.kit/version.tmp"
  mv -f "$root/.kit/version.tmp" "$root/.kit/version"
}

# --------------------------------------------------------------------------
# Thông tin phụ cho bin/self-update
# --------------------------------------------------------------------------

# kit_changelog <CHANGELOG.md> <từ> <đến>: in các mục `## vX.Y.Z` nằm giữa hai
# phiên bản. Nâng cấp in (từ, đến], hạ cấp in (đến, từ].
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

# kit_profile_missing <profile> <template>: in `KHÓA=mặc_định` cho khóa có trong
# template mới mà file profile chưa có (kể cả dạng comment). Không ghi gì.
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
        if (v == "") print k "=\t(bắt buộc, không có mặc định)"
        else print k "=" v
      }
    }
  ' "${profile:-/dev/null}" "$template"
}

# --------------------------------------------------------------------------
# Nhận dự án (install.sh adopt)
# --------------------------------------------------------------------------

# kit_conflict_hint <đường_dẫn>: chỗ mở rộng nên dùng để chuyển phần tùy biến
# khỏi file của gói bị xung đột.
kit_conflict_hint() {
  case "$1" in
    compose*.yaml | compose*.yml)
      printf 'đổi cấu trúc (service, mount, build, command) -> compose.override.yaml; phiên bản, cổng, image -> project/profile.env; biến cho container -> env/*.env'
      ;;
    bin/*) printf 'lệnh riêng của dự án -> project/bin/<lệnh>; giá trị cấu hình -> project/profile.env; biến cho container -> env/*.env' ;;
    Makefile) printf 'target riêng -> project/bin/<lệnh>' ;;
    conf/* | template/* | .vscode/*) printf 'mount bản riêng bằng compose.override.yaml, hoặc đưa thay đổi lên repo của gói' ;;
    *) printf 'giá trị -> project/profile.env; cấu trúc Compose -> compose.override.yaml; biến container -> env/*.env; lệnh riêng -> project/bin/' ;;
  esac
}

# kit_stray_files <root> <manifest> <thư_mục_template>: in các file lạ (không
# thuộc gói, không phải template, không phải trạng thái của gói). Thư mục mà mọi
# file bên trong đều lạ được gộp thành `thư_mục/`. Không bao giờ đi vào src/,
# .worktrees/, .git/, .kit/ hay project/.
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

# Đọc compose.yaml, chỉ các dòng không bị comment. In `service<TAB>loại<TAB>giá trị`
# với loại là image, port (host:container), javaopts (giá trị *_JAVA_OPTS).
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

# kit_adopt_guess <root>: in `KHÓA=giá trị` đoán được chỉ từ file (không đọc DB,
# không gọi Docker). Khóa nào không chắc thì bỏ, không đoán bừa.
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

# kit_profile_apply_guesses <profile> <file_đoán>: điền các khóa đoán vào file
# profile vừa tạo từ template. Mỗi dòng đoán kèm `# adopt đoán, kiểm tra lại`.
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
          print k "=" g[k] "  # adopt đoán, kiểm tra lại"
          next
        }
      }
      print
    }
    END { for (j = 1; j <= n; j++) if (!(order[j] in done)) print order[j] "=" g[order[j]] "  # adopt đoán, kiểm tra lại" }
  ' "$guesses" "$profile" > "$tmp" && mv -f "$tmp" "$profile"
}
