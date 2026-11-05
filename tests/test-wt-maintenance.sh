#!/usr/bin/env bash
# Test S1 cho bin/wt adopt, prune và doctor. Docker root được cài bằng install.sh new
# --source, git là thật với một bare remote có master và staging, docker là bản giả
# ghi log. Phủ: adopt từ đường dẫn ngoài, prune với worktree sạch đã merge, có thay
# đổi, chưa merge, review và nằm ngoài vị trí chuẩn, doctor báo mount sai, base_url
# lệch, khóa lạ và khóa bắt buộc thiếu.
#
# Usage:  bash tests/test-wt-maintenance.sh
set -Eeuo pipefail
# shellcheck source=tests/lib.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)/lib.sh"

# Docker giả: `docker info` theo cờ online, `compose ps -q phpfpm` trả một id,
# `docker inspect` trả $KIT_TEST_MOUNT_SRC, và lệnh exec có core_config_data trả
# $KIT_TEST_BASE_URL (đại diện cho bin/mysql).
install_docker() {
  cat > "$SANDBOX/.fakebin/docker" <<'STUB'
#!/usr/bin/env bash
if [[ "${1:-}" == compose && "${2:-}" == version ]]; then exit 0; fi
printf 'docker %s\n' "$*" >> "${KIT_LOG_DIR:?}/docker.log"
case "$*" in
  info*)
    [[ -e "${KIT_DOCKER_ONLINE:?}" ]] && exit 0
    exit 1
    ;;
  *'ps -q phpfpm'*) printf 'cid-phpfpm\n' ;;
  inspect*) printf '%s\n' "${KIT_TEST_MOUNT_SRC:-}" ;;
  *core_config_data*) printf '%s\n' "${KIT_TEST_BASE_URL:-}" ;;
esac
exit 0
STUB
  chmod 755 "$SANDBOX/.fakebin/docker"
}

# Docker root `shop` với src/ là bản clone của bare remote (remote tên origin, có
# master và staging). master chứa .gitignore kiểu whitelist của Magento và
# composer.json, còn các file lõi (bootstrap.php, env.php...) chỉ có trong src/ và bị
# Git bỏ qua. Profile khai báo khóa Git, trừ khi $1 là no-git-keys.
new_root() {
  sandbox_new
  install_docker
  git_remote_new
  kit_new shop --domain shop.test > /dev/null
  ROOT="$SANDBOX/shop"
  SRC="$ROOT/src"

  rm -rf "$SRC"
  git clone -q "$BARE_REMOTE" "$SRC"
  git -C "$SRC" config user.name 'kit tests'
  git -C "$SRC" config user.email 'tests@example.invalid'
  git -C "$SRC" config commit.gpgsign false
  printf '*\n!.gitignore\n!composer.json\n!composer.lock\n' > "$SRC/.gitignore"
  printf '{"name": "kit/magento-test"}\n' > "$SRC/composer.json"
  printf '{"content-hash": "a"}\n' > "$SRC/composer.lock"
  git -C "$SRC" add .gitignore composer.json composer.lock
  git -C "$SRC" commit -q -m 'magento sandbox'
  git -C "$SRC" push -q origin master
  # staging xuất phát từ cùng cây nhánh gốc, giống dự án thật đã có .gitignore.
  git -C "$SRC" push -q origin master:staging

  mkdir -p "$SRC/app/etc" "$SRC/pub/media" "$SRC/vendor" "$SRC/node_modules" \
    "$SRC/bin" "$SRC/dev" "$SRC/lib" "$SRC/phpserver" "$SRC/setup"
  printf '<?php // bootstrap\n' > "$SRC/app/bootstrap.php"
  printf '<?php // autoload\n' > "$SRC/app/autoload.php"
  printf "<?php return ['db' => ['host' => 'db']];\n" > "$SRC/app/etc/env.php"
  printf '<?php // index\n' > "$SRC/pub/index.php"
  printf 'server {}\n' > "$SRC/nginx.conf.sample"

  if [[ "${1:-}" != no-git-keys ]]; then
    set_profile KIT_GIT_REMOTE origin
    set_profile KIT_GIT_BASE_BRANCH master
    set_profile KIT_GIT_TARGET_BRANCH staging
  fi
}

