# Nginx Proxy Manager + frpc (CT 107)

CT 107 (`nginxproxymanager`) is the single entry point for home services. Nginx Proxy Manager routes every `*.ghost.aniicrite.dev` and `*.home.aniicrite.dev` name to a container; frpc keeps an outbound tunnel to frps on beetle so the `ghost` names work from the internet without opening ports at home.

| File | Live path in CT 107 |
| --- | --- |
| [`compose.yaml`](compose.yaml): NPM, tinyauth (login in front of hosts, backed by PocketID), frpc v0.71.0 | `/root/compose.yaml` |
| [`frpc.toml`](frpc.toml): tunnel client | `/root/frpc.toml` |
| [`.env.example`](.env.example): frp token and tinyauth settings | `/root/.env` |
| [`cup/compose.yaml`](cup/compose.yaml): container update checker on :8000 | `/root/.cup/compose.yaml` |

The server side is [`machines/beetle/frps`](../../beetle/frps) and [`machines/beetle/caddy`](../../beetle/caddy).

## Traffic

```
remote: *.ghost.aniicrite.dev -> Cloudflare DNS -> beetle Caddy :443 (wildcard TLS)
          -> frps vhost HTTPS 127.0.0.1:8010 -> tunnel -> frpc -> NPM :443 -> 10.10.10.<CT id>
home:   *.home.aniicrite.dev  -> 192.168.0.203 (NPM) :443 -> 10.10.10.<CT id>
```

frpc proxies (`frpc.toml`): `ghost-wildcard` and `home-wildcard` (https, to NPM :443) and `ssh` (tcp, beetle :6000 -> Proxmox host :22).

NPM holds one Let's Encrypt wildcard certificate for `*.ghost.aniicrite.dev` and `*.home.aniicrite.dev`, issued with the Cloudflare DNS challenge.

## Deploy

```bash
cp .env.example .env    # FRP_AUTH_TOKEN (same value as on beetle) and tinyauth settings
sed -i 's/<BEETLE_PUBLIC_IP>/<ip>/' frpc.toml
docker compose up -d
(cd cup && docker compose up -d)
```

Admin UI: `http://192.168.0.203:81` from the home network. Replace the default login (`admin@example.com` / `changeme`) on first start.

The frp token is read through `{{ .Envs.FRP_AUTH_TOKEN }}` on both sides. Change it on beetle and here together, then restart frps and frpc. Upgrade frps and frpc together; frp v0.71 only guarantees compatibility with frpc v0.61 and newer.

## Proxy host settings

Every host: wildcard certificate, Force SSL, Block common exploits, Websockets on, **HTTP/2 off**. Caddy reuses one upstream connection for all hosts; if any host enables HTTP/2, NPM answers requests for the others on that connection with `421 Misdirected Request`.

| Name | Target |
| --- | --- |
| immich | `10.10.10.100:2283` |
| vw | `10.10.10.101:8004` |
| dns (AdGuard) | `10.10.10.103:80` |
| beszel | `10.10.10.109:8090` |
| pocketid | `10.10.10.115:1411` (`ghost` only) |
| pbs (Proxmox Backup Server on crab) | `https://192.168.0.10:8007` (`home` only) |
| dash (Homepage) | `10.10.10.109:3000` (`home` only, access list `media-admin`) |
| jellyfin | `10.10.10.116:8096` |
| requests (Seerr) | `10.10.10.117:5055` |
| qbit, prowlarr, sonarr, radarr, bazarr | `10.10.10.117:8080`, `:9696`, `:8989`, `:7878`, `:6767` (`home` only) |
| tdarr | `10.10.10.118:8265` (`home` only, access list `media-admin`: HTTP basic auth) |

