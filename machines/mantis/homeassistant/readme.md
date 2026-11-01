# Home Assistant (VM 120)

Home Assistant OS in VM 120, UI at `https://ha.home.aniicrite.dev` (NPM -> `192.168.0.216:8123`).
The theme and both dashboards live here as YAML and are pushed with [`apply.py`](apply.py);
nothing is edited in the Home Assistant UI.

- [`themes/homelab.yaml`](themes/homelab.yaml): near-black theme with hairline cards, one
  green accent for every "on" state, matching the Homepage dashboard. Copied to
  `/config/themes/` over SSH and reloaded with `frontend.reload_themes`.
- [`dashboards/home.yaml`](dashboards/home.yaml): rooms (weather, lamp, fans, air purifier).
- [`dashboards/homelab.yaml`](dashboards/homelab.yaml): servers (Proxmox host, power and cost,
  network, machines, media, container status, updates and backups).
- Dashboards are saved over the websocket API (`lovelace/config/save`, no restart). Each
  file maps to the dashboard `dashboard-<file name>`, which must already exist in
  Settings -> Dashboards. Native cards only (tile, sensor, glance, calendar); no HACS.

```bash
HA_TOKEN=<token> ./apply.py            # theme + dashboards
HA_TOKEN=<token> ./apply.py dashboards  # dashboards only
```

`uv run` pulls `websockets` and `pyyaml`. The theme push needs SSH as root to the VM
(Advanced SSH add-on).

Integrations behind the cards: Proxmox VE (host, storage and container sensors), TP-Link
Tapo P110 on the server plug (power, energy; cost sensors from a `utility_meter` package
at 8 INR/kWh), AdGuard Home, UPnP (WAN speed), Jellyfin, Seerr, Radarr, Sonarr,
qBittorrent, Immich, Xiaomi Home (desk lamp, air purifier), Atomberg (fans, custom
component), WiZ (master room lamp).

WiZ bulbs on firmware 1.34 and newer reject local writes with `-32602 Invalid params`
until the WiZ app setting Settings -> Security -> Allow Local is set to "Allow all
controls". Discovery did not find the bulb; add it by IP.