# Ghi KEY=value vào project/profile.env (thay dòng KEY= có sẵn).
set_profile() {
  sed -i "s|^$1=.*|$1=$2|" "$ROOT/project/profile.env"
}

wt() {
  run_in "$ROOT" bin/wt "$@"
}

# Đẩy commit lên staging của remote để branch coi như đã merge.
merge_into_staging() {
  git -C "$SRC" push -q origin "$1:staging"
}

# Tạo worktree <branch> bằng bin/wt, thêm một commit rồi trả đường dẫn qua WT_DIR.
make_commit_wt() {
  local branch="$1" dir="${1//\//-}"
  wt create "$branch"
  WT_DIR="$ROOT/.worktrees/$dir"
  git -C "$WT_DIR" config user.name t
  git -C "$WT_DIR" config user.email t@example.invalid
  git -C "$WT_DIR" config commit.gpgsign false
  printf '%s\n' "$branch" > "$WT_DIR/CHANGE-$dir"
  git -C "$WT_DIR" add -f "CHANGE-$dir"
  git -C "$WT_DIR" commit -q -m "change $branch"
}

test_adopt_moves_outside_worktree() {
  new_root
  git -C "$SRC" worktree add -q "$ROOT/ngoai" -b feature/lac-cho
  wt use "$ROOT/ngoai"
  assert_status_nonzero 'use vẫn từ chối đường dẫn ngoài'
  wt adopt "$ROOT/ngoai"
  assert_status 0 'adopt thoát 0'
  assert_dir "$ROOT/.worktrees/feature-lac-cho" 'worktree nằm ở .worktrees/<dir>'
  assert_absent "$ROOT/ngoai" 'thư mục cũ đã được dời đi'
  assert_equals 'feature/lac-cho' "$(git -C "$ROOT/.worktrees/feature-lac-cho" rev-parse --abbrev-ref HEAD)" 'branch giữ nguyên'
  assert_file "$ROOT/.worktrees/feature-lac-cho/app/etc/env.php" 'adopt chạy prepare, có env.php'
  assert_file "$ROOT/.worktrees/feature-lac-cho/nginx.conf" 'adopt chạy prepare, có nginx.conf'
  assert_contains 'bin/wt use' 'adopt gợi ý bước tiếp theo'
  wt use feature-lac-cho
  assert_status 0 'sau adopt thì use được'
}

test_adopt_detached_and_refusals() {
  new_root
  git -C "$SRC" worktree add -q --detach "$ROOT/ngoai-rv" HEAD
  wt adopt "$ROOT/ngoai-rv"
  assert_status 0 'adopt worktree detached'
  assert_dir "$ROOT/.worktrees/ngoai-rv" 'detached lấy tên thư mục gốc'
  wt adopt "$ROOT/khong-co"
  assert_status_nonzero 'adopt từ chối đường dẫn không tồn tại'
  mkdir "$SANDBOX/la"
  wt adopt "$SANDBOX/la"
  assert_status_nonzero 'adopt từ chối thư mục không phải worktree của src/'
  assert_contains 'Không phải worktree' 'adopt nêu lý do'
  wt adopt "$SRC"
  assert_status_nonzero 'adopt từ chối checkout chính'
  git -C "$SRC" worktree add -q "$ROOT/ngoai2" -b feature/trung
  wt create feature/trung2
  mkdir -p "$ROOT/.worktrees/feature-trung"
  wt adopt "$ROOT/ngoai2"
  assert_status_nonzero 'adopt từ chối khi đích đã tồn tại'
  assert_dir "$ROOT/ngoai2" 'worktree không bị dời khi đích bị chiếm'
}

