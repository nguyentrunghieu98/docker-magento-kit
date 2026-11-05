# Cloudflare tunnel (profile `cloudflared`)

Tunnel là tùy chọn. Gói không sinh cấu hình ingress, ingress do dashboard Cloudflare quản lý.

## Bật tunnel

1. Tạo tunnel trên dashboard Cloudflare (Zero Trust, Networks, Tunnels) rồi chép token.
2. Dán token vào `env/cloudflare.env`:

   ```
   TUNNEL_TOKEN=<token>
   ```

   File này được `.gitignore` mẫu bỏ qua, không commit token.
3. Thêm vào `project/profile.env`:

   ```
   KIT_COMPOSE_PROFILES=cloudflared
   ```

4. Chạy `bin/start` (hoặc `bin/restart`). Không bật profile thì không có service `tunnel`.

## Ingress trên dashboard

Thêm một public hostname cho tunnel với:

| Trường | Giá trị |
|---|---|
| Hostname | domain của dự án, ví dụ `shop.example.com` |
| Service type | `HTTPS` |
| URL | `https://app:8443` |
| Additional application settings, TLS | bật `No TLS Verify` (`noTLSVerify`) |

- Đích là tên service `app`, cổng 8443 bên trong mạng Compose. Đừng dùng tên container và đừng dùng cổng host `KIT_HTTPS_PORT`.
- `noTLSVerify` cần vì nginx trong `app` dùng chứng chỉ tự ký.
- Service `tunnel` không có `container_name`, image ghim tag cụ thể và chạy `--protocol http2 --retries 2 --no-autoupdate`, để chạy ổn định trên mọi mạng.
- Đổi tag image hoặc lệnh thì dùng `compose.override.yaml`.
