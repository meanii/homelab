# Proxmox Backup Server (crab)

Proxmox Backup Server 4.2 in Docker, using the unofficial image [`ayufan/proxmox-backup-server`](https://github.com/ayufan/pve-backup-server-dockerfiles) (Proxmox does not publish one). Mantis sends its vzdump jobs here (storage `crab-pbs`, see [`machines/mantis/proxmox`](../../mantis/proxmox)), including the Immich photo library. This is the only backup of mantis.

UI: `https://pbs.home.aniicrite.dev` and `https://pbs.ghost.aniicrite.dev` (NPM in CT 107 -> `https://192.168.0.10:8007`), or `https://192.168.0.10:8007` directly; user `admin@pbs`. The login is the PBS realm, not PAM; the container has no shell login.

| Path | What |
| --- | --- |
| `/mnt/data/pbs` -> `/datastore/hdd` | datastore `hdd` on the 2 TB HDD |
| `~/pbs/{etc,lib,logs}` | PBS configuration, state and task logs on the system NVMe |

Docker on crab runs rootless, so the container's `backup` user (uid 34) is uid 100033 on the host. The datastore directory must be owned by `100033:100033`.

## Schedules

| Job | Schedule | Setting |
| --- | --- | --- |
| prune `prune-hdd` | daily 06:00 | keep 7 daily, 4 weekly, 6 monthly |
| garbage collection | Sun 10:00 | frees chunks no snapshot uses |
| verify `verify-hdd` | Sat 10:00 | new snapshots, and old ones again after 30 days |

The vzdump jobs on mantis (`daily-immich` for CT 100, `weekly-backup` for CT 101, 107, 115) have no prune setting of their own; the prune job above decides what is kept.

## Access

Mantis uses the API token `mantis@pbs!pve` with role `DatastoreBackup` on `/datastore/hdd` only: it can write and restore its own backups but not delete or prune them. The user `mantis@pbs` has the same ACL because a token never gets more rights than its user.

## Setup

1. Disk and directories: [`../storage-setup.sh`](../storage-setup.sh).
2. `mkdir -p ~/pbs/{etc,lib,logs} && docker compose up -d`
3. `PBS_INITIAL_PASSWORD=<VALUE> PBS_ADMIN_PASSWORD=<VALUE> bash setup.sh`, where `PBS_INITIAL_PASSWORD` is the default password from the image's README (user `admin`). It replaces that login, creates the datastore, jobs and token, and prints the token secret and the certificate fingerprint. Keep both in `~/.config/homelab/pbs.env` (mode 600).
4. On mantis: [`crab-storage.sh`](../../mantis/proxmox/crab-storage.sh) and [`backup-job.sh`](../../mantis/proxmox/backup-job.sh).
5. Telegram alerts: `set -a; . ~/.config/homelab/telegram.env; set +a; bash telegram-notifications.sh`. It adds a webhook target `telegram` and a matcher `telegram-errors` for error-severity events, and switches the datastore to the notification system. Test with `docker exec pbs proxmox-backup-manager notification target test telegram`.

## Restore

In the Proxmox UI: storage `crab-pbs` -> Backups -> select a snapshot -> Restore. Single files: "File Restore" on the same snapshot.
