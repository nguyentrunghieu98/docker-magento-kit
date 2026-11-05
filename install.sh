#!/usr/bin/env bash
# install.sh - cài magento-docker-kit vào một Docker root.
#
#   curl -fsSL https://raw.githubusercontent.com/nguyentrunghieu98/magento-docker-kit/main/install.sh \
#     | bash -s -- new <dir> [--version vX.Y.Z]
#
#   install.sh new <dir> [--domain x.test] [--setup --magento <phiên bản>] [--version vX.Y.Z] [--source <thư mục|tarball>]
#   install.sh adopt <dir> [--dry-run] [--force] [--version vX.Y.Z] [--source <thư mục|tarball>]
#
# Không có --source thì tải tarball theo tag (mặc định là tag mới nhất), máy đích
# không cần git. --source dùng để chạy không cần mạng (CI và test).
# Biến môi trường: KIT_REPO=<owner>/<repo> đổi repo nguồn.
set -Eeuo pipefail

KIT_REPO="${KIT_REPO:-nguyentrunghieu98/magento-docker-kit}"
WORK=''

die() {
  printf 'install.sh: %s\n' "$*" >&2
  exit 1
}

usage() {
  cat <<'EOF'
Cách dùng:
  install.sh new <dir> [--domain x.test] [--setup --magento <phiên bản>] [--version vX.Y.Z] [--source <thư mục|tarball>]
  install.sh adopt <dir> [--dry-run] [--force] [--version vX.Y.Z] [--source <thư mục|tarball>]

  new <dir>          ghi file của gói và template vào <dir>, không đụng gì khác
  adopt <dir>        đưa Docker root đang chạy về dạng do gói quản lý, không đụng stack
  --dry-run          (adopt) chỉ in kế hoạch, không ghi gì
  --force            (adopt) sao lưu file xung đột vào .kit/backup/<thời điểm>/ rồi ghi đè
  --domain x.test    điền KIT_DOMAIN trong project/profile.env mới tạo
  --setup            sau khi cài, chạy bin/download rồi bin/setup (cần --domain và --magento)
  --magento <bản>    phiên bản Magento cho bin/download, chỉ dùng cùng --setup
  --version vX.Y.Z   ghim phiên bản, mặc định là tag mới nhất
  --source <nguồn>   dùng thư mục checkout của gói hoặc tarball, không cần mạng
EOF
}

cleanup() {
  if [[ -n "$WORK" && -d "$WORK" ]]; then
    rm -rf "$WORK"
  fi
  return 0
}
trap cleanup EXIT

# Tìm thư mục gốc của gói (chứa dist/) trong một thư mục đã giải nén.
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
  tar -xzf "$tarball" -C "$out" || die "không giải nén được $tarball"
}

latest_tag() {
  local json
  json="$(curl -fsSL "https://api.github.com/repos/$KIT_REPO/tags?per_page=100")" || die 'không lấy được danh sách tag'
  printf '%s\n' "$json" \
    | grep -Eo '"name"[[:space:]]*:[[:space:]]*"v[0-9]+\.[0-9]+\.[0-9]+"' \
    | grep -Eo 'v[0-9]+\.[0-9]+\.[0-9]+' \
    | sort -t. -k1.2,1n -k2,2n -k3,3n \
    | tail -n 1
}

# Đặt KIT_ROOT (thư mục gói) và VERSION.
resolve_source() {
  local source="$1" version="$2"
  WORK="$(mktemp -d "${TMPDIR:-/tmp}/kit-install.XXXXXX")"
  if [[ -n "$source" ]]; then
    if [[ -d "$source" ]]; then
      KIT_ROOT="$(cd "$source" && pwd -P)"
    elif [[ -f "$source" ]]; then
      extract_tarball "$source" "$WORK/src"
      KIT_ROOT="$(find_kit_root "$WORK/src")" || die "tarball không chứa dist/: $source"
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
      version="$(latest_tag)"
      [[ -n "$version" ]] || die 'repo chưa có tag phát hành nào'
    fi
    curl -fsSL "https://github.com/$KIT_REPO/archive/refs/tags/$version.tar.gz" -o "$WORK/kit.tar.gz" \
      || die "không tải được tag $version"
    extract_tarball "$WORK/kit.tar.gz" "$WORK/src"
    KIT_ROOT="$(find_kit_root "$WORK/src")" || die "tarball $version không chứa dist/"
    [[ -f "$KIT_ROOT/dist/manifest" ]] || die "tag $version thiếu dist/manifest"
  fi
  VERSION="$version"
  [[ -f "$KIT_ROOT/dist/files/bin/lib/kit-core.sh" ]] || die "nguồn thiếu bin/lib/kit-core.sh"
  # shellcheck source=dist/files/bin/lib/kit-core.sh
  source "$KIT_ROOT/dist/files/bin/lib/kit-core.sh"
}

