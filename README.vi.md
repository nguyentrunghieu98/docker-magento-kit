# magento-docker-kit

[English](README.md) | [Tiếng Việt](README.vi.md)

Bộ môi trường Docker cài được cho dự án Magento 2, gồm bản chụp ghim của
[markshust/docker-magento](https://github.com/markshust/docker-magento), image PHP dựng sẵn,
công cụ worktree dùng chung một stack và một kit tri thức nhỏ cho agent lập trình.

![test](https://github.com/nguyentrunghieu98/docker-magento-kit/actions/workflows/test.yml/badge.svg)

## Gói có gì

- Docker root chạy Magento 2 với app, php-fpm, MariaDB hoặc MySQL, Redis/Valkey, OpenSearch, RabbitMQ và mail catcher cục bộ.
- Image PHP 8.2, 8.3 và 8.4 dựng sẵn, có biến thể Xdebug, phát hành qua GHCR.
- `bin/wt` giữ một stack và một database khi chuyển qua lại giữa các worktree Git.
- File profile của dự án (`project/profile.env`) chứa mọi thứ riêng của từng dự án, nhờ đó cùng một gói phục vụ nhiều dự án.
- Cập nhật ba chiều với manifest có checksum và chỗ sao lưu, kèm `adopt` cho Docker root đang chạy sẵn.
- Kit agent: `AGENTS.md`, `CLAUDE.md`, ba role và skill `magento-workflow`, cài cho cả Claude Code và Codex.

## Yêu cầu

- Docker Engine với Compose v2, cấp cho Docker ít nhất 6 GB bộ nhớ.
- `bash`, `git`, `curl` và `tar`.
- Thông tin đăng nhập Magento cho `bin/download` khi cài từ đầu (`auth.json` hoặc `bin/setup-composer-auth`).

## Cài dự án mới

Từ bản checkout của gói, không cần tag phát hành:

```bash
git clone https://github.com/nguyentrunghieu98/docker-magento-kit.git
cd docker-magento-kit
./install.sh new ../shop --source . --domain shop.test
```

Từ một tag phát hành:

```bash
curl -fsSL https://raw.githubusercontent.com/nguyentrunghieu98/docker-magento-kit/v1.0.0/install.sh \
  | bash -s -- new shop --domain shop.test
```

`install.sh new` chỉ ghi file của gói và template vào thư mục đích, không đụng gì khác.
Truyền `--setup --magento 2.4.7-p3` để chạy `bin/download` rồi `bin/setup` sau khi cài, hoặc tự chạy:

```bash
cd ../shop
bin/download community 2.4.7-p3
bin/setup
bin/start
```

Mở `https://shop.test` sau khi thêm host entry (xem `bin/setup-domain` và `bin/setup-ssl`).

## Nhận một Docker root đang chạy

`adopt` đưa Docker root đang chạy về dạng do gói quản lý mà không đụng container hay dữ liệu.
Mọi khác biệt được coi là xung đột, không ghi gì trừ khi kế hoạch sạch hoặc có `--force`.

```bash
./install.sh adopt ../existing-site --dry-run   # chỉ in kế hoạch
./install.sh adopt ../existing-site             # ghi khi không có xung đột
./install.sh adopt ../existing-site --force     # sao lưu xung đột vào .kit/backup/<thời điểm>/
```

## Cập nhật dự án đã cài

Mỗi Docker root ghi manifest đã cài trong `.kit/`. Cập nhật là ba chiều: file cục bộ, checksum đã cài và checksum mới.

```bash
cd shop
bin/self-update --dry-run      # in kế hoạch
bin/self-update                # áp dụng khi sạch
bin/self-update --force        # sao lưu xung đột rồi ghi đè
bin/self-update --version v1.2.0
```

Có xung đột thì dừng trước khi ghi. File thuộc dự án (profile, file env, `project/`) không bao giờ bị ghi đè.

## Profile dự án

`project/profile.env` là nơi duy nhất chứa cấu hình dự án. Bí mật nằm trong `env/*.env`, không nằm trong profile.

| Khóa | Mặc định | Ý nghĩa |
|---|---|---|
| `KIT_PROJECT_NAME` | tên thư mục | Tên project Compose, cũng là tiền tố container và volume |
| `KIT_DOMAIN` | bắt buộc | Host name công khai, dùng cho `bin/setup`, `bin/setup-domain`, `bin/setup-ssl` |
| `KIT_GIT_REMOTE` | bắt buộc | Remote cho `bin/wt` và kit agent |
| `KIT_GIT_BASE_BRANCH` | bắt buộc | Nhánh gốc để tạo worktree, không bao giờ push |
| `KIT_GIT_TARGET_BRANCH` | bắt buộc | Nhánh đích của merge request, không bao giờ push |
| `KIT_PHP_VERSION` | `8.3` | Tag image PHP, một trong `8.2`, `8.3`, `8.4` |
| `KIT_PHP_VARIANT` | rỗng | Biến thể Xdebug lúc chạy, do `bin/xdebug` quản lý |
| `KIT_DB_ENGINE` | `mariadb` | `mariadb` hoặc `mysql`, chọn overlay Compose |
| `KIT_DB_VERSION` | `11.4` / `8.4` | Phiên bản image database theo engine đã chọn |
| `KIT_REDIS_IMAGE` | `valkey/valkey:8.1-alpine` | Image tương thích Redis |
| `KIT_HTTP_PORT` / `KIT_HTTPS_PORT` | `80` / `443` | Cổng web mở ra ngoài |
| `KIT_DB_PORT` / `KIT_REDIS_PORT` | `3306` / `6379` | Cổng dịch vụ mở ra ngoài |
| `KIT_OPENSEARCH_PORT` / `KIT_OPENSEARCH_HEAP` | `9200` / `1g` | Cổng search và heap JVM |
| `KIT_RABBITMQ_PORT` / `KIT_RABBITMQ_MANAGEMENT_PORT` | `5672` / `15672` | Cổng queue |
| `KIT_STATIC_LOCALES` | `en_US` | Locale cho `bin/deploy` |
| `KIT_COMPOSE_PROFILES` | rỗng | Profile Compose cần bật, ví dụ `cloudflared` |
| `KIT_MODEL_<HARNESS>_<TIER>` | bảng của gói | Ghi đè một ô model cho kit agent |

## Worktree

Mỗi Docker root phục vụ đúng một checkout tại một thời điểm. `bin/wt` tạo worktree trong `.worktrees/`,
chuyển stack duy nhất giữa chúng, và giữ một database, một `vendor/` và một `pub/media/`.

```bash
bin/wt create feat/checkout-rework   # từ <remote>/<nhánh gốc>
bin/wt use feat-checkout-rework      # stack chuyển sang worktree đó
bin/wt status                        # đang phục vụ checkout nào, kèm trạng thái container
bin/wt list
bin/wt prepare                       # chép file lõi mà checkout mới còn thiếu
bin/wt adopt ../path/to/wrong-place  # dời worktree tạo sai chỗ vào .worktrees/
bin/wt prune --dry-run               # duyệt worktree đã merge và worktree review, rồi prune
bin/wt doctor                        # so mount phpfpm với .active-src và kiểm cấu hình
```

Khi đổi worktree chỉ `app` và `phpfpm` được tạo lại. Database không bị đụng tới.

## Kit agent

`bin/agent install` ghi phần hướng dẫn dùng chung và adapter vào thư mục hiện tại:

- `AGENTS.md` từ template của gói cộng giá trị profile, thêm tối đa 20 dòng riêng của dự án từ `project/agent/AGENTS.project.md`.
- `CLAUDE.md` nạp `AGENTS.md`.
- `.claude/skills/` và `.agents/skills/`, gồm skill `magento-workflow` cùng reference về gate, quy ước Git và MR, và worktree.
- Role cho Claude Code trong `.claude/agents/` và cho Codex trong `${CODEX_HOME:-~/.codex}/agents/magento-*.toml`.

| Role | Quyền | Hạng model |
|---|---|---|
| `magento-researcher` | chỉ đọc | fast |
| `magento-developer` | ghi | deep |
| `magento-reviewer` | chỉ đọc | default |

Hạng model lấy từ bảng của gói. Ghi đè từng ô trong `project/profile.env`, ví dụ
`KIT_MODEL_CODEX_DEEP=deepseek-v4-pro:max` hoặc `KIT_MODEL_CLAUDE_FAST=inherit`.
Codex chỉ đọc agent trong thư mục home của nó, nên adapter được cài ở đó với tiền tố `magento-`.

## Image PHP

Image nằm ở `ghcr.io/nguyentrunghieu98/magento-php` với tag `<php>-fpm-<n>` và `<php>-fpm-<n>-xdebug`.
Số `<n>` khớp `images/php/IMAGE_VERSION`. File Compose ghim số đó, nên đổi thư mục image thì phải tăng
version và ghim cùng lúc. Dựng cục bộ bằng `docker build` trong `images/php`, hoặc để workflow
`image-php` phát hành tag mới.

## Tunnel Cloudflare

Đặt `KIT_COMPOSE_PROFILES=cloudflared` trong profile, để token tunnel trong `env/cloudflare.env`,
và quản lý ingress trên dashboard Cloudflare. Xem [dist/files/docs/cloudflared.md](dist/files/docs/cloudflared.md).

## Bố cục repo

```text
install.sh              installer: new, adopt
dist/files/             file của gói (chép vào Docker root)
dist/templates/         file dự án tạo một lần (profile, file env, .gitignore)
dist/manifest           checksum và quyền của dist/files
images/php/             Dockerfile, phiên bản PHP ghim, kiểm tra S3
tests/                  bộ test bash, không cần mạng
tools/release           manifest, check và release
.github/workflows/      CI: test, shellcheck, manifest, image PHP
```

## Phát triển

```bash
bash tests/run-all.sh          # toàn bộ suite, không cần mạng
tools/release manifest         # sinh lại dist/manifest
tools/release check            # lỗi khi dist/files và manifest lệch nhau
shellcheck -x install.sh tools/release tests/*.sh
```

Mỗi file test là một suite độc lập. Test của `bin/wt` và installer dựng Docker root sandbox trong
thư mục tạm và dùng `docker` giả có ghi log.

## Phát hành

`tools/release vX.Y.Z` sinh lại manifest, ghi tag phiên bản và in các bước phát hành.
Workflow `test` chạy mỗi lần push, kiểm manifest, test và shellcheck. Workflow `image-php` dựng image
PHP khi `images/php/**` đổi và từ chối ghi đè tag đã tồn tại.

## Giấy phép

MIT. Nguồn upstream, tag và commit được ghi trong [NOTICE](NOTICE).
