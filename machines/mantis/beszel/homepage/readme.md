# Homepage (CT 109)

[Homepage](https://gethomepage.dev) v2.4.0 at `/root/homepage` in CT 109, UI at
`https://dash.home.aniicrite.dev` (NPM -> `10.10.10.109:3000`, behind tinyauth). One
page with every service,
up/down dots and live numbers.

- [`compose.yaml`](compose.yaml), [`.env.example`](.env.example): API keys and
  logins as `HOMEPAGE_VAR_*`; the real `.env` is mode 600 in CT 109 and copied to
  `~/.config/homelab/homepage.env` on crab. `HOMEPAGE_ALLOWED_HOSTS` must contain
  the public host name or the page refuses to load.
- [`config/`](config): `services.yaml` (groups Machines, Media, Calendar, Downloads,
  Infrastructure, Apps), `settings.yaml`, `widgets.yaml`, `proxmox.yaml`, `custom.css`.
- Machines: one Beszel widget per host (`systemId` = the Beszel system name) with
  CPU, memory and disk, five columns (mantis, beetle, crab, vultr, wl-prod).
- Each container's card has a Proxmox ring next to its status dot (green = running);
  click it for that container's CPU and RAM. `proxmox.yaml` holds the API for this; its
  block key must be the node name (`home`), matching `proxmoxNode` in `services.yaml`.
- Theme: `custom.css` makes the page near-black with hairline borders, Geist / Geist
  Mono and a serif date (fonts from Google Fonts). `settings.yaml` uses `color: zinc`.
- Homepage caches the rendered page: after changing `settings.yaml`, run
  `docker compose restart homepage` and then `curl -H 'Host: dash.home.aniicrite.dev'
  http://127.0.0.1:3000/api/revalidate`, or the old layout stays.

Widgets call the services over vmbr1 (`10.10.10.x`), which the Proxmox firewall
does not filter. PBS is reached at `192.168.0.10:8007`, allowed for CT 109's LAN
address `192.168.0.210` in crab's ufw, with the read-only token `homepage@pbs!dash`.
The Jellyfin widget needs `version: 2` for Jellyfin 12.

Widget credentials, all limited to what the widget reads where the service allows it:

| Widget | Credential |
| --- | --- |
| Proxmox, Media storage | API token `homepage@pve!dash`, role `PVEAuditor` on `/` (read-only). "Media storage" reads `nodes/home/storage/crab-media/status`, which reports crab's 1.2 TB media quota. |
| Immich | API key "homepage dashboard" with only the `server.statistics` permission |
| Beszel | superuser `homepage@home.lan`: the widget logs in through `_superusers/auth-with-password`, so a normal or read-only user does not work. Its password sits in CT 109 next to Beszel's own database, so it adds no new exposure. |
| AdGuard | none: AdGuard has no login of its own anymore (it is behind tinyauth) |
| Calendar | uses the Sonarr and Radarr widgets above |

Downly (CT 112) is not on the page: it publishes no web port. Seerr's API key is in its
`settings.json` (`main.apiKey`).

Rebuild: `pct set 109 --memory 1024`, copy `compose.yaml` and `config/` to
`/root/homepage`, write `.env`, `chown -R 1000:1000 config`, `docker compose up -d`,
then add the NPM host.
