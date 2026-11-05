#!/usr/bin/env bash
# Test S1 cho bin/wt (lõi): create từ remote, từ chối tên sai, use từ chối đường dẫn
# ngoài .worktrees/, prepare, list, status, path, shell, remove, mounts, và bin/watch
# theo dõi đích của .active-src. Docker root được cài bằng install.sh new --source,
# git là thật với một bare remote có master và staging, docker là bản giả ghi log.
# Nâng từ tests/test-magento-wt.sh của dự án Format.
#
# Usage:  bash tests/test-wt.sh
set -Eeuo pipefail
# shellcheck source=tests/lib.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)/lib.sh"

# Docker giả: ghi mọi lệnh, `docker info` theo cờ online, và khi online thì
# `compose ... ps --services --status running` trả app, phpfpm, db. KIT_TEST_FAIL_UP=1
# làm `compose ... up` thất bại.
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
  *'ps --services --status running'*)
    printf '%s\n' app phpfpm db
    ;;
  *' up '*)
    [[ "${KIT_TEST_FAIL_UP:-0}" == 1 ]] && exit 1
    ;;
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

calls() { cat "$KIT_LOG_DIR/docker.log" 2> /dev/null || true; }

test_help() {
  new_root
  wt help
  assert_status 0 'help thoát 0'
  assert_contains 'Cách dùng: bin/wt <lệnh>' 'help in dòng cách dùng'
  local cmd
  for cmd in 'create <type>/<slug>' 'use <tên|đường dẫn|branch>' 'list' 'status' 'path' 'prepare' 'shell' 'remove' 'mounts'; do
    assert_contains "$cmd" "help liệt kê '$cmd'"
  done
  wt frobnicate
  assert_status_nonzero 'lệnh lạ thoát khác 0'
  assert_contains 'Lệnh không tồn tại: frobnicate' 'lệnh lạ được gọi tên'
}

test_create_from_remote_base() {
  new_root
  # Đẩy thêm một commit lên master của remote mà src/ chưa có, để chứng minh create
  # fetch và tạo từ origin/master chứ không từ nhánh local.
  local other="$SANDBOX/other"
  git clone -q "$BARE_REMOTE" "$other"
  git -C "$other" config user.name t
  git -C "$other" config user.email t@example.invalid
  git -C "$other" config commit.gpgsign false
  printf 'moi\n' > "$other/MOI"
  git -C "$other" add -f MOI
  git -C "$other" commit -q -m 'remote moi'
  git -C "$other" push -q origin master
  local remote_sha local_sha
  remote_sha="$(git -C "$other" rev-parse HEAD)"
  local_sha="$(git -C "$SRC" rev-parse master)"
  assert_equals 1 "$([[ "$remote_sha" != "$local_sha" ]] && echo 1 || echo 0)" 'tiền đề: master local đã cũ hơn remote'

  wt create feature/gio-hang
  local wt_dir="$ROOT/.worktrees/feature-gio-hang"
  assert_status 0 'create thoát 0'
  assert_dir "$wt_dir" '<dir> là tên branch đổi / thành -'
  assert_equals 'feature/gio-hang' "$(git -C "$wt_dir" rev-parse --abbrev-ref HEAD)" 'worktree nằm trên branch mới'
  assert_equals "$remote_sha" "$(git -C "$wt_dir" rev-parse HEAD)" 'branch được tạo từ origin/master sau fetch, không từ master local'
  assert_equals "$local_sha" "$(git -C "$SRC" rev-parse master)" 'master local không bị đụng tới'
  assert_file "$wt_dir/MOI" 'worktree có commit mới của remote'
  assert_symlink_to "$ROOT/.active-src" "$SRC" 'create tạo .active-src -> src khi chưa có'
}

test_create_prepares_core_files() {
  new_root
  wt create fix/loi-thanh-toan
  local d="$ROOT/.worktrees/fix-loi-thanh-toan"
  assert_files_equal "$SRC/app/bootstrap.php" "$d/app/bootstrap.php" 'create chép app/bootstrap.php'
  assert_files_equal "$SRC/pub/index.php" "$d/pub/index.php" 'create chép pub/index.php'
  assert_files_equal "$SRC/app/etc/env.php" "$d/app/etc/env.php" 'create chép app/etc/env.php'
  assert_files_equal "$SRC/nginx.conf.sample" "$d/nginx.conf" 'create sinh nginx.conf từ nginx.conf.sample'
  assert_equals '' "$(git -C "$d" status --porcelain)" 'worktree vừa chuẩn bị không có file bẩn hay chưa theo dõi'
}

