# Ma trận gate

Chạy gate áp dụng cho bề mặt đã sửa. Mỗi gate ghi một dòng bằng chứng. Lệnh chạy từ Docker root theo `AGENTS.md`.

| Bề mặt thay đổi | Gate | Lệnh | Đạt khi |
|---|---|---|---|
| Mọi file PHP | cú pháp | `bin/cli php -l <file>` cho từng file đã sửa | không lỗi cú pháp |
| Mọi file PHP | coding standard | `bin/cli php vendor/bin/phpcs --standard=Magento2 --report=summary <đường dẫn>` | 0 error, warning đã đọc |
| Lớp, plugin, preference, observer, controller, CLI, cron, autoload | DI compile | `bin/cli php bin/magento setup:di:compile` | exit 0 |
| `db_schema.xml`, data patch, bật module | schema | `bin/magento setup:upgrade` rồi `cache:flush` | exit 0 |
| Layout, template, JS, LESS, CSS | build frontend | `npx grunt less:<theme>` hoặc lệnh của dự án | exit 0 |
| Layout, template, JS, LESS, CSS | giao diện | Playwright ở 1440 và 390, chụp màn hình | đúng thiết kế, không tràn ngang |
| Có `Test/Unit` | unit test | `bin/cli php vendor/bin/phpunit -c dev/tests/unit/phpunit.xml.dist <thư mục test>` | pass |
| Chuỗi i18n | static test | `bin/cli php vendor/bin/phpunit -c dev/tests/static/phpunit.xml.dist` (phạm vi hẹp) | pass |
| Queue, consumer, cron | chạy thật | khởi động lại consumer hoặc chạy cron, đọc `var/log` | không có lỗi mới |
| `app/etc/config.php` | diff | `git diff -- app/etc/config.php` | chỉ có dòng của module mình |
| Không có test tự động | kiểm tay | liệt kê bước và kết quả mong đợi | người dùng xác nhận |

## Ghi chú

- `setup:di:compile` và `setup:upgrade` chậm, chạy một lần cho mỗi thay đổi chứ không chạy theo từng file.
- Schema dùng chung cho mọi worktree. Báo người dùng trước khi chạy `setup:upgrade`.
- Gate giao diện cần stack đang chạy. Không có Playwright thì nói rõ là chưa kiểm, không gắn ảnh giả.
- Không báo PASS theo trí nhớ hay theo lần chạy trước. Chạy lại sau lần sửa cuối.
- Gate hỏng vì code có sẵn thì ghi FAIL kèm dòng lỗi, không sửa code ngoài phạm vi.

## Mẫu bằng chứng

```
php -l app/code/Vendor/Module/Model/Foo.php     | PASS
phpcs --report=summary app/code/Vendor/Module    | PASS (0 error, 2 warning)
setup:di:compile                                | N/A (không chạm DI)
unit test (Vendor_Module)                       | PASS (12 test)
Playwright 1440/390                             | PASS (ảnh đã lưu)
```