test_adopt_refuses_active() {
  new_root
  git -C "$SRC" worktree add -q "$ROOT/ngoai" -b feature/phuc-vu
  ln -s "$ROOT/ngoai" "$ROOT/.active-src"
  wt adopt "$ROOT/ngoai"
  assert_status_nonzero 'adopt từ chối worktree đang phục vụ'
  assert_contains 'đang được phục vụ' 'adopt nêu lý do'
  assert_dir "$ROOT/ngoai" 'không bị dời'
}

test_prune_selects_by_state() {
  new_root
  make_commit_wt feature/da-merge
  make_commit_wt feature/chua-merge
  make_commit_wt feature/dang-sua
  printf 'dirty\n' >> "$ROOT/.worktrees/feature-dang-sua/composer.json"
  wt create --review-mr 7 --ref staging
  git -C "$SRC" worktree add -q "$ROOT/ngoai" -b feature/ngoai-chua-merge
  merge_into_staging feature/da-merge
  local before_branches
  before_branches="$(git -C "$SRC" branch --format='%(refname:short)' | sort)"

  wt prune --dry-run
  assert_status 0 'prune --dry-run thoát 0'
  local out="$OUTPUT" listed
  # Phần "Sẽ xoá" nằm trước phần "Còn thay đổi".
  listed="${out%%Còn thay đổi*}"
  if [[ "$listed" == *feature-da-merge* ]]; then
    pass_ 'dry-run liệt kê worktree sạch đã merge'
  else
    fail_ 'dry-run thiếu worktree đã merge'
  fi
  if [[ "$listed" == *review-mr7* ]]; then
    pass_ 'dry-run liệt kê worktree review'
  else
    fail_ 'dry-run thiếu worktree review'
  fi
  if [[ "$listed" != *feature-chua-merge* && "$listed" != *feature-dang-sua* ]]; then
    pass_ 'phần xoá không chứa worktree chưa merge hay đang sửa'
  else
    fail_ 'phần xoá lẫn worktree không được xoá'
  fi
  local dirty_part="${out#*Còn thay đổi}"
  dirty_part="${dirty_part%%Ngoài .worktrees*}"
  if [[ "$dirty_part" == *feature-dang-sua* ]]; then
    pass_ 'worktree có thay đổi nằm ở danh sách chỉ báo'
  else
    fail_ 'worktree có thay đổi không được báo'
  fi
  local outside_part="${out#*Ngoài .worktrees}"
  if [[ "$outside_part" == *ngoai* && "$outside_part" == *'bin/wt adopt'* ]]; then
    pass_ 'worktree chưa merge ngoài vị trí chuẩn có gợi ý adopt'
  else
    fail_ 'thiếu gợi ý adopt cho worktree ngoài'
  fi
  assert_dir "$ROOT/.worktrees/feature-da-merge" 'dry-run chưa xoá gì (đã merge)'
  assert_dir "$ROOT/.worktrees/review-mr7" 'dry-run chưa xoá gì (review)'

  wt prune
  assert_status 0 'prune thoát 0'
  assert_absent "$ROOT/.worktrees/feature-da-merge" 'prune xoá worktree sạch đã merge'
  assert_absent "$ROOT/.worktrees/review-mr7" 'prune xoá worktree review'
  assert_dir "$ROOT/.worktrees/feature-chua-merge" 'prune giữ worktree chưa merge'
  assert_dir "$ROOT/.worktrees/feature-dang-sua" 'prune giữ worktree có thay đổi'
  assert_dir "$ROOT/ngoai" 'prune không đụng worktree ngoài vị trí chuẩn'
  assert_equals "$before_branches" "$(git -C "$SRC" branch --format='%(refname:short)' | sort)" 'prune giữ nguyên mọi branch'
}