test_create_rejects_bad_names() {
  new_root
  local bad
  for bad in 'gio-hang' 'Feature/x' 'feature/' '/x' 'feature/a b' 'feature/..x' 'feature/x.lock' 'feature//x'; do
    wt create "$bad"
    assert_status_nonzero "create từ chối tên '$bad'"
  done
  wt create gio-hang
  assert_contains '<type>/<slug>' 'lỗi nêu mẫu tên đúng'
  assert_absent "$ROOT/.worktrees" 'tên sai không tạo gì'
  assert_absent "$ROOT/.active-src" 'tên sai không tạo .active-src'
}

test_create_missing_git_keys() {
  new_root no-git-keys
  wt create feature/x
  assert_status_nonzero 'create dừng khi thiếu khóa Git'
  assert_contains 'KIT_GIT_REMOTE' 'lỗi chỉ rõ KIT_GIT_REMOTE'
  assert_contains 'KIT_GIT_BASE_BRANCH' 'lỗi chỉ rõ KIT_GIT_BASE_BRANCH'
  assert_absent "$ROOT/.worktrees/feature-x" 'không tạo worktree khi thiếu khóa'
  set_profile KIT_GIT_REMOTE origin
  wt create feature/x
  assert_status_nonzero 'vẫn dừng khi còn thiếu một khóa'
  assert_contains 'KIT_GIT_BASE_BRANCH' 'lỗi chỉ ra khóa còn thiếu'
  assert_not_contains 'KIT_GIT_REMOTE' 'lỗi không nhắc khóa đã điền'
}

test_create_bad_ref_after_fetch() {
  new_root
  set_profile KIT_GIT_BASE_BRANCH khong-co-nhanh-nay
  wt create feature/x
  assert_status_nonzero 'create dừng khi nhánh gốc không có trên remote'
  assert_contains 'KIT_GIT_BASE_BRANCH' 'lỗi chỉ rõ khóa cần sửa'
  assert_contains 'origin/khong-co-nhanh-nay' 'lỗi nêu ref không tồn tại'
  assert_absent "$ROOT/.worktrees/feature-x" 'không tạo worktree'
  set_profile KIT_GIT_BASE_BRANCH master
  set_profile KIT_GIT_REMOTE khong-co-remote
  wt create feature/x
  assert_status_nonzero 'create dừng khi remote không có trong src/'
  assert_contains 'KIT_GIT_REMOTE=khong-co-remote' 'lỗi chỉ rõ remote sai'
}

test_create_refuses_existing_branch_and_dir() {
  new_root
  wt create feature/a
  assert_status 0 'lần tạo đầu thành công'
  wt create feature/a
  assert_status_nonzero 'tạo lại cùng tên bị từ chối'
  git -C "$SRC" branch feature/cu
  wt create feature/cu
  assert_status_nonzero 'branch local đã có bị từ chối, không tạo từ nhánh local'
  assert_contains 'đã tồn tại' 'lỗi nêu lý do'
}

test_create_review_mr() {
  new_root
  local other="$SANDBOX/other" sha
  git clone -q "$BARE_REMOTE" "$other"
  git -C "$other" config user.name t
  git -C "$other" config user.email t@example.invalid
  git -C "$other" config commit.gpgsign false
  git -C "$other" checkout -q -b mr-seven
  printf 'mr\n' > "$other/MR"
  git -C "$other" add -f MR
  git -C "$other" commit -q -m 'mr 7'
  sha="$(git -C "$other" rev-parse HEAD)"
  git -C "$other" push -q origin "mr-seven:refs/merge-requests/7/head"

  wt create --review-mr 7
  local d="$ROOT/.worktrees/review-mr7"
  assert_status 0 'create --review-mr thoát 0'
  assert_dir "$d" 'worktree review tên review-mr<id>'
  assert_equals 'HEAD' "$(git -C "$d" rev-parse --abbrev-ref HEAD)" 'worktree review là detached'
  assert_equals "$sha" "$(git -C "$d" rev-parse HEAD)" 'worktree review nằm đúng commit của MR'
  assert_file "$d/MR" 'worktree review có nội dung MR'

  wt create --review-mr abc
  assert_status_nonzero 'số MR không phải số bị từ chối'
  wt create --review-mr 99
  assert_status_nonzero 'MR không có trên remote bị từ chối'
  assert_contains '--ref' 'lỗi gợi ý --ref'
  wt create --review-mr 8 --ref staging
  assert_status 0 'create --review-mr --ref lấy từ origin/<branch>'
  assert_equals "$(git -C "$SRC" rev-parse origin/staging)" "$(git -C "$ROOT/.worktrees/review-mr8" rev-parse HEAD)" 'review --ref nằm đúng commit của origin/staging'
}

