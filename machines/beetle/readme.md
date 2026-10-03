# beetle (Hetzner VPS)

Ubuntu 24.04. The public entry point for `aniicrite.dev`: Caddy terminates TLS for every public site and for the home services, which reach it through the frp tunnel. SSH: `ssh beetle` (port 2269, key only).

## Host services

| Service | Configuration |
| --- | --- |
| Caddy v2.11.4 + `caddy-dns/cloudflare` v0.2.4 | [`caddy/`](caddy); custom build, apt package `caddy` on hold |
| Docker | stacks below |
| ufw | [`host/ufw.sh`](host/ufw.sh) |
| sshd | [`host/sshd.conf`](host/sshd.conf) |
| journald | capped at 300 MB, [`host/journald-size.conf`](host/journald-size.conf) |
| fail2ban | Debian default `sshd` jail |
| Tailscale, Beszel agent | [`machines/mantis/beszel`](../mantis/beszel) for the agent |

## Docker stacks

| Stack | Live path | Repo | Host port | Domain |
| --- | --- | --- | --- | --- |
| frps v0.71.0 | `/root/services/frp` | [`frps/`](frps) | 7000, 6000; 127.0.0.1: 7500, 8009, 8010 | `frp.aniicrite.dev` (dashboard) |
| NetBird server + dashboard | `/root` | [`netbird/`](netbird) | 127.0.0.1: 8080, 8081; 3478/udp | `netbird.aniicrite.dev` |
| NetBird reverse proxy | `/root/services/netbird-proxy` | [`netbird/proxy-compose.yaml`](netbird/proxy-compose.yaml) | 9080, 9443 | `proxy.aniicrite.dev` |
| aliasvault | `/opt/aliasvault` | [`aliasvault/`](aliasvault) | 127.0.0.1:8093 | `vault.aniicrite.dev` |
| aniicrite.dev site | `/root/personal/aniicrite.dev` | own repo | 8091 | `aniicrite.dev` |
| umbra (note sync server) | `/opt/umbra/server` | own repo | 8092 | `umbra.aniicrite.dev` |
| backpulse (+ Postgres) | `/opt/backpulse` | own repo | 8095 | `backpulse.aniicrite.dev` |
| rsscat, dmrctelebot (Telegram bots) | `/root/personal/rss.cat`, `/root/services/dmrc/dmrctelebot` | own repos | none | none |

"Own repo" stacks are my application projects, deployed from their own repositories.

Services that only Caddy talks to are published on `127.0.0.1`. Docker-published ports bypass ufw, so binding to localhost is what keeps them private.

## Rebuild order

1. Ubuntu 24.04, SSH on port 2269 with key login ([`host/sshd.conf`](host/sshd.conf)), Docker, Tailscale, fail2ban.
2. `host/ufw.sh`, then `host/journald-size.conf` into `/etc/systemd/journald.conf.d/`.
3. Caddy: install the custom binary and config as described in [`caddy/readme.md`](caddy/readme.md).
4. frps from [`frps/`](frps) (copy `.env.example` to `.env`, set the token and dashboard password), then point mantis' frpc at this server.
5. The other stacks; in each folder copy `.env.example` to `.env` and fill it in.
6. Beszel agent with `machines/mantis/beszel/install-agent.sh`.

## DNS (Cloudflare, zone `aniicrite.dev`)

| Record | Target |
| --- | --- |
| `aniicrite.dev`, `*.ghost`, `frp`, `netbird`, `proxy`, `umbra`, `vault`, `backpulse` | A -> beetle |
| `*.proxy` | CNAME -> `proxy.aniicrite.dev` |
| `*.home` | A -> `192.168.0.203` (NPM on the home LAN) |

The Cloudflare API token used by Caddy needs `Zone:DNS:Edit` on this zone.
