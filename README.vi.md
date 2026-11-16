# magento-docker-kit

[English](README.md) | [Tiếng Việt](README.vi.md)

Một lớp phủ nhỏ cho Docker root dựng bằng [markshust/docker-magento](https://github.com/markshust/docker-magento):
một stack phục vụ nhiều Git worktree, một runner unit test duy nhất, và hook cho agent.
Phần Docker lấy từ upstream, kit chỉ thêm những gì upstream không có.
Không có installer, không có file profile, không có cấu hình sinh tự động.

## Gồm những gì

| Đường dẫn | Công dụng |
|---|---|
| `docker/bin/wt` | Tạo, chuyển và dọn worktree trong `.worktrees/`. Một stack, một DB, một `vendor/` |
| `docker/compose.worktree.yaml` | Overlay mount `.active-src` (worktree đang active) |
| `docker/bin/docker-compose` | File của upstream, thêm một khối nạp overlay khi `.active-src` là symlink |
| `docker/bin/test/unit` | Runner unit test duy nhất: serial, `--parallel` (ParaTest), `--wt`, `--xdebug`, `--coverage` |
| `docker/bin/phpcs` | File của upstream, thêm `--wt <name>` |
| `docker/bin/watch` | Watcher frontend đi theo `.active-src` |
| `docker/conf/php/opcache.ini` | Cấu hình OPcache cho môi trường dev |
| `agents/hooks/ui-conventions.sh` | Hook cho agent, chèn quy tắc UI của dự án khi sửa file giao diện |

## Thêm vào một Docker root

Dựng Docker root bằng upstream trước, rồi chép lớp phủ đè lên:

```bash
cp -a magento-docker-kit/docker/. /path/to/docker-root/
git -C /path/to/docker-root/src config wt.from origin/master    # nhánh gốc cho worktree mới
git -C /path/to/docker-root/src config wt.into origin/staging   # nhánh đích cho prune
```

Lệnh chép sẽ ghi đè file trùng tên. Nếu Docker root đã có `compose.worktree.yaml` hoặc
`bin/docker-compose` riêng thì so từng file thay vì chép đè.
Overlay chỉ phủ `app` và `phpfpm`. Service `phpfpm-xdebug` của upstream vẫn mount `./src`,
nên `--xdebug` chạy trên `src/`, không phải worktree đang active.

`wt.from` / `wt.into` nằm trong `src/.git/config`, không bị commit, và có thể thay theo từng lệnh
bằng `--from` / `--into`. Thiếu cả hai thì `bin/wt` dừng và chỉ cách đặt.

## Worktree

```bash
bin/wt create feat/checkout-rework   # nhánh mới từ wt.from (hoặc --from <remote>/<branch>)
bin/wt use feat-checkout-rework      # stack chuyển sang worktree đó (chỉ khởi động lại app và phpfpm)
bin/wt status
bin/wt list
bin/wt run <name> <command...>       # chạy một lệnh cho checkout đó trong container dùng một lần
bin/wt prune --dry-run               # worktree đã merge vào wt.into (hoặc --into) và worktree review
bin/wt doctor                        # so mount của phpfpm với .active-src
```

## Unit test

```bash
bin/test/unit --info                                 # runner sẽ làm gì: đọc cái này trước
bin/test/unit <path> --filter <regex>                # serial, trên checkout đang active
bin/test/unit --parallel <path>                      # ParaTest
bin/test/unit --wt <name> [--parallel] <path>        # container dùng một lần (agent dùng cách này)
bin/test/unit --xdebug <path>                        # qua bin/debug-cli của upstream
bin/test/unit --coverage <path>                      # báo cáo HTML trong dev/tests/unit/report
```

- Lệnh lấy từ composer script `test:unit` / `test:unit:parallel` của dự án. Không có thì dùng
  `vendor/bin/phpunit` / `vendor/bin/paratest -p ${TEST_PROCESSES:-2}` với `dev/tests/unit/phpunit.xml.dist`.
- `--parallel` mà không có ParaTest thì exit 2 kèm lệnh cài. Không bao giờ tự lùi về serial.
- `--wt` luôn tạo container mới: cùng image với `phpfpm`, không mạng, checkout và `vendor/` dùng chung
  ở chế độ chỉ đọc, tmpfs cho `generated/`, `var/` và `dev/tests/unit/tmp`. Nhiều lượt chạy cùng lúc
  không dùng chung các thư mục này. `composer.lock` khác lock của checkout đang active (lock mà `vendor/`
  dùng chung đang theo) thì dừng.
- Exit 2 là lỗi cách dùng hoặc thiếu điều kiện, mã khác là mã thoát của test.

## Hook quy tắc UI

```json
{
  "hooks": {
    "PreToolUse": [{
      "matcher": "Edit|Write|MultiEdit",
      "hooks": [{ "type": "command", "timeout": 10,
        "command": "\"$CLAUDE_PROJECT_DIR\"/.agents/hooks/ui-conventions.sh docs/agents/ui-conventions.md" }]
    }]
  }
}
```

Tham số là file quy tắc, tính từ gốc Magento. Hook đọc file đó trong checkout đang sửa, nếu không có
thì đọc trong `src/`, và cảnh báo ra stderr khi thiếu.

## Test

```bash
bash tests/run-all.sh
```

Test cần bash, git và jq. Docker được thay bằng bản giả ghi lại lời gọi.
