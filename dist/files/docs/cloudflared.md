# Cloudflare tunnel (profile `cloudflared`)

The tunnel is optional. The package does not generate ingress configuration; ingress is managed by the Cloudflare dashboard.

## Enable the tunnel

1. Create a tunnel in the Cloudflare dashboard (Zero Trust, Networks, Tunnels) and copy the token.
2. Paste the token into `env/cloudflare.env`:

   ```
   TUNNEL_TOKEN=<token>
   ```

   The sample `.gitignore` ignores this file; do not commit the token.
3. Add to `project/profile.env`:

   ```
   KIT_COMPOSE_PROFILES=cloudflared
   ```

4. Run `bin/start` (or `bin/restart`). Without this profile there is no `tunnel` service.

## Ingress in the dashboard

Add a public hostname to the tunnel with:

| Field | Value |
|---|---|
| Hostname | the project domain, for example `shop.example.com` |
| Service type | `HTTPS` |
| URL | `https://app:8443` |
| Additional application settings, TLS | enable `No TLS Verify` (`noTLSVerify`) |

- The target is the service name `app`, port 8443 inside the Compose network. Do not use the container name and do not use the host port `KIT_HTTPS_PORT`.
- `noTLSVerify` is required because nginx in `app` uses a self-signed certificate.
- The `tunnel` service has no `container_name`, its image is pinned to a specific tag and it runs `--protocol http2 --retries 2 --no-autoupdate`, so it stays stable on any network.
- To change the image tag or the command, use `compose.override.yaml`.
