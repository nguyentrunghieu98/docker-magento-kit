# Worktree

Một stack, một DB, một `vendor/`, một `node_modules/` và một `pub/media/` cho mọi worktree. Chỉ một checkout được phục vụ tại một thời điểm.

## Lệnh

- `bin/wt create <type>/<slug>`: tạo worktree ở `.worktrees/<dir>`, nhánh tách từ `<remote>/<base branch>`.
- `bin/wt create --review-mr <id> [--ref <branch>]`: tạo worktree detached `review-mr<id>` để soát MR.
- `bin/wt use <tên|đường dẫn>`: đổi checkout đang phục vụ. Chỉ nhận checkout chính và đường dẫn trong `.worktrees/`.
- `bin/wt status`: cho biết checkout đang phục vụ. Chạy trước mọi lệnh Magento.
- `bin/wt prepare`: chép file lõi mà checkout còn thiếu và cài kit agent.
- `bin/wt adopt <đường dẫn>`: dời worktree tạo sai chỗ về vị trí chuẩn rồi `prepare`.
- `bin/wt prune --dry-run`: in danh sách sẽ xoá. `bin/wt prune` xoá đúng danh sách đó, giữ branch.
- `bin/wt doctor`: so mount thật của phpfpm với đích `.active-src`, cảnh báo `base_url` lệch `KIT_DOMAIN` và khóa profile sai.

## Quy tắc

- `bin/wt` là đường duy nhất tạo và đổi worktree. Sửa tay `.active-src` hoặc `git worktree add` làm stack mount sai chỗ.
- `prune` giữ lại worktree còn thay đổi, worktree đang phục vụ và worktree chưa merge. Duyệt `--dry-run` trước khi xoá.
- Worktree dùng chung DB nên thay đổi schema ảnh hưởng mọi worktree.
