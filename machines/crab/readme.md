# crab (desktop)

Ubuntu 24.04 desktop, 12 cores, 40 GB RAM, on 24x7. LAN `192.168.0.10` (static, NetworkManager connection `netplan-enp4s0`, gateway `192.168.0.1`, DNS `192.168.0.208` then `1.1.1.1`), on the tailnet as `crab`. Disks: KIOXIA KBG40ZNV512G NVMe (system), Seagate ST2000VX015 2 TB HDD (`/mnt/data`, storage for mantis), SK hynix BC711 NVMe (not used by the homelab).

| Service | Configuration |
| --- | --- |
| Proxmox Backup Server for mantis | [`pbs/`](pbs), datastore on `/mnt/data/pbs` |
| NFS export `media` for mantis | `/mnt/data/media`, [`storage-setup.sh`](storage-setup.sh) |
| Beszel agent + S.M.A.R.T. | [`beszel-agent-system.sh`](beszel-agent-system.sh) |
| Ollama | `~/ollama`, models `tinyllama`, `mistral` |
| Penpot | `~/penpot` (upstream compose) |

## Data disk

The 2 TB HDD is a single ext4 partition with label `data`, mounted in `/etc/fstab`:

```
LABEL=data /mnt/data ext4 defaults,noatime,nofail,prjquota 0 2
```

| Directory | Owner | Used by |
| --- | --- | --- |
| `pbs/` | `100033:100033` (uid 34 in the rootless PBS container) | Proxmox Backup Server datastore `hdd` |
| `media/` | `1000:1000` (`anil`) | NFS export for mantis: `torrents/`, `library/`, `template/` |

`media/` is capped at 1200 GiB with an ext4 project quota (project id 1000, the `+P` attribute makes new files inherit it). `df` on `media/` reports the cap, so the download apps see the real free space, and automatic downloads cannot fill the disk PBS writes to. PBS stays small through its prune and garbage collection jobs. Beszel alerts at 85% disk use. Check the quota with `sudo repquota -P /mnt/data`.

`nofail` lets the machine boot without the disk. The empty mount point has the immutable attribute (`sudo chattr +i /mnt/data` while unmounted), so nothing can write to the system disk under that path when the HDD is missing; backups then fail with an error instead of filling the NVMe.

[`storage-setup.sh`](storage-setup.sh) sets this up: mount, project quota (needs the disk unmounted once, so stop PBS first), directories, NFS export, firewall rules and the Beszel filesystem name.

## NFS export

`/mnt/data/media` is exported over NFS 4.2 only (versions 3, 4.0 and 4.1 are off), to mantis (`192.168.0.122`) only, with `no_root_squash` so the Proxmox host can manage ISOs and templates. Mantis mounts it as storage `crab-media` and bind-mounts it into CT 116-118 as `/data`. The apps there run as uid 1000, which the containers map to host uid 1000, so files on the HDD belong to `anil`. Downloads and the library are on the same filesystem, so Sonarr and Radarr import with hardlinks instead of copies. See [`machines/mantis/proxmox`](../mantis/proxmox).

Beszel shows the disk as "Data HDD" with usage, I/O and S.M.A.R.T. data.

## Firewall

ufw is on: incoming traffic is dropped unless a rule allows it, outgoing is open.

| Port | From | For |
| --- | --- | --- |
| 22, 3389 (GNOME remote desktop) | `192.168.0.0/23`, `tailscale0` | SSH and remote desktop |
| 5201 (iperf3), 18080 (downly) | `192.168.0.0/23` | network tests, my project |
| 2049, 111 | mantis `192.168.0.122` | NFS |
| 8007 | mantis `.122`, NPM `.203`, Homepage in CT 109 `.210` | PBS |

[`storage-setup.sh`](storage-setup.sh) adds the PBS and NFS rules; the others were added by hand with `ufw allow`.

## Disk health

[`smartd/smartd.conf`](smartd/smartd.conf) (live at `/etc/smartd.conf`, HDD serial filled in) watches all three drives. The HDD runs a short self-test daily at 12:00 and a long one (about 4.5 h) on Saturdays at 13:00, after the PBS verify job. Warnings go to Telegram through [`smartd/smartd-telegram.sh`](smartd/smartd-telegram.sh) (`/usr/local/bin/`), which reads `/etc/smartd-telegram.env` (copy of `~/.config/homelab/telegram.env`, mode 600). Self-test results: `sudo smartctl -l selftest /dev/sda`.

## Beszel agent

Installed in two steps, because the first step needs no root:

1. User install: download `beszel-agent` (checksum-verified) to `~/.local/bin`, write `KEY`, `TOKEN`, `HUB_URL=https://beszel.ghost.aniicrite.dev` and `LISTEN=127.0.0.1:45876` to `~/.config/beszel-agent/env` (mode 600), start it once as a user service so it registers and saves its fingerprint in `~/.config/beszel/`.
2. `sudo bash beszel-agent-system.sh`: installs `smartmontools`, moves the agent to the same system service layout as the other machines with the S.M.A.R.T. drop-in (`SMART_DEVICES=/dev/nvme0n1:nvme,/dev/nvme1n1:nvme,/dev/sda`) and `EXTRA_FILESYSTEMS=sda1__Data HDD` for the data disk, keeps the fingerprint, and removes the user service.

On a fresh machine with sudo available, `machines/mantis/beszel/install-agent.sh` plus [`smart.conf`](../mantis/beszel/smart.conf) does the same in one step.

## Git hooks

`git config --global core.hooksPath .githooks` and gitleaks on `PATH` (`~/.local/bin/gitleaks`), so every clone on this machine scans commits and pushes.
