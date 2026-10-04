# Homepage (CT 109)

[Homepage](https://gethomepage.dev) v2.4.0 at `/root/homepage` in CT 109, UI at
`https://dash.home.aniicrite.dev` (NPM -> `10.10.10.109:3000`, access list
`media-admin`: same user and password as the arr apps). One page with every service,
up/down dots and live numbers.

- [`compose.yaml`](compose.yaml), [`.env.example`](.env.example): API keys and
  logins as `HOMEPAGE_VAR_*`; the real `.env` is mode 600 in CT 109 and copied to
  `~/.config/homelab/homepage.env` on crab. `HOMEPAGE_ALLOWED_HOSTS` must contain
  the public host name or the page refuses to load.
- [`config/`](config): `services.yaml` (groups Media, Downloads, Infrastructure,
  Apps), `settings.yaml`, `widgets.yaml`.

Widgets call the services over vmbr1 (`10.10.10.x`), which the Proxmox firewall
does not filter. PBS is reached at `192.168.0.10:8007`, allowed for CT 109's LAN
address `192.168.0.210` in crab's ufw, with the read-only token `homepage@pbs!dash`.
The Jellyfin widget needs `version: 2` for Jellyfin 12. Seerr's API key is in its
`settings.json` (`main.apiKey`).

Rebuild: `pct set 109 --memory 1024`, copy `compose.yaml` and `config/` to
`/root/homepage`, write `.env`, `chown -R 1000:1000 config`, `docker compose up -d`,
then add the NPM host.
