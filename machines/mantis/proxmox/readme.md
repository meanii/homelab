# Proxmox host: backups, notifications, firewall

## vzdump jobs

[`backup-job.sh`](backup-job.sh) creates the jobs. Only the critical containers are included. Resulting `/etc/pve/jobs.cfg`:

```
vzdump: weekly-backup
	schedule sun 02:00
	vmid 101,107,115,116,117,118
	exclude-path /scratch
	storage crab-pbs
	mode snapshot
	compress zstd
	notification-mode notification-system

vzdump: daily-immich
	schedule 01:00
	vmid 100
	storage crab-pbs
	mode snapshot
	compress zstd
	notification-mode notification-system
```

CT 100 (Immich) runs nightly because it holds the photo library (about 200 GB). PBS deduplicates, so each night only new photos are stored; the first backup copies everything.

CT 116-118 (Jellyfin, arr, Tdarr) are backed up for their configuration only. Their media is the bind mount `/data` from crab, which vzdump never includes, and their transcode, download and cache files live under `/scratch`, which the job excludes.

The jobs have no `prune-backups`: retention is set by the prune job on the Proxmox Backup Server in crab ([`machines/crab/pbs`](../../crab/pbs)).

Restore test (October 2026): the latest CT 101 (Vaultwarden) backup restored from `crab-pbs` into a temporary CT 901 in 66 s (`pct restore 901 <volid> --storage local-lvm --unique 1`, network removed, `onboot 0`). `pragma integrity_check` on the restored `db.sqlite3` returned `ok` and its user and vault item counts matched the live database. CT 901 was destroyed afterwards. Repeat this after major changes to the backup setup.

## Storage on crab

[`crab-storage.sh`](crab-storage.sh) adds two storages that live on crab's 2 TB HDD, and prepares the host for the media containers:

| Storage | Type | Content |
| --- | --- | --- |
| `crab-pbs` | Proxmox Backup Server, datastore `hdd`, API token `mantis@pbs!pve` | vzdump backups |
| `crab-media` | NFS 4.2 `192.168.0.10:/mnt/data/media`, hard mount at `/mnt/pve/crab-media`, capped at 1.2 TB on crab | ISO images, CT templates, media (`torrents/`, `library/`) |

CT 116-118 (Jellyfin, arr, Tdarr) bind-mount `/mnt/pve/crab-media` as `/data` (`mp0`; bind mounts are never part of a vzdump backup). Their apps run as uid/gid 1000; `lxc.idmap` maps that one id to host uid/gid 1000 (allowed by `root:1000:1` in `/etc/subuid` and `/etc/subgid`), which is `anil` on crab.

[`require-crab-media.sh`](require-crab-media.sh) is the hookscript of those containers (`pct set <id> --hookscript local:snippets/require-crab-media.sh`). Its pre-start step waits up to 60 s for the NFS share and otherwise refuses to start the container, so no app starts against an empty `/data` and marks the library as missing.

## Telegram notifications

[`telegram-notifications.sh`](telegram-notifications.sh) creates a webhook target `telegram` and a matcher `telegram-errors` (`match-severity error`). Failed backups and other errors are posted to Telegram. The bot token and chat id are stored as target secrets, not in `/etc/pve/notifications.cfg`.

```bash
TELEGRAM_BOT_TOKEN=... TELEGRAM_CHAT_ID=... ./telegram-notifications.sh
pvesh create /cluster/notifications/targets/telegram/test
```

## Firewall

Rule files are in [`firewall/`](firewall): `cluster.fw` and `<id>.fw` go to `/etc/pve/firewall/`, `host.fw` to `/etc/pve/nodes/home/host.fw`.

- `policy_in: DROP`, `policy_out: ACCEPT`.
- IP set `home` = `192.168.0.0/23` (the router serves both 192.168.0.x and 192.168.1.x), `tailnet` = `100.64.0.0/10`.
- Host: SSH and the web UI from `home` and `tailnet`, Tailscale UDP 41641, ping.
- Containers: group `base` (SSH from `home`, ping) plus the service ports each one needs from the LAN. NPM 80/443 and AdGuard DNS 53 accept any source.
- Only `net0` (`vmbr0`) has `firewall=1`. `vmbr1` is not filtered, so NPM -> backend traffic is unaffected.

Apply a change:

```bash
scp firewall/<id>.fw mantis:/etc/pve/firewall/<id>.fw
ssh mantis 'pve-firewall compile >/dev/null && pve-firewall restart && pve-firewall status'
```

When editing host rules remotely, arm an automatic undo first:

```bash
systemd-run --unit=fw-deadman --on-active=4m /bin/sh -c 'sed -i "s/^enable: 1$/enable: 0/" /etc/pve/firewall/cluster.fw; pve-firewall restart'
# test SSH and the web UI, then:
systemctl stop fw-deadman.timer
```

## SSH

[`sshd.conf`](sshd.conf): key login only. Check with `sshd -t` before `systemctl reload ssh`.

## S.M.A.R.T.

The Beszel agent reads disk health through the systemd drop-in [`../beszel/smart.conf`](../beszel/smart.conf) (Micron 2210 NVMe as `/dev/nvme0n1`, SATA SSD as `/dev/sda`).
