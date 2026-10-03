# Jellyfin (CT 116)

[Jellyfin](https://jellyfin.org) 12.1 serves the media library to the LAN and to
phones, laptops and TVs. It runs in CT 116 (`jellyfin`, Debian 13, 4 cores,
4 GB RAM, 40 GB on `local-lvm`, LAN `192.168.0.206`, internal `10.10.10.116`)
at `/root/jellyfin`. UI: `https://jellyfin.home.aniicrite.dev` (LAN) and
`https://jellyfin.ghost.aniicrite.dev` (internet), both through NPM to
`10.10.10.116:8096` with websockets on. Direct LAN access:
`http://192.168.0.206:8096`.

The container runs one service from [`compose.yaml`](compose.yaml):
`jellyfin/jellyfin:12.1` as uid/gid 1000, with `/dev/dri` passed through for
Intel QuickSync, config in `./config`, cache and transcodes under `/scratch`
(excluded from backups), and the NFS media share at `/data`.

Admin credentials and the API key live only on crab in
`~/.config/homelab/jellyfin.env` (mode 600): `JELLYFIN_URL`,
`JELLYFIN_ADMIN_USER`, `JELLYFIN_ADMIN_PASSWORD`, `JELLYFIN_API_KEY`. The arr
and Tdarr stacks read the URL and key from that file.

## Hardware acceleration

The host iGPU is an Intel UHD 630 (Coffee Lake, Gen 9.5). The encoding
settings (`POST /System/Configuration/encoding`, see [`setup.py`](setup.py))
are:

- Hardware acceleration `qsv` on `/dev/dri/renderD128`.
- Hardware decoding for h264, hevc, mpeg2video, vc1, vp8 and vp9, including
  10-bit HEVC and VP9. No AV1: this GPU cannot decode it.
- Hardware encoding on, HEVC encoding allowed, Intel low-power H264/HEVC
  encoders off (they trade quality for power on this generation).
- Tone mapping on with VPP tone mapping, so HDR sources play on SDR screens.
- Throttling and segment deletion on; transcode temp path
  `/scratch/transcodes`.

`vainfo` inside the container (iHD driver 26.2.4) lists `HEVCMain10` with
`VLD` and `EncSlice` entrypoints. A 60 s 1080p24 test clip transcoded with
`-hwaccel qsv -c:v hevc_qsv` runs at about 80 fps, and `intel_gpu_top` on the
host shows the Video engine near 22 percent busy during the transcode and
zero when idle.

## Libraries

| Library | Type | Path | Options |
| --- | --- | --- | --- |
| Movies | movies | `/data/library/movies` | language en, country IN |
| Shows | tvshows | `/data/library/tv` | language en, country IN |
| Anime | tvshows | `/data/library/anime` | language en, country IN |

Real-time monitoring is off (inotify does not work reliably over NFS); the
arr apps trigger refreshes, and a full scan runs daily at 10:00 local time
(`RefreshLibrary`), after Tdarr's 03:00-09:00 window. Trickplay images run at
10:30 and chapter images at 11:00 for the same reason. Quick Connect is enabled for
TV and phone sign-in. No SSO plugin is installed.

## Rebuild

Create the container on mantis:

```bash
pct create 116 local:vztmpl/debian-13-standard_13.1-2_amd64.tar.zst \
  --hostname jellyfin --cores 4 --memory 4096 --swap 512 \
  --rootfs local-lvm:40 --storage local-lvm \
  --unprivileged 1 --features nesting=1,keyctl=1 --onboot 1 \
  --startup order=16 --tags media \
  --nameserver "1.1.1.1 8.8.8.8" \
  --net0 name=eth0,bridge=vmbr0,firewall=1,gw=192.168.0.1,ip=192.168.0.206/24 \
  --net1 name=eth1,bridge=vmbr1,ip=10.10.10.116/24
cat >> /etc/pve/lxc/116.conf <<EOF
lxc.idmap: u 0 100000 1000
lxc.idmap: g 0 100000 1000
lxc.idmap: u 1000 1000 1
lxc.idmap: g 1000 1000 1
lxc.idmap: u 1001 101001 64535
lxc.idmap: g 1001 101001 64535
dev0: /dev/dri/card1,gid=44
dev1: /dev/dri/renderD128,gid=104
mp0: /mnt/pve/crab-media,mp=/data
EOF
pct set 116 --hookscript local:snippets/require-crab-media.sh
cp machines/mantis/proxmox/firewall/116.fw /etc/pve/firewall/116.fw
pct start 116
```

The idmap maps container uid/gid 1000 to host uid/gid 1000, so files created
in `/data` are owned by the same user as on crab. The hookscript refuses to
start the container while the NFS share is unmounted. Port 8096/tcp is open
from home; NPM reaches the server over vmbr1, which is unfiltered.

Install Docker in the container, copy `compose.yaml`, then start Jellyfin:

```bash
pct exec 116 -- sh -c "apt-get update && apt-get install -y curl ca-certificates && curl -fsSL https://get.docker.com | sh"
# copy compose.yaml to /root/jellyfin/compose.yaml
pct exec 116 -- sh -c "cd /root/jellyfin && mkdir -p config /scratch/transcodes /scratch/cache && chown 1000:1000 config /scratch/transcodes /scratch/cache && docker compose up -d"
```

Then run `setup.py` from mantis. On a fresh server it completes the startup
wizard (language en-US, country IN, admin user from the environment) and
prints nothing secret except through the API; on an existing server it only
reapplies libraries, encoding, the scan schedule and a refresh:

```bash
JELLYFIN_ADMIN_PASSWORD='<generated>' JELLYFIN_API_KEY='<key>' python3 setup.py
```

Save the four values to `~/.config/homelab/jellyfin.env` on crab (mode 600).
Create the NPM proxy hosts for `jellyfin.home.aniicrite.dev` and
`jellyfin.ghost.aniicrite.dev` pointing at `10.10.10.116:8096` with
websockets on, HTTP/2 off and certificate id 23.

## API notes for Jellyfin 12

Three v12 behaviours differ from older guides and from the 10.11 API:

- The auth context comes only from the `Authorization: MediaBrowser ...`
  header. `X-Emby-Authorization` and `X-Emby-Token` are ignored (401/400).
  Token calls use `Authorization: MediaBrowser Token="<key>"`.
- The first user is created lazily: `GET /Startup/User` creates and returns
  the default user, then `POST /Startup/User` renames it and sets the
  password. Posting the user first returns 404.
- `POST /Auth/Keys` takes the app name as a query parameter
  (`?app=homelab-setup`) and returns 204; read the key back with
  `GET /Auth/Keys`.
