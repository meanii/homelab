# mantis (Proxmox at home)

Proxmox VE 9.2, node name `home`, Intel i5-8500T (UHD 630 iGPU), 24 GB RAM. Reached as `ssh mantis` over Tailscale or `root@192.168.0.122` on the LAN.

## Storage

| Name | Type | Size | Holds |
| --- | --- | --- | --- |
| `local` | directory on NVMe | 94 GB | ISOs, templates (backups go to `crab-pbs`) |
| `local-lvm` | LVM-thin on NVMe | 349 GB | most container disks |
| `slowbird` | LVM-thin on SATA SSD | 467 GB | Immich and other large containers |

## Network

`/etc/network/interfaces`:

```
auto vmbr0
iface vmbr0 inet static
    address 192.168.0.122/24
    gateway 192.168.0.1
    bridge-ports eno1

auto vmbr1
iface vmbr1 inet static
    address 10.10.10.1/24
    bridge-ports none
    post-up echo 1 > /proc/sys/net/ipv4/ip_forward
    post-up iptables -t nat -A POSTROUTING -s 10.10.10.0/24 -o vmbr0 -j MASQUERADE
    post-down iptables -t nat -D POSTROUTING -s 10.10.10.0/24 -o vmbr0 -j MASQUERADE
```

- `vmbr0`: home LAN. Every container gets a static LAN address with `firewall=1`.
- `vmbr1`: internal bridge with no physical port, NAT to the LAN. A container's internal address is `10.10.10.<CT id>`; NPM forwards to these.
- Tailscale runs on the host. It advertises the route `192.168.0.203/32` (NPM) with SNAT, so a tailnet device reaches every `*.home.aniicrite.dev` name from anywhere: those names resolve to `192.168.0.203` in public DNS. The route must be approved once in the Tailscale admin console (Machines -> `home` -> Edit route settings). Reproduce with `tailscale set --advertise-routes=192.168.0.203/32`.

## Containers

| CT | Name | Stack | Backed up |
| --- | --- | --- | --- |
| 100 | immich | [`immich/`](immich) at `/root` | yes, nightly, including the photo library |
| 101 | vaultwarden | [`vaultwarden/`](vaultwarden) at `/root` | yes |
| 102, 104, 106 | hermes agents | Hermes AI agents, installed per their upstream docs; not in this repo | no |
| 103 | adguard | AdGuard Home binary, `AdGuardHome.service`, config `/opt/AdGuardHome/AdGuardHome.yaml` (not copied: holds the admin password hash). DNS on 53, UI on 80, upstreams Quad9 and Cloudflare DoH | no |
| 107 | nginxproxymanager | [`nginxproxymanager/`](nginxproxymanager) at `/root` | yes |
| 109 | beszel | [`beszel/`](beszel) at `/root/beszel` | no |
| 112 | downly | my own project, deployed from its repository | no |
| 115 | pocketid | [`pocketid/`](pocketid) at `/root` | yes |
| 116 | jellyfin | [`jellyfin/`](jellyfin) at `/root/jellyfin`, Intel QuickSync, media from crab at `/data` | yes, config only |
| 117 | arr | [`arr/`](arr) at `/root/arr`: qBittorrent, Prowlarr, Sonarr, Radarr, Bazarr, Seerr, Recyclarr, Unpackerr, FlareSolverr | yes, config only |
| 118 | tdarr | [`tdarr/`](tdarr) at `/root/tdarr`, converts the library to HEVC with QuickSync, 03:00-09:00 | yes, config only |

CT 100, 101 and 107 also run [cup](nginxproxymanager/cup) (container update checker) from `/root/.cup/compose.yaml`.

Intel QuickSync for Immich: the iGPU is passed into CT 100 in `/etc/pve/lxc/100.conf`:

```
dev0: /dev/dri/card1,gid=44
dev1: /dev/dri/renderD128,gid=104
```

## Host configuration

See [`proxmox/`](proxmox) for the backup job, Telegram notifications, firewall rules and SSH settings. The Beszel agent runs on the host with S.M.A.R.T. access, see [`beszel/`](beszel).

Other host settings:

- `/etc/hosts`: `192.168.0.122 home.aniicrite.dev home`
- Postfix `myhostname = home.aniicrite.dev`
- OpenID realm for the web UI: `pveum realm add proxmox --type openid --issuer-url https://pocketid.ghost.aniicrite.dev --client-id <id> --client-key <secret> --username-claim email --autocreate 1`

## Adding a service container

The command used for CT 109:

```bash
pct create 109 local:vztmpl/debian-13-standard_13.1-2_amd64.tar.zst \
  --hostname beszel --cores 1 --memory 512 --swap 256 --rootfs local-lvm:4 \
  --unprivileged 1 --features nesting=1,keyctl=1 --onboot 1 --startup order=9 --tags monitoring \
  --nameserver "1.1.1.1 8.8.8.8" \
  --net0 name=eth0,bridge=vmbr0,firewall=1,gw=192.168.0.1,ip=192.168.0.210/24 \
  --net1 name=eth1,bridge=vmbr1,ip=10.10.10.109/24 \
  --ssh-public-keys /root/.ssh/authorized_keys
pct start 109
pct exec 109 -- sh -c 'apt-get update && apt-get install -y curl ca-certificates && curl -fsSL https://get.docker.com | sh'
```

Then:

1. Add `proxmox/firewall/<id>.fw` with the ports the service needs from the LAN and apply it.
2. In NPM add a proxy host `<name>.ghost.aniicrite.dev` + `<name>.home.aniicrite.dev` -> `http://10.10.10.<id>:<port>` with the wildcard certificate, Force SSL, Block exploits and Websockets on, **HTTP/2 off**. Caddy on beetle reuses one upstream connection for all hosts; a single host with HTTP/2 makes NPM answer the others with `421 Misdirected Request`. No DNS change is needed.
3. If it is critical, add the CT id to a backup job (`proxmox/backup-job.sh`).

Read files inside a container from another machine: `ssh mantis pct exec <id> -- cat <path>`.
