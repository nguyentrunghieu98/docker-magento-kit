# magento-docker-kit

Gói đóng sẵn môi trường Docker cho dự án Magento 2, kèm công cụ worktree và kit agent, cài và cập nhật vào nhiều dự án.

## Gói và dự án

**Gói**:
Bản phân phối `magento-docker-kit` ở một phiên bản semver cụ thể, gồm mọi file do gói quản lý.
_Avoid_: kit (khi nói về toàn bộ gói), template, fork

**Dự án**:
Một cài đặt cụ thể của gói cho một codebase Magento, ví dụ Format.
_Avoid_: project instance, site

**Docker root**:
Thư mục gốc của một dự án, nơi gói được cài và chứa `src/`.
_Avoid_: project root (dễ nhầm với gốc Magento)

**File của gói**:
File do gói sở hữu, được ghi đè khi cập nhật và được theo dõi bằng checksum.
_Avoid_: core file, base file

**File của dự án**:
File dự án sở hữu, chỉ được tạo một lần từ template và không bao giờ bị gói ghi đè.
_Avoid_: local file, override

**Profile dự án**:
Tập gồm file profile, các file env, file override của Compose và thư mục `project/`, mô tả mọi thứ riêng của một dự án.
_Avoid_: config, settings

**File profile**:
File duy nhất chứa giá trị mà gói đọc để tự cấu hình cho một dự án, như domain, remote và nhánh Git. Nó không chứa bí mật.
_Avoid_: config, `.env`, settings

**Trạng thái runtime**:
Giá trị cục bộ do lệnh của gói ghi ra trong lúc chạy, ví dụ Xdebug đang bật hay tắt. Nó không được commit và không thuộc profile dự án.
_Avoid_: state, cache

**Chỗ mở rộng**:
Nơi hợp lệ để dự án thay đổi hành vi của gói mà không sửa file của gói.
_Avoid_: hook, patch, customization

**Xung đột cập nhật**:
Một file của gói đã bị sửa tay ở dự án và khác với cả bản lúc cài lẫn bản mới.
_Avoid_: merge conflict, diff

**Nhận dự án**:
Đưa một Docker root đang chạy sẵn về dạng do gói quản lý mà không dựng lại dữ liệu.
_Avoid_: migrate, import, cài đè

**Cutover**:
Thời điểm stack của dự án được dừng và khởi động lại trên bộ file mới. Trước thời điểm này, lùi lại không làm ngừng dịch vụ.
_Avoid_: deploy, go-live, chuyển đổi

**File lạ**:
File ở Docker root không thuộc gói, không phải template và không phải trạng thái của gói.
_Avoid_: untracked file, rác

## Worktree

**Checkout chính**:
Repo Magento tại `src/` của Docker root.
_Avoid_: main worktree, master checkout

**Worktree**:
Một checkout phụ của repo Magento, nằm ở vị trí chuẩn trong Docker root.
_Avoid_: lane, slot, sandbox

**Worktree đang phục vụ**:
Checkout duy nhất mà stack đang mount và phục vụ tại một thời điểm.
_Avoid_: active lane, current slot

**Nhận worktree**:
Đưa một worktree tạo sai chỗ về vị trí chuẩn để nó được phép phục vụ.
_Avoid_: import, migrate

## Agent

**Harness**:
Công cụ chạy agent đọc kit agent của dự án, ví dụ Claude Code, Codex hay DSH.
_Avoid_: tool, IDE, client

**Kit agent**:
Phần của gói cung cấp tri thức Magento cho agent: cách chạy lệnh, gate verify, quy ước Git, ranh giới cứng. Nó không định nghĩa quy trình làm việc.
_Avoid_: workflow kit, agent workflow

**Bộ skill quy trình**:
Bộ skill cài vào harness, quyết định trình tự làm việc như grill, spec, ticket, implement và review. Nó nằm ngoài gói.
_Avoid_: stage, S0 đến S6

**Role**:
Một subagent có tên, được định nghĩa bằng ranh giới quyền của nó, không bằng model chạy nó.
_Avoid_: worker, teammate, persona

**Hạng model**:
Mức năng lực trừu tượng mà một role cần (`fast`, `default`, `deep`), được quy đổi sang model thật theo từng harness.
_Avoid_: tier, model name
