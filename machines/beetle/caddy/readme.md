# Caddy on beetle

Caddy is the public TLS entry point on beetle. It gets a wildcard certificate for `*.ghost.aniicrite.dev` with the Cloudflare DNS challenge and forwards those hosts to the frps vhost HTTPS port (8010). The other sites in the `Caddyfile` run directly on beetle.

It runs as a systemd service, not in Docker:

- config: `/etc/caddy/Caddyfile` (copy of `Caddyfile` here)
- Cloudflare credentials in `/etc/caddy/caddy.env`, created from `caddy.env.example`, never committed
- systemd override [`override.conf`](override.conf) in `/etc/systemd/system/caddy.service.d/`:

```ini
[Service]
EnvironmentFile=/etc/caddy/caddy.env
```

```bash
systemctl daemon-reload && systemctl restart caddy
journalctl -u caddy -f
```

## Binary

`/usr/bin/caddy` is the official Caddy v2.11.4 build with `github.com/caddy-dns/cloudflare` v0.2.4 from caddyserver.com, not Ubuntu's `caddy` package (on hold with `apt-mark hold caddy`). v0.2.4 accepts the `cfut_` token format.

Rebuild or upgrade:

```bash
curl -fsSL -o /tmp/caddy "https://caddyserver.com/api/download?os=linux&arch=amd64&version=<version>&p=github.com/caddy-dns/cloudflare@<module-version>"
chmod +x /tmp/caddy && /tmp/caddy build-info | grep caddy-dns/cloudflare
set -a; . /etc/caddy/caddy.env; set +a; /tmp/caddy validate --config /etc/caddy/Caddyfile --adapter caddyfile
install -m755 /tmp/caddy /usr/bin/caddy && systemctl restart caddy
```

`caddy validate` with the real token is the test: the Cloudflare module rejects a token format it does not know while provisioning. Do not rely on `caddy upgrade`: it can pull an older module version (it installed cloudflare v0.2.1 when v0.2.4 was current).