test_prune_skips_dirty_review_and_active() {
  new_root
  make_commit_wt feature/dang-phuc-vu
  merge_into_staging feature/dang-phuc-vu
  wt create --review-mr 9 --ref staging
  printf 'x\n' >> "$ROOT/.worktrees/review-mr9/composer.json"
  wt use feature-dang-phuc-vu
  wt prune
  assert_status 0 'prune thoát 0'
  assert_dir "$ROOT/.worktrees/feature-dang-phuc-vu" 'không xoá worktree đang phục vụ dù đã merge'
  assert_dir "$ROOT/.worktrees/review-mr9" 'không xoá worktree review còn thay đổi chưa commit'
}

test_prune_needs_git_keys() {
  new_root no-git-keys
  wt prune --dry-run
  assert_status_nonzero 'thiếu khóa Git thì prune dừng'
  assert_contains 'KIT_GIT_REMOTE' 'nêu khóa cần sửa'
  new_root
  set_profile KIT_GIT_TARGET_BRANCH khong-co-nhanh-nay
  wt prune --dry-run
  assert_status_nonzero 'ref đích không tồn tại thì dừng'
  assert_contains 'KIT_GIT_TARGET_BRANCH' 'nêu khóa cần sửa khi ref không có'
  wt prune --nope
  assert_status_nonzero 'prune từ chối tham số lạ'
}

test_doctor_mount_mismatch() {
  new_root
  set_docker_online
  wt create feature/one
  wt use feature-one
  export KIT_TEST_MOUNT_SRC="$SRC"
  export KIT_TEST_BASE_URL='https://shop.test/'
  wt doctor
  assert_status_nonzero 'mount sai thì doctor thoát khác 0'
  assert_contains "mount $SRC" 'doctor nêu mount thật'
  assert_contains "$ROOT/.worktrees/feature-one" 'doctor nêu đích của .active-src'
  export KIT_TEST_MOUNT_SRC="$ROOT/.worktrees/feature-one"
  : > "$KIT_LOG_DIR/docker.log"
  wt doctor
  assert_status 0 'mount đúng và base_url khớp thì doctor thoát 0'
  assert_contains 'phpfpm mount đúng' 'doctor xác nhận mount'
  assert_contains 'base_url khớp KIT_DOMAIN' 'doctor xác nhận base_url'
  assert_contains 'docker inspect' 'doctor dùng docker inspect' "$(cat "$KIT_LOG_DIR/docker.log")"
  assert_equals 1 "$(grep -c '^docker inspect' "$KIT_LOG_DIR/docker.log")" 'doctor chỉ gọi docker inspect một lần'
  unset KIT_TEST_MOUNT_SRC KIT_TEST_BASE_URL
}

test_doctor_base_url_mismatch() {
  new_root
  set_docker_online
  export KIT_TEST_MOUNT_SRC="$SRC"
  export KIT_TEST_BASE_URL='https://cu.example.com:8443/'
  wt doctor
  assert_status_nonzero 'base_url lệch thì doctor thoát khác 0'
  assert_contains 'cu.example.com' 'doctor nêu base_url trong DB'
  assert_contains 'KIT_DOMAIN=shop.test' 'doctor nêu KIT_DOMAIN'
  unset KIT_TEST_MOUNT_SRC KIT_TEST_BASE_URL
}

test_doctor_profile_keys() {
  new_root
  printf 'KIT_TYPO_KEY=1\n' >> "$ROOT/project/profile.env"
  set_profile KIT_GIT_TARGET_BRANCH ''
  wt doctor
  assert_status_nonzero 'khóa lạ và khóa thiếu thì doctor thoát khác 0'
  assert_contains 'Khóa lạ KIT_TYPO_KEY' 'doctor báo khóa lạ'
  assert_contains 'Thiếu khóa bắt buộc KIT_GIT_TARGET_BRANCH' 'doctor báo khóa bắt buộc thiếu'
  assert_docker_not_called 'doctor dừng trước khi kiểm Docker khi profile lỗi'
}

test_doctor_clean_offline() {
  new_root
  wt doctor
  assert_status 0 'profile đủ và docker tắt thì doctor thoát 0'
  assert_contains 'BỎ QUA: Docker daemon tắt' 'doctor nói rõ phần bị bỏ qua'
}

run_tests
finish