test_use_switches_and_recreates_php_only() {
  new_root
  wt create feature/one
  set_docker_online
  reset_calls
  wt use feature-one
  assert_status 0 'use thoát 0 khi Docker online'
  assert_symlink_to "$ROOT/.active-src" "$ROOT/.worktrees/feature-one" 'use trỏ .active-src vào worktree'
  assert_file_matches "$KIT_LOG_DIR/docker.log" ' stop app phpfpm$' 'chỉ dừng app và phpfpm'
  assert_file_matches "$KIT_LOG_DIR/docker.log" ' up -d --no-deps --force-recreate app phpfpm$' 'app và phpfpm được tạo lại'
  assert_file_does_not_match "$KIT_LOG_DIR/docker.log" ' (stop|up) .*(db|redis|opensearch|rabbitmq)' 'db, redis, search, queue không bị đụng'
  assert_file_matches "$KIT_LOG_DIR/docker.log" 'exec phpfpm bin/magento cache:clean' 'use xoá cache Magento'
  assert_contains 'Đang phục vụ: feature-one' 'use báo worktree mới'
}

test_use_by_branch_name_and_already_active() {
  new_root
  wt create feature/one
  set_docker_online
  wt use feature/one
  assert_status 0 'use nhận tên branch'
  reset_calls
  wt use feature-one
  assert_status 0 'use lại cùng worktree thoát 0'
  assert_contains 'Đang phục vụ sẵn' 'use lại báo đã phục vụ'
  assert_file_does_not_match "$KIT_LOG_DIR/docker.log" ' (stop|up) ' 'use lại không restart'
}

test_use_without_docker() {
  new_root
  wt create feature/one
  reset_calls
  wt use feature-one
  assert_status 0 'use thoát 0 khi Docker tắt'
  assert_symlink_to "$ROOT/.active-src" "$ROOT/.worktrees/feature-one" 'use vẫn đổi .active-src'
  assert_contains 'bin/start' 'use nhắc khởi động stack'
  assert_file_does_not_match "$KIT_LOG_DIR/docker.log" ' (stop|up) ' 'không restart khi Docker tắt'
}

test_use_back_to_main() {
  new_root
  wt create feature/one
  wt use feature-one
  wt use main
  assert_status 0 'use main thoát 0'
  assert_symlink_to "$ROOT/.active-src" "$SRC" 'use main trỏ lại src/'
}

test_use_rolls_back_on_failure() {
  new_root
  wt create feature/one
  set_docker_online
  reset_calls
  export KIT_TEST_FAIL_UP=1
  wt use feature-one
  unset KIT_TEST_FAIL_UP
  assert_status_nonzero 'use lỗi khi tạo lại container lỗi'
  assert_contains 'Đã huỷ việc đổi worktree' 'use báo đã huỷ'
  assert_symlink_to "$ROOT/.active-src" "$SRC" '.active-src được trả về như cũ'
  assert_file_line_count 2 "$KIT_LOG_DIR/docker.log" ' up -d --no-deps --force-recreate ' 'khôi phục thử tạo lại lần nữa'
  assert_file_does_not_match "$KIT_LOG_DIR/docker.log" 'cache:clean' 'đổi lỗi không xoá cache'
}

test_use_refuses_outside_paths() {
  new_root
  wt create feature/one
  mkdir -p "$ROOT/.codex-worktrees"
  git -C "$SRC" worktree add -q "$ROOT/.codex-worktrees/agent1" -b agent1
  printf '{}\n' > "$ROOT/.codex-worktrees/agent1/composer.json"
  wt use "$ROOT/.codex-worktrees/agent1"
  assert_status_nonzero 'use từ chối worktree ngoài .worktrees/'
  assert_contains 'bin/wt adopt' 'lỗi gợi ý adopt'
  assert_contains '.codex-worktrees/agent1' 'lỗi nêu đường dẫn bị từ chối'
  wt use agent1
  assert_status_nonzero 'use từ chối cả khi gọi bằng tên branch'
  assert_contains 'bin/wt adopt' 'lỗi gợi ý adopt khi gọi bằng tên branch'
  local plain="$SANDBOX/not-a-worktree"
  mkdir -p "$plain"
  wt use "$plain"
  assert_status_nonzero 'use từ chối thư mục tuỳ ý'
  assert_symlink_to "$ROOT/.active-src" "$SRC" '.active-src không đổi sau các lần bị từ chối'
}