cmd_new() {
  local target="$1" domain="${2:-}" setup="${3:-0}" magento="${4:-}" sum mode path existing=() rel
  [[ -n "$target" ]] || die 'thiếu <dir>, ví dụ: install.sh new my-shop'
  if [[ -e "$target" && ! -d "$target" ]]; then
    die "$target đã tồn tại và không phải thư mục"
  fi

  if [[ "$setup" == 1 ]]; then
    [[ -n "$magento" ]] || die '--setup cần --magento <phiên bản>, ví dụ: --magento 2.4.7'
    [[ -n "$domain" ]] || die '--setup cần --domain, vì bin/setup lấy domain từ KIT_DOMAIN'
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
    printf 'install.sh: %s đã có file của gói:\n' "$target" >&2
    printf '  %s\n' "${existing[@]:0:5}" >&2
    [[ "${#existing[@]}" -le 5 ]] || printf '  ... và %d file nữa\n' "$((${#existing[@]} - 5))" >&2
    printf "Để đưa dự án đang có về dạng do gói quản lý, dùng: install.sh adopt %s\n" "$target" >&2
    exit 1
  fi

  mkdir -p "$target"
  target="$(cd "$target" && pwd -P)"

  # Dùng chung lõi lập kế hoạch với bin/self-update: manifest cũ rỗng nên mọi
  # file của gói là "ghi", template chỉ tạo khi chưa có.
  local profile_created=0 plan="$WORK/plan"
  [[ -e "$target/project/profile.env" ]] || profile_created=1
  kit_plan "$target" '' "$KIT_ROOT/dist/manifest" "$KIT_ROOT/dist/templates" > "$plan"
  kit_apply "$target" "$plan" "$KIT_ROOT/dist/files" "$KIT_ROOT/dist/templates" 0 "$target/.kit/backup"

  # --domain chỉ điền vào file profile vừa được tạo từ template, không sửa file có sẵn.
  if [[ -n "$domain" && "$profile_created" -eq 1 ]]; then
    sed -i.bak "s|^KIT_DOMAIN=.*|KIT_DOMAIN=$domain|" "$target/project/profile.env"
    rm -f "$target/project/profile.env.bak"
  fi

  # Trạng thái của gói ghi sau cùng: manifest rồi đến version.
  kit_write_state "$target" "$KIT_ROOT/dist/manifest" "$VERSION"

  if [[ "$setup" == 1 ]]; then
    printf 'Đã cài magento-docker-kit %s vào %s, chạy bin/download rồi bin/setup\n' "$VERSION" "$target"
    (cd "$target" && bin/download community "$magento" && bin/setup) || die "bin/download hoặc bin/setup lỗi, sửa rồi chạy lại từng lệnh trong $target"
    return 0
  fi

  cat <<EOF
Đã cài magento-docker-kit $VERSION vào $target

Các bước tiếp theo:
  cd $target
  bin/download community 2.4.7      # tải Magento vào src/
  bin/setup magento.test            # dựng stack và cài Magento
EOF
}

print_adopt_plan() {
  local plan="$1" action mode path n label
  printf 'Kế hoạch nhận dự án (%s)\n' "$VERSION"
  while IFS=$'\t' read -r action mode path; do
    case "$action" in
      write) label='ghi mới' ;;
      conflict) label='XUNG ĐỘT' ;;
      template) label='tạo từ template' ;;
      *) continue ;;
    esac
    printf '  %s: %s\n' "$label" "$path"
    if [[ "$action" == conflict ]]; then printf '                   gợi ý: %s\n' "$(kit_conflict_hint "$path")"; fi
  done < "$plan"
  n="$(kit_plan_count "$plan" skip)"
  printf '  (%s file trùng nội dung, sẽ ghi vào manifest)\n' "$n"
}

print_adopt_conflict_diffs() {
  local plan="$1" target="$2" action mode path
  while IFS=$'\t' read -r action mode path; do
    [[ "$action" == conflict ]] || continue
    printf '\n--- xung đột: %s\n' "$path"
    if [[ -f "$target/$path" && ! -L "$target/$path" ]]; then
      diff -u --label "local/$path" --label "$VERSION/$path" "$target/$path" "$KIT_ROOT/dist/files/$path" || true
    else
      printf '(local không phải file thường)\n'
    fi
  done < "$plan"
}

