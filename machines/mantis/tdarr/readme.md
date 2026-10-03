# Tdarr (CT 118)

[Tdarr](https://tdarr.io) pre-transcodes the Jellyfin library to HEVC 10-bit with
Intel QuickSync, in place, so direct play stays cheap. The Mantis HEVC QSV flows skip
files that are already efficient, keep English, Hindi and native audio and subtitles,
verify each output, then ask the matching *arr app to rescan and refresh Jellyfin.
on `local-lvm`, LAN `192.168.0.211`, internal `10.10.10.118`, startup order 18, tag
`media`). App home is `/root/tdarr` (`compose.yaml`, `server/`, `configs/`, `logs/`).
Transcode cache is `/scratch/tdarr-cache` (binds to `/temp` in the container, on the
SSD rootfs, excluded from backups). Media is visible at `/data` (bind mount of the
`crab-media` NFS share, never backed up). UI: `https://tdarr.home.aniicrite.dev`
(NPM -> `10.10.10.118:8265`). Tdarr's own login is off; the NPM host uses the access
list `media-admin` (HTTP basic auth, same user and password as the arr apps, in
`ARR_UI_USER`/`ARR_UI_PASSWORD` of `~/.config/homelab/arr.env` on crab), and
`118.fw` no longer opens 8265 to the LAN, so the UI is only reachable through NPM.
Port 8266 (server, for nodes) stays open to `+home`.

Image: `ghcr.io/haveagitgat/tdarr:2.93.01` (pinned). Server on 8266, web UI on 8265,
internal node `mantis-qsv` with `/dev/dri` passed through. The render node is passed
with `mode=0666` (`dev1: /dev/dri/renderD128,gid=104,mode=0666`): the image starts as
root and drops to its app user, which loses the compose `group_add` gids, so the
worker would otherwise get `EACCES` on the 660 render node and QSV initialisation
would fail. Everything runs as uid/gid 1000.

## Libraries

| Library | Folder | Flow |
| --- | --- | --- |
| Movies | `/data/library/movies` | Mantis HEVC QSV (radarr) |
| TV | `/data/library/tv` | Mantis HEVC QSV (sonarr) |
| Anime | `/data/library/anime` | Mantis HEVC QSV (sonarr) |

Each library uses cache `/temp`, empty output folder (replace in place), folder watch
on, hourly find-new scan (`scheduledScanFindNew`), and transcode plus (quick) health
check processing on. The container filter stays at the default media extensions.

## Flow

Two flows, identical except for the notify step: [`flow-radarr.json`](flow-radarr.json)
notifies Radarr, [`flow-sonarr.json`](flow-sonarr.json) notifies Sonarr. API keys and
the Jellyfin URL in the committed files are placeholders (`<...>`); the live flows in
Tdarr hold the real values. The graph (25 nodes):

1. Skip without changes when the video is HDR or Dolby Vision, above 1080p, or
   already HEVC/AV1 at or below 6 Mbps (HEVC above 6 Mbps is re-encoded; the bitrate
   check is a custom function that falls back from the mediainfo video track to the
   overall bitrate, ffprobe, then size over duration, because per-track bitrates are
   often missing). Each skip writes a reason to the job log and ends at a no-op
   replace.
2. Map audio and subtitles (custom function): keep `eng`, `hin` and the first audio
   track's language, drop other audio; keep text subtitles in those languages; drop
   PGS/VobSub only when a text subtitle in the same language exists; add an AAC
   stereo track (160k) from the best kept track when none exists. Streams whose
   language cannot be determined are kept, and the choice is logged.
3. Encode: QSV hardware decode, then `hevc_qsv` 10-bit (`main10` profile,
   `scale_qsv=format=p010le`), preset `slow`, `-global_quality` 23 for 1080p and 21
   for 720p and below, original frame rate, container `mkv`.
4. Verify: continue only when the output is smaller than the input and its duration
   is within 2 s; otherwise keep the original and log why.
5. Replace the original in place, ask Radarr (movies) or Sonarr (tv, anime) to
   refresh the item, then refresh the Jellyfin library.

Verified on generated samples in a temporary library (since removed): an H.264
1080p clip with jpn/eng/fra audio and an eng subtitle became HEVC Main 10
(`yuv420p10le`), kept jpn and eng, dropped fra, gained a tagged AAC stereo track,
kept the subtitle, and shrank 37.7 MB to 19.8 MB; a low-bitrate HEVC clip was left
byte-identical. `intel_gpu_top` on the host showed sustained ~25% Video engine busy
while the encode ran.

## Schedule and workers

Node `mantis-qsv`: 1 GPU transcode worker, 0 CPU transcode workers, 1 CPU
health-check worker (all day). Transcoding runs 03:00-09:00 IST daily; the hours use
the container clock (Asia/Kolkata). The window avoids the PBS backups (01:00 daily
and Sunday 02:00, host time) and evening watching. The runtime node id changes on
every container restart, but the worker limits and schedule carry over to the new id
(they are matched by node name), verified across a restart.

## Export and import

The committed `flow-*.json` files are exports of the live flows (flow tab -> flow
menu -> export), with secrets replaced by placeholders. To import: flow tab -> new
flow -> import/paste, or `POST /api/v2/cruddb` with
`{"data": {"collection": "FlowsJSONDB", "mode": "insert", "obj": <flow>}}`, then set
each library's `flowId` to the stored `_id` and fill in the real API keys and
Jellyfin URL in the notify nodes.

## Rebuild

```bash
pct create 118 local:vztmpl/debian-13-standard_13.1-2_amd64.tar.zst \
  --hostname tdarr --cores 4 --memory 4096 --swap 512 --rootfs local-lvm:120 \
  --net0 name=eth0,bridge=vmbr0,firewall=1,gw=192.168.0.1,ip=192.168.0.211/24 \
  --net1 name=eth1,bridge=vmbr1,ip=10.10.10.118/24 \
  --nameserver "1.1.1.1 8.8.8.8" --unprivileged 1 \
  --features nesting=1,keyctl=1 --onboot 1 --startup order=18 --tags media
cat >> /etc/pve/lxc/118.conf <<EOF
lxc.idmap: u 0 100000 1000
lxc.idmap: g 0 100000 1000
lxc.idmap: u 1000 1000 1
lxc.idmap: g 1000 1000 1
lxc.idmap: u 1001 101001 64535
lxc.idmap: g 1001 101001 64535
dev0: /dev/dri/card1,gid=44
dev1: /dev/dri/renderD128,gid=104,mode=0666
mp0: /mnt/pve/crab-media,mp=/data
EOF
pct set 118 --hookscript local:snippets/require-crab-media.sh
cp machines/mantis/proxmox/firewall/118.fw /etc/pve/firewall/118.fw
pct start 118
# in the CT as root: curl -fsSL https://get.docker.com | sh
# copy compose.yaml to /root/tdarr, then docker compose up -d
```

Then recreate the libraries and flows over the Tdarr API (see above), set the node
worker limits and schedule, and create the NPM host `tdarr.home.aniicrite.dev` ->
`http://10.10.10.118:8265`.