test_prepare_restores_and_preserves() {
  new_root
  wt create feature/one
  local d="$ROOT/.worktrees/feature-one"
  rm -f "$d/app/etc/env.php" "$d/pub/index.php"
  printf '<?php // tuy chinh\n' > "$d/app/bootstrap.php"
  wt prepare feature-one
  assert_status 0 'prepare thoát 0'
  assert_files_equal "$SRC/app/etc/env.php" "$d/app/etc/env.php" 'prepare chép lại app/etc/env.php'
  assert_files_equal "$SRC/pub/index.php" "$d/pub/index.php" 'prepare chép lại pub/index.php'
  assert_equals '<?php // tuy chinh' "$(head -n 1 "$d/app/bootstrap.php")" 'prepare giữ file đã có'
  assert_equals '' "$(git -C "$d" status --porcelain)" 'prepare không để lại file chưa theo dõi'
}

test_prepare_warns_on_lock_mismatch() {
  new_root
  wt create feature/one
  printf '{"content-hash": "b"}\n' > "$ROOT/.worktrees/feature-one/composer.lock"
  wt prepare feature-one
  assert_status 0 'prepare thoát 0 khi composer.lock khác'
  assert_contains 'composer.lock khác với src/' 'prepare cảnh báo composer.lock lệch'
}

test_prepare_runs_agent_install_only_when_present() {
  new_root
  wt create feature/one
  assert_status 0 'create thoát 0 khi chưa có bin/agent'
  rm -f "$ROOT/bin/agent"
  cat > "$ROOT/bin/agent" <<'STUB'
#!/usr/bin/env bash
printf 'agent %s cwd=%s\n' "$*" "$PWD" >> "${KIT_LOG_DIR:?}/agent.log"
STUB
  chmod 755 "$ROOT/bin/agent"
  wt prepare feature-one
  assert_status 0 'prepare thoát 0 khi có bin/agent'
  assert_file_line "$KIT_LOG_DIR/agent.log" "agent install cwd=$ROOT/.worktrees/feature-one" 'prepare chạy bin/agent install trong worktree'
  : > "$KIT_LOG_DIR/agent.log"
  wt prepare main
  assert_equals '' "$(cat "$KIT_LOG_DIR/agent.log")" 'prepare main không cài kit agent'
}

test_list_marks_active() {
  new_root
  wt create feature/one
  wt use feature-one
  wt list
  assert_status 0 'list thoát 0'
  assert_contains 'Đang phục vụ: feature-one' 'list báo worktree đang phục vụ'
  local line stars=0 star_line=''
  while IFS= read -r line; do
    if [[ "$line" == '*'* ]]; then
      stars=$((stars + 1))
      star_line="$line"
    fi
  done <<< "$OUTPUT"
  assert_equals 1 "$stars" 'list đánh dấu đúng một worktree'
  assert_contains 'feature-one' 'dấu * nằm ở worktree đang phục vụ' "$star_line"
  assert_contains 'main' 'list có checkout chính'
}

test_list_before_any_worktree() {
  new_root
  wt list
  assert_status 0 'list chạy được khi chưa có .active-src'
  assert_contains 'Đang phục vụ: main' 'chưa có .active-src thì coi như phục vụ src/'
  assert_absent "$ROOT/.active-src" 'list không tạo .active-src'
}

test_path_resolves_and_fails() {
  new_root
  wt create feature/dup
  wt create hotfix/dup
  wt path main
  assert_equals "$SRC" "$OUTPUT" 'path main in src/'
  wt path feature-dup
  assert_equals "$ROOT/.worktrees/feature-dup" "$OUTPUT" 'path nhận tên thư mục'
  wt path feature/dup
  assert_equals "$ROOT/.worktrees/feature-dup" "$OUTPUT" 'path nhận tên branch'
  wt path khong-co
  assert_status_nonzero 'path tên lạ thoát khác 0'
  assert_contains 'Không có worktree nào tên: khong-co' 'path báo tên lạ'
  wt path dup
  assert_status_nonzero 'path tên không có thật thoát khác 0'
}

test_status() {
  new_root
  wt create feature/one
  wt use feature-one
  wt status
  assert_status 0 'status thoát 0'
  assert_contains 'Đang phục vụ: feature-one' 'status báo worktree đang phục vụ'
  assert_contains 'Branch: feature/one' 'status báo branch'
  assert_contains 'Docker daemon đang tắt' 'status báo Docker tắt'
  set_docker_online
  reset_calls
  wt status
  assert_file_matches "$KIT_LOG_DIR/docker.log" ' ps$' 'status hỏi compose ps khi Docker online'
}

