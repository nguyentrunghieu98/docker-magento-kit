# Git và merge request

Nhánh gốc và nhánh đích của dự án là chỉ đọc. Ranh giới cứng nằm trong `AGENTS.md`.

## Nhánh

- Tách từ `<remote>/<base branch>`, tên `<type>/<slug>`.
- `type` là `feat`, `fix`, `hotfix`, `refactor`, `perf` hoặc `chore`. `slug` là chữ thường, số và gạch ngang, 3 đến 50 ký tự.
- Tạo bằng `bin/wt create <type>/<slug>`, không dùng `git worktree add` tay.

## Commit

- Dòng đầu theo mẫu `<type>: <câu mệnh lệnh, tối đa 72 ký tự>`.
- Thân commit nêu module đã chạm, lệnh gate đã chạy, ghi chú deploy và cách lùi.
- Stage đường dẫn cụ thể, không `git add -A`. Không commit bí mật, file sinh tự động, `vendor/`, `generated/`, `pub/static/`.

## Push và merge request

- Push nhánh rồi mở MR vào `<target branch>`:

```bash
git push -u <remote> <branch> \
  -o merge_request.create \
  -o merge_request.target=<target branch> \
  -o merge_request.title='<tiêu đề>'
```

- Push option bị từ chối thì push thường, in URL MR rồi dừng.
- MR đích là nhánh đích của dự án, không phải nhánh gốc.
- Người deploy là người dùng. Agent dừng ở nhánh đã push và MR.

## Review

- Soát diff từ merge base với nhánh đích, không soát cả repo.
- Bốn nhóm cần soát: lỗi logic, ranh giới bị vượt, thiếu gate cho bề mặt đã sửa, thay đổi ngoài phạm vi.
- Phát hiện xếp theo mức Critical, High, Medium, Low. Không có Critical hoặc High thì mới đề nghị merge.
