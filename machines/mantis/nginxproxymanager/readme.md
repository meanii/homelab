# Nginx Proxy Manager + frpc (CT 107)

CT 107 (`nginxproxymanager`) is the single entry point for home services. Nginx Proxy Manager routes every `*.ghost.aniicrite.dev` and `*.home.aniicrite.dev` name to a container; frpc keeps an outbound tunnel to frps on beetle so the `ghost` names work from the internet without opening ports at home.

| File | Live path in CT 107 |
| --- | --- |
| [`compose.yaml`](compose.yaml): NPM, tinyauth v5.2.0 (single sign-on in front of the admin hosts), frpc v0.71.0 | `/root/compose.yaml` |
| [`frpc.toml`](frpc.toml): tunnel client | `/root/frpc.toml` |
| [`.env.example`](.env.example): frp token | `/root/.env` |
| [`tinyauth/tinyauth.env.example`](tinyauth/tinyauth.env.example): tinyauth settings | `/root/tinyauth.env`, users in `/root/tinyauth/users.txt` |
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
cp .env.example .env    # FRP_AUTH_TOKEN (same value as on beetle)
cp tinyauth/tinyauth.env.example tinyauth.env   # fill in, mode 600; users.txt in ./tinyauth/
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
| dns (AdGuard) | `10.10.10.103:80` (`home` only; admin UI only, DNS-over-HTTPS is off) |
| beszel | `10.10.10.109:8090` |
| pocketid | `10.10.10.115:1411` (`ghost` only) |
| pbs (Proxmox Backup Server on crab) | `https://192.168.0.10:8007` (`home` only) |
| dash (Homepage) | `10.10.10.109:3000` (`home` only, tinyauth) |
| jellyfin | `10.10.10.116:8096` |
| requests (Seerr) | `10.10.10.117:5055` |
| qbit, prowlarr, sonarr, radarr, bazarr | `10.10.10.117:8080`, `:9696`, `:8989`, `:7878`, `:6767` (`home` only, tinyauth) |
| tdarr | `10.10.10.118:8265` (`home` only, tinyauth) |
| auth (tinyauth login page) | `http://tinyauth:3000` (compose network, `home` only) |

## Single sign-on (tinyauth)

One login page at `https://auth.home.aniicrite.dev` protects the admin hosts: qbit,
sonarr, radarr, prowlarr, bazarr, tdarr and dash. It offers three ways in:

- PocketID (passkeys), as OIDC client `tinyauth` in PocketID
- Google
- username and password from `/root/tinyauth/users.txt` (bcrypt, `$2a$` prefix)

OAuth logins are accepted only for the emails in `TINYAUTH_OAUTH_WHITELIST`. The
session cookie is set for `.home.aniicrite.dev` and lasts 7 days, so one login
covers every protected host. tinyauth also accepts HTTP basic auth from a local
user, which is what scripts and API clients can use.

[`tinyauth/npm-tinyauth.mjs`](tinyauth/npm-tinyauth.mjs) creates the `auth` host and
writes the forward-auth block into the advanced config of each host passed to it
(`docker exec -w /app root-nginxproxymanager-1 node npm-tinyauth.mjs <domain>...`).
The block defines its own `location /`, which makes NPM drop its generated one, so
it repeats NPM's proxy and websocket headers; nginx asks
`http://tinyauth:3000/api/auth/nginx` on every request and turns a 401 into a
redirect to the login page.

Behind tinyauth the apps' own logins are off (Sonarr, Radarr, Prowlarr:
`authenticationMethod: external`; Bazarr: no authentication; qBittorrent: auth
bypass for `10.10.10.107/32`, NPM's address on vmbr1). Their ports are closed to the
LAN in `117.fw`, so the only way in from the network is through NPM. Containers on
vmbr1 can still reach them directly; vmbr1 is treated as trusted.

Only `*.home` hosts are protected: the cookie domain follows `TINYAUTH_APPURL`, and
the admin hosts have no `ghost` name. From outside, use Tailscale (route to NPM, see
[`machines/mantis`](..)).

