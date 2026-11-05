# Hướng dẫn cho agent: {{KIT_PROJECT_NAME}}

Magento 2 chạy trong Docker. Docker root là `{{KIT_ROOT}}`, code Magento ở `src/`, site `https://{{KIT_DOMAIN}}`.

## Ranh giới cứng

- Dừng ở nhánh `<type>/<slug>` đã push lên `{{KIT_GIT_REMOTE}}` cùng merge request đích `{{KIT_GIT_TARGET_BRANCH}}`. Người tự deploy.
- `{{KIT_GIT_BASE_BRANCH}}` và `{{KIT_GIT_TARGET_BRANCH}}` chỉ đọc: không push, không force-push vào hai nhánh này.
- Không deploy, không SSH vào production, không ghi dữ liệu production.
- `vendor/`, `generated/`, `pub/static/` là output: sửa nguồn rồi để lệnh sinh lại.
- Bí mật (`auth.json`, `env/*.env`, token) ở lại ngoài commit.

## Chạy lệnh

Host không có PHP. Mọi lệnh PHP và Magento chạy qua Docker root:

```bash
cd {{KIT_ROOT}} && bin/cli <lệnh>        # hoặc bin/magento, bin/composer
```

Container đang tắt thì chạy `bin/start`. Git chạy trong checkout của nhánh, `src/` hoặc `.worktrees/<dir>`.

## Worktree

- Tạo bằng `bin/wt create <type>/<slug>`, worktree nằm ở `.worktrees/<dir>`, nhánh tách từ `{{KIT_GIT_REMOTE}}/{{KIT_GIT_BASE_BRANCH}}`.
- Một stack, một DB, một `vendor/` cho mọi worktree. Chạy `bin/wt status` trước lệnh Magento, đổi bằng `bin/wt use <tên>`.
- `bin/wt` là đường duy nhất tạo và đổi worktree: `git worktree add` và sửa tay `.active-src` làm stack mount sai chỗ.

## Tri thức

- Skill `magento-workflow`: nạp khi chạy gate, commit, tạo MR hoặc đổi worktree.
- `project/agent/references/`: đọc khi việc chạm module, deploy hand-off hoặc quy ước riêng của dự án.