# Nhận một Docker root đang chạy. Không gọi docker, không đụng src/, .worktrees/,
# .active-src. Có xung đột và không --force thì không ghi gì (kể cả manifest),
# nên chạy lại bao nhiêu vòng cũng được cho tới khi hết xung đột.
cmd_adopt() {
  local target="$1" dry="${2:-0}" force="${3:-0}" plan="$WORK/plan" strays guesses="$WORK/guesses" profile_created=0 conflicts backup
  [[ -n "$target" ]] || die 'thiếu <dir>, ví dụ: install.sh adopt ~/Sites/shop'
  [[ -d "$target" ]] || die "$target không phải thư mục. Dự án mới thì dùng: install.sh new $target"
  target="$(cd "$target" && pwd -P)"
  [[ -f "$target/compose.yaml" ]] || die "$target không có compose.yaml, không giống một Docker root. Dự án mới thì dùng: install.sh new $target"
  if [[ -e "$target/.kit/manifest" ]]; then
    die "$target đã do gói quản lý (có .kit/manifest). Cập nhật bằng: bin/self-update"
  fi

  verify_source "$KIT_ROOT"
  [[ -e "$target/project/profile.env" ]] || profile_created=1

  # Chưa có manifest cũ: file khác nội dung là xung đột, file trùng là skip.
  kit_plan "$target" '' "$KIT_ROOT/dist/manifest" "$KIT_ROOT/dist/templates" > "$plan"
  print_adopt_plan "$plan"

  conflicts="$(kit_plan_count "$plan" conflict)"
  if [[ "$conflicts" -gt 0 ]]; then print_adopt_conflict_diffs "$plan" "$target"; fi

  strays="$(kit_stray_files "$target" "$KIT_ROOT/dist/manifest" "$KIT_ROOT/dist/templates")"
  if [[ -n "$strays" ]]; then
    printf '\nFile lạ (không thuộc gói, chỉ báo, không xoá):\n'
    printf '%s\n' "$strays" | sed 's/^/  /'
  fi

  : > "$guesses"
  if [[ "$profile_created" -eq 1 ]]; then
    kit_adopt_guess "$target" > "$guesses"
    printf '\nproject/profile.env sẽ được tạo với các khóa đoán từ file (KIT_DOMAIN để trống):\n'
    sed 's/^/  /' "$guesses"
  fi

  if [[ "$conflicts" -gt 0 && "$force" -eq 0 ]]; then
    printf '\ninstall.sh: %s xung đột cập nhật, chưa ghi gì. Chuyển phần tùy biến sang chỗ mở rộng rồi chạy lại adopt, hoặc dùng --force để sao lưu rồi ghi đè.\n' "$conflicts" >&2
    exit 1
  fi
  if [[ "$dry" -eq 1 ]]; then
    printf '\nChạy thử (--dry-run), không ghi gì.\n'
    exit 0
  fi

  backup="$target/.kit/backup/$(date +%Y%m%d-%H%M%S)"
  kit_apply "$target" "$plan" "$KIT_ROOT/dist/files" "$KIT_ROOT/dist/templates" "$force" "$backup"
  if [[ "$profile_created" -eq 1 && -s "$guesses" ]]; then
    kit_profile_apply_guesses "$target/project/profile.env" "$guesses"
  fi
  kit_write_state "$target" "$KIT_ROOT/dist/manifest" "$VERSION"

  printf '\nĐã nhận %s vào gói %s. Không đụng stack, src/ và .worktrees/.\n' "$target" "$VERSION"
  if [[ "$conflicts" -gt 0 ]]; then printf 'Đã sao lưu %s file xung đột vào %s\n' "$conflicts" "${backup#"$target"/}"; fi
  cat <<EOF

Các bước tiếp theo:
  - kiểm tra project/profile.env, điền KIT_DOMAIN và mọi dòng "adopt đoán"
  - file Compose có thể đã đổi: so bin/docker-compose config rồi mới bin/restart (adopt không restart stack)
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
      printf 'install.sh: lệnh không hợp lệ: %s\n' "$cmd" >&2
      usage >&2
      exit 2
      ;;
  esac
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --version)
        [[ $# -ge 2 ]] || die '--version cần giá trị vX.Y.Z'
        version="$2"
        shift 2
        ;;
      --version=*)
        version="${1#*=}"
        shift
        ;;
      --domain)
        [[ $# -ge 2 ]] || die '--domain cần giá trị, ví dụ x.test'
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
        [[ $# -ge 2 ]] || die '--magento cần phiên bản, ví dụ 2.4.7'
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
        [[ $# -ge 2 ]] || die '--source cần một thư mục hoặc tarball'
        source="$2"
        shift 2
        ;;
      --source=*)
        source="${1#*=}"
        shift
        ;;
      -*) die "tùy chọn không hợp lệ: $1" ;;
      *)
        [[ -z "$dir" ]] || die "thừa tham số: $1"
        dir="$1"
        shift
        ;;
    esac
  done
  if [[ -n "$version" && ! "$version" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    die "--version phải có dạng vX.Y.Z, nhận được: $version"
  fi
  if [[ -n "$domain" && ! "$domain" =~ ^[A-Za-z0-9]([A-Za-z0-9.-]*[A-Za-z0-9])?$ ]]; then
    die "--domain không hợp lệ: $domain"
  fi
  if [[ "$cmd" == new && ("$dry" -eq 1 || "$force" -eq 1) ]]; then
    die '--dry-run và --force chỉ dùng với adopt'
  fi
  if [[ "$cmd" == adopt ]]; then
    [[ -z "$domain" ]] || die 'adopt để trống KIT_DOMAIN, tự điền trong project/profile.env'
    [[ "$setup" -eq 0 && -z "$magento" ]] || die '--setup và --magento chỉ dùng với new'
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
