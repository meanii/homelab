# Beszel (CT 109)

[Beszel](https://github.com/henrygd/beszel) v0.20.0 monitors the four homelab machines and `wl-prod`, the Hetzner VPS that runs webhooklocal.com (monitoring only; it has no folder in this repo). The hub runs in CT 109 (`beszel`, Debian 13, 1 core, 512 MB, 4 GB on `local-lvm`, LAN `192.168.0.210`, internal `10.10.10.109`) at `/root/beszel`. UI: `https://beszel.home.aniicrite.dev` (NPM -> `10.10.10.109:8090`, websockets on).

CT 109 also runs the [Homepage](homepage/) dashboard (1 GB RAM since then) at `https://dash.home.aniicrite.dev`.

## Hub

```bash
cp .env.example .env   # first admin login, only read on the first start
docker compose up -d
```

## Agents

Every agent is a systemd service that dials out to `https://beszel.ghost.aniicrite.dev` over WebSocket, so the hub needs no route to the agents. The agent's own listener is bound to `127.0.0.1:45876`. Settings live in `/etc/beszel-agent.env` (mode 600); the unit file has no secrets.

| System | Installed with | S.M.A.R.T. |
| --- | --- | --- |
| mantis | [`install-agent.sh`](install-agent.sh) + [`smart.conf`](smart.conf) | Micron NVMe, SATA SSD |
| beetle | `install-agent.sh` | no (virtual disk) |
| vultr | `install-agent.sh` | no (virtual disk) |
| crab | user install, then [`machines/crab/beszel-agent-system.sh`](../../crab/beszel-agent-system.sh) | both NVMe and the 2 TB backup HDD |
| wl-prod | `install-agent.sh` | no (virtual disk) |

Adding a machine: in the hub open Settings -> Tokens and enable a universal token (valid 1 hour), then as root on the new host:

```bash
KEY='<hub-public-key>' TOKEN='<universal-token>' ./install-agent.sh
```

The system appears under its hostname; rename it to the machine name. It keeps connecting after the token expires because the agent stores a fingerprint in its data directory (`/var/lib/beszel-agent/fingerprint`). Keep that file when moving an agent, or the hub rejects it as a different machine.

## S.M.A.R.T.

[`smart.conf`](smart.conf) is a drop-in for `/etc/systemd/system/beszel-agent.service.d/`. It gives the unprivileged agent `CAP_SYS_RAWIO` and `CAP_SYS_ADMIN` and the `disk` group. NVMe drives are read through the namespace device (`/dev/nvme0n1`), because the controller node `/dev/nvme0` is root-only. Set `SMART_DEVICES` to the host's disks, then `systemctl daemon-reload && systemctl restart beszel-agent`.

## Alerts

[`alerts.sh`](alerts.sh) sets the Telegram notification target and creates the rules below, using [`api.sh`](api.sh) (calls the hub API as the admin from `.env`; a third argument means "JSON body on stdin"):

```bash
TELEGRAM_BOT_TOKEN=... TELEGRAM_CHAT_ID=... ./alerts.sh
```

| Alert | Threshold | For | Systems |
| --- | --- | --- | --- |
| Status | down | 2 min | all |
| Disk | > 85% | 10 min | all |
| Memory | > 90% | 10 min | all |
| CPU | > 90% | 15 min | all |
| Temperature | > 80 °C | 5 min | mantis, crab |

A disk whose S.M.A.R.T. state turns to failing is reported automatically.