test_mounts() {
  new_root
  wt mounts
  assert_status_nonzero 'mounts lỗi khi Docker tắt'
  assert_contains 'Docker daemon đang tắt' 'mounts giải thích'
  set_docker_online
  reset_calls
  wt mounts
  assert_status 0 'mounts thoát 0 khi Docker online'
  assert_file_matches "$KIT_LOG_DIR/docker.log" ' config$' 'mounts hỏi compose config'
}

test_shell() {
  new_root
  wt create feature/one
  cat > "$SANDBOX/.fakebin/stub-shell" <<'STUB'
#!/usr/bin/env bash
printf 'shell-pwd=%s\n' "$PWD"
STUB
  chmod 755 "$SANDBOX/.fakebin/stub-shell"
  SHELL="$SANDBOX/.fakebin/stub-shell" wt shell feature-one
  assert_status 0 'shell thoát 0'
  assert_contains "shell-pwd=$ROOT/.worktrees/feature-one" 'shell mở trong worktree'
  wt shell
  assert_status_nonzero 'shell không tên thoát khác 0'
  assert_contains 'Cách dùng: bin/wt shell' 'shell không tên in cách dùng'
}

test_remove() {
  new_root
  wt create feature/one
  wt remove main
  assert_status_nonzero 'remove từ chối checkout chính'
  assert_contains 'Không xoá được checkout chính' 'remove nêu lý do'
  wt use feature-one
  wt remove feature-one
  assert_status_nonzero 'remove từ chối worktree đang phục vụ'
  assert_contains 'Không xoá được worktree đang phục vụ' 'remove nêu lý do khi đang phục vụ'
  assert_dir "$ROOT/.worktrees/feature-one" 'worktree vẫn còn'
  wt use main
  wt remove feature-one
  assert_status 0 'remove xoá worktree không phục vụ'
  assert_contains 'branch local được giữ' 'remove báo giữ branch'
  assert_absent "$ROOT/.worktrees/feature-one" 'thư mục worktree đã mất'
  assert_cmd_status 0 'branch local vẫn còn' git -C "$SRC" show-ref --verify --quiet refs/heads/feature/one
  assert_dir "$ROOT/.worktrees" '.worktrees/ vẫn còn'
}

test_remove_refuses_dirty_and_outside() {
  new_root
  wt create feature/one
  printf '\n' >> "$ROOT/.worktrees/feature-one/composer.json"
  wt remove feature-one
  assert_status_nonzero 'remove từ chối worktree còn file đã sửa'
  assert_dir "$ROOT/.worktrees/feature-one" 'worktree được giữ'
  git -C "$SRC" worktree add -q "$ROOT/ngoai" -b agent1
  wt remove "$ROOT/ngoai"
  assert_status_nonzero 'remove từ chối đường dẫn ngoài .worktrees/'
  assert_dir "$ROOT/ngoai" 'worktree ngoài không bị xoá'
}

test_overlay_mounts_active_src_and_shares_dirs() {
  local f="$KIT_REPO_ROOT/dist/files/compose.worktree.yaml" t
  assert_file_matches "$f" '\./\.active-src:/var/www/html:cached' 'overlay mount .active-src vào /var/www/html'
  for t in vendor node_modules pub/media; do
    assert_file_matches "$f" "\./src/$t:/var/www/html/$t" "overlay dùng chung $t từ src/"
  done
  for t in app/code app/design app/etc generated var; do
    assert_file_matches "$f" "\./\.active-src/$t:/var/www/html/$t" "overlay lấy $t từ worktree, không bị ./src che"
  done
}

test_watch_follows_active_src() {
  command -v node > /dev/null 2>&1 || { pass_ 'bỏ qua test watch vì thiếu node'; return 0; }
  new_root
  run_in "$ROOT" node bin/watch --print-target
  assert_equals "$SRC" "$OUTPUT" 'chưa có .active-src thì watch theo dõi src/'
  wt create feature/one
  assert_equals "$SRC" "$(cd "$ROOT" && node bin/watch --print-target)" '.active-src -> src thì watch theo dõi src/'
  wt use feature-one
  run_in "$ROOT" node bin/watch --print-target
  assert_equals "$ROOT/.worktrees/feature-one" "$OUTPUT" 'watch theo dõi đích của .active-src'
}

run_tests
finish
