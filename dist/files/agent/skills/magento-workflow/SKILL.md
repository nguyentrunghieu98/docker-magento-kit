---
name: magento-workflow
description: Tri thức chạy lệnh Magento trong Docker, ma trận gate, quy ước Git và merge request, quy tắc worktree của gói. Nạp khi chạy kiểm tra cho một thay đổi, khi commit hoặc tạo MR, hoặc khi đổi worktree.
---

# magento-workflow

Đây là tri thức về cách làm, không phải trình tự làm việc. Trình tự do bộ skill quy trình của harness quyết định.

`AGENTS.md` ở Docker root là nguồn của ranh giới cứng, cách chạy lệnh và quy tắc worktree. Skill này chỉ mở rộng ba phần:

- `references/gates.md` — ma trận gate theo bề mặt thay đổi, mẫu bằng chứng.
- `references/git-mr.md` — nhánh, commit, push, merge request, quy ước review.
- `references/worktree.md` — `bin/wt` và thay đổi checkout mà stack đang phục vụ.

Mọi lệnh PHP và Magento chạy qua Docker root bằng `bin/cli` hoặc `bin/magento`. Container tắt thì chạy `bin/start`.
