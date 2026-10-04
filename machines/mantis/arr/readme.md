# arr

Media download stack in CT 117 (`arr`) on mantis. Torrents only, no VPN.
qBittorrent downloads, Prowlarr finds indexers, Sonarr/Radarr manage series
and movies, Bazarr fetches subtitles, Seerr takes requests, Unpackerr
extracts packed downloads, Recyclarr keeps the TRaSH profiles in sync.

## Container

Created from `local:vztmpl/debian-13-standard_13.1-2_amd64.tar.zst`:

```sh
pct create 117 local:vztmpl/debian-13-standard_13.1-2_amd64.tar.zst \
  --hostname arr --cores 3 --memory 4096 --swap 512 --rootfs local-lvm:200 \
  --unprivileged 1 --features nesting=1,keyctl=1 --onboot 1 \
  --nameserver '1.1.1.1 8.8.8.8' \
  --net0 name=eth0,bridge=vmbr0,firewall=1,gw=192.168.0.1,ip=192.168.0.209/24 \
  --net1 name=eth1,bridge=vmbr1,ip=10.10.10.117/24 \
  --startup order=17 --tags media
```

Appended to `/etc/pve/lxc/117.conf` (container uid/gid 1000 = host
uid/gid 1000, so apps running as 1000 can write the NFS share):

```text
lxc.idmap: u 0 100000 1000
lxc.idmap: g 0 100000 1000
lxc.idmap: u 1000 1000 1
lxc.idmap: g 1000 1000 1
lxc.idmap: u 1001 101001 64535
lxc.idmap: g 1001 101001 64535
```

```sh
pct set 117 --mp0 /mnt/pve/crab-media,mp=/data \
  --hookscript local:snippets/require-crab-media.sh
```

No GPU. Docker installed with `curl -fsSL https://get.docker.com | sh`
(needed `apt-get install curl` first on the Debian template).
`/scratch/incomplete` (unfinished downloads, on the 200G rootfs) is owned
by uid 1000. App configs live in `/root/arr/` (compose.yaml, .env,
`config/`, recyclarr.yml via `config/recyclarr/`).

## Services

All apps run as uid/gid 1000 (`PUID`/`PGID` or `user: 1000:1000`),
`TZ=Asia/Kolkata`, images pinned (verified by pull at build time):

| App | Image | Port |
| --- | --- | --- |
| qBittorrent | lscr.io/linuxserver/qbittorrent:5.2.4 | 8080, 6881 tcp/udp |
| Prowlarr | lscr.io/linuxserver/prowlarr:2.6.5 | 9696 |
| Sonarr | lscr.io/linuxserver/sonarr:4.0.20 | 8989 |
| Radarr | lscr.io/linuxserver/radarr:6.4.4 | 7878 |
| Bazarr | lscr.io/linuxserver/bazarr:1.6.2 | 6767 |
| Seerr | ghcr.io/seerr-team/seerr:v3.5.0 | 5055 |
| FlareSolverr | ghcr.io/flaresolverr/flaresolverr:v3.5.2 | 8191 |
| Unpackerr | ghcr.io/unpackerr/unpackerr:v0.16.1 | - |
| Recyclarr | ghcr.io/recyclarr/recyclarr:8.7.2 (no `v` prefix) | - |

Secrets live in `/root/arr/.env` and `config/recyclarr/secrets.yml`
(mode 600); copies are in `~/.config/homelab/arr.env` on crab. The repo
holds `compose.yaml` (with `${VAR}`), `.env.example` and
`secrets.yml.example`.

## Paths and the hardlink rule

Every container sees the same paths, so imports are hardlinks, not copies:

- `/data/torrents/{movies,tv,anime}`: finished downloads, still seeding.
  qBittorrent categories `radarr`, `sonarr`, `sonarr-anime` point here.
- `/data/library/{movies,tv,anime}`: Sonarr/Radarr root folders, what
  Jellyfin shows.
- `/incomplete` (only in qBittorrent): unfinished pieces, backed by
  `/scratch/incomplete` on the CT rootfs, excluded from backups.
- qBittorrent, Sonarr, Radarr, Bazarr and Unpackerr all mount `/data`
  at `/data`. Same filesystem plus same paths means Sonarr/Radarr
  "copy using hardlinks" links the seeding torrent to the library file.

Unpackerr polls the Sonarr/Radarr queues every 5 minutes and extracts
packed (rar-packed) downloads in place.

## Quality profiles (Recyclarr + TRaSH)

`recyclarr.yml` syncs three instances: Sonarr `tv` (WEB-1080p), Sonarr
`anime` ([Anime] Remux-1080p, capped at 1080p), Radarr `movies`
(HD Bluray + WEB). No quality above 1080p anywhere. The groups mirror the
official config-templates trash_ids, inlined because that repository
ships no `includes.json` for Recyclarr's `template:` directive (includes
resolve to an empty registry).

Two deliberate differences from TRaSH defaults:

- `x265 (HD)` scores **+100** instead of TRaSH's -10000 penalty. The
  library pre-transcodes to HEVC anyway, and both screens play
  HEVC 10-bit directly, so x265 releases save disk and bandwidth.
- Native custom formats `Hindi Audio` (+100) and `English Audio` (+25),
  created in Sonarr/Radarr with an audio-language condition, prefer
  multi-audio releases that include Hindi or English. They are listed
  under `reset_unmatched_scores.except` so the weekly sync preserves
  them (verified: scores survive a sync).

More deliberate settings, all in `recyclarr.yml` so the weekly sync keeps them:

- Upgrades are off in all three profiles (`upgrade.allowed: false`) and
  propers/repacks are `do_not_prefer`. With upgrades on, a slightly better
  release made Radarr download the whole film again, overwrite the file Tdarr
  had shrunk, and queue it for Tdarr again.
- `HDR (avoid)` (native custom format, release-name regex for HDR, HDR10(+),
  HLG, Dolby Vision, UHD and 2160p) scores -10000 in all three profiles, so
  HDR releases fall below the minimum score of 0 and are never grabbed. All
  screens are 1080p SDR, and Tdarr skips HDR files, so an HDR release would
  stay at full size (Gladiator, grabbed before this rule, is 17.9 GB).

Recycle bin: deleted files go to `/data/.recycle/{movies,tv}/` (outside the
libraries Jellyfin and Tdarr scan) and are removed after 7 days.

Recyclarr runs weekly Sunday 04:00 plus once at container start. Its
cron service uses a custom entrypoint because in v8.7.2 bare `sync` only
syncs the radarr instance and `sync sonarr` syncs nothing; only a single
`-i <instance>` filter works. So it runs
`recyclarr sync -i tv && recyclarr sync -i anime && recyclarr sync -i movies`.
Its whole `/config` is one bind mount (`./config/recyclarr`) because v8
migrates cache/state beside `recyclarr.yml` and a file mount breaks that.
API keys come from `secrets.yml` via `!secret` (gitignored; `.env`
`!env_var` lines trip gitleaks `literal-credential`).

## Share limits

Supported setup, no workarounds:

- qBittorrent global share action is **Stop** (`max_ratio_act: 0`),
  ratio limit 1.0 and seeding time 1440 minutes (1 day) enabled. When a
  torrent hits either limit it stops (keeps seeding until then). Behind
  carrier-grade NAT few peers download from us (ratios of 0.01-0.2 after a
  day), and once Tdarr replaces a library file the seeding copy is no longer
  a hardlink and takes its own space, so torrents are kept for one day.
- Sonarr (both download clients) and Radarr (one) have **Remove
  Completed Downloads on**. Completed Download Handling then removes the
  torrent and its files after import; the hardlinked library copy stays.
  This is also what makes the clients pass Sonarr/Radarr validation and
  the test button in the final state.

## Logins

The admin UIs are behind tinyauth single sign-on on NPM (PocketID, Google or
username/password; see [`nginxproxymanager`](../nginxproxymanager)). Their own logins
are off: Sonarr, Radarr and Prowlarr `authenticationMethod: external` (set with
`PUT /api/{v3,v1}/config/host/1`), Bazarr `auth.type: null` in
`config/bazarr/config/config.yaml`, qBittorrent bypasses its login for NPM's address
`10.10.10.107/32` (`bypass_auth_subnet_whitelist`). `117.fw` closes their ports to
the LAN, so the only way in is through NPM. The apps talk to each other with API
keys, which are unaffected; the Homepage widgets still log in to qBittorrent with
its password. Seerr keeps its own login (Jellyfin accounts). The tinyauth password
login uses `ARR_UI_USER`/`ARR_UI_PASSWORD` from `~/.config/homelab/arr.env` on crab.

## Queue and connectivity

qBittorrent runs up to 5 downloads and 10 torrents at once. Torrents
slower than 30 KiB/s for 2 minutes do not count against those limits
(`dont_count_slow_torrents`), so a release with few reachable seeds
cannot block well-seeded ones in the queue.

qBittorrent adds the public tracker list
`https://raw.githubusercontent.com/ngosang/trackerslist/master/trackers_best.txt`
to every new torrent (`add_trackers_enabled`, `add_trackers_url`; it refreshes
the list itself), so more peers are found than through the release's own trackers.

The home connection is behind the ISP's carrier-grade NAT (no public IPv4,
no IPv6), so peers cannot connect in and port forwarding is not possible.
qBittorrent only reaches seeds that accept incoming connections
themselves. Two settings work around that:

- Minimum 10 seeders: Prowlarr's app profile `Standard` has
  `minimumSeeders: 10`, synced to every indexer in Sonarr and Radarr, so
  releases with few seeds (likely none reachable) are never grabbed.
- Decluttarr (`ghcr.io/manimatter/decluttarr:v2.2.0`) checks the queues
  every 10 minutes. A download that is stalled or stuck fetching metadata
  for 3 checks (30 min), or slower than 50 KB/s for 6 checks (1 h), is
  removed from qBittorrent and marked failed in Sonarr/Radarr, which
  blocklists that release and searches for another one. It also removes
  failed downloads, failed imports matching the patterns in its config,
  and unwanted files inside torrents. Its config with API keys and the
  qBittorrent login is `config/decluttarr/config.yaml` (mode 600); the
  repo has [`decluttarr.example.yaml`](decluttarr.example.yaml). It lists
  qBittorrent twice because Sonarr has two download clients
  (`qBittorrent`, `qBittorrent-anime`) and the names must match.

## Indexers (Prowlarr)

Apps Sonarr + Radarr are connected with full sync (both test OK).
FlareSolverr proxy host `http://flaresolverr:8191` with tag
`flaresolverr`. Passing indexers, all tested OK in Prowlarr:

- YTS (movies), EZTV (tv, needs the flaresolverr tag for Cloudflare),
  ThePirateBay (general, flaresolverr tag), Nyaa.si (anime),
  1337x (general, flaresolverr tag).

Not available:

- Anidex: "indexer's server is unavailable".
- TorrentGalaxy: no definition file ships with Prowlarr.

Radarr's Prowlarr app uses movie sync categories
(2000-2060); Sonarr uses the tv defaults. No port forwarding on the home
router; the torrent port 6881 is reachable only as far as the ISP allows.

## Subtitles (Bazarr)

Connected to Sonarr (`sonarr:8989`) and Radarr (`radarr:7878`), monitored
items only. Languages English and Hindi with profile `English + Hindi`
(id 1, default for series and movies). Providers without accounts:
subf2m, subsource, legendasdivx, napisy24, titlovi (podnapisi and YIFY
have no section in Bazarr 1.6). Subtitles are stored next to the media
(`subfolder: current`). Note: Bazarr 1.6 has no REST write for settings
or languages; configuration goes through config.yaml edits (connection,
providers) plus `POST /api/system/settings` form fields
(`languages-enabled`, `languages-profiles`, `settings-general-*`).

## Requests (Seerr)

Seerr v3.5.0 (the successor of Jellyseerr; that repository now redirects
to seerr-team) runs at `requests.home.aniicrite.dev` and
`requests.ghost.aniicrite.dev`. Jellyseerr 2.7.3 could not log in to
Jellyfin 12.1 (400 on `/Users/AuthenticateByName`); Seerr 3.5.0 updated
its Jellyfin authorization headers (seerr-team/seerr#3502) and works.

[`seerr-setup.py`](seerr-setup.py) configures it through the API and is
safe to re-run: Jellyfin sign-in as the Jellyfin admin (which makes that
account the Seerr owner) with Jellyfin at `http://10.10.10.116:8096`,
all three Jellyfin libraries enabled, Radarr (`HD Bluray + WEB`,
`/data/library/movies`) and Sonarr (`WEB-1080p`, `/data/library/tv`;
anime `[Anime] Remux-1080p`, `/data/library/anime`, series type anime),
Telegram notifications, then `POST /settings/initialize`. Radarr and
Sonarr are reached by their compose service names.

Family accounts: anyone with a Jellyfin account can sign in to Seerr with
it (new Jellyfin sign-ins on). New users get request, auto-approve and
issue permissions, limited to 5 movies and 5 seasons per 7 days; change
limits per user in Seerr -> Users. Discover and streaming region is India,
and notification links point to `requests.ghost.aniicrite.dev`.

Search and the media pages use `api.themoviedb.org`; Jellyfin's TMDB
metadata provider uses it too. All traffic, torrents included, goes
through the normal ISP connection (no VPN or proxy).

## Notifications

Telegram (token/chat id from `~/.config/homelab/telegram.env`):
Sonarr and Radarr notify on grab, import, upgrade, health issue and
failure; each sent a test message OK. Seerr notifies on requests,
approvals, availability and failures (configured by `seerr-setup.py`). Sonarr/Radarr also update Jellyfin on import, upgrade,
rename and delete (MediaBrowser connection named `Jellyfin`, `updateLibrary`
on). The triggers must be switched on explicitly: Radarr `onDownload`,
`onUpgrade`, `onRename`, `onMovieDelete`, `onMovieFileDelete*`; Sonarr also
`onImportComplete`, `onSeriesAdd`, `onSeriesDelete`, `onEpisodeFileDelete*`.
With `onDownload` off, imports reach Jellyfin only at the daily 10:00 scan.
In Sonarr v4/Radarr v6 connections live under notifications, there is no
separate `/api/v3/connection`.

## URLs

LAN (`*.home.aniicrite.dev` via NPM) and direct ports on 192.168.0.209:

- qBittorrent 8080, Prowlarr 9696, Sonarr 8989, Radarr 7878, Bazarr 6767,
  Seerr 5055 as `requests` (also `requests.ghost.aniicrite.dev`
  from the internet). NPM reaches them over vmbr1 at 10.10.10.117.

## Rebuild

1. Create the CT, idmap, mount and hookscript as above, then start it.
2. Install Docker (`curl -fsSL https://get.docker.com | sh`), create
   `/root/arr`, copy `compose.yaml`, `.env` (from `.env.example` plus
   real values), `recyclarr.yml` to `config/recyclarr/recyclarr.yml`,
   `secrets.yml` (from `secrets.yml.example`) to
   `config/recyclarr/secrets.yml` (owner 1000:1000, mode 600).
3. `docker compose up -d qbittorrent prowlarr sonarr radarr bazarr seerr flaresolverr`.
4. Read API keys from `config/{sonarr,radarr,prowlarr}/config.xml` and
   `config/bazarr/config/config.yaml` into `.env`; re-push `.env`.
5. qBittorrent: log in with the temp password from `docker logs`,
   set the real password and preferences (`save_path`,
   `temp_path_enabled` + `temp_path: /incomplete`, ratio/time limits,
   categories) via `/api/v2/`.
6. Sonarr/Radarr: root folders, naming, media management (hardlinks,
   20480 MB free), download clients, profiles come from Recyclarr.
7. `docker compose up -d unpackerr recyclarr`; run
   `docker compose run --rm --entrypoint /entrypoint.sh recyclarr sync -i <tv|anime|movies>`
   per instance after creating the Hindi/English custom formats.
8. Prowlarr: tag, FlareSolverr proxy, apps, indexers; fix Radarr sync
   categories to movie cats.
9. Decluttarr: `config/decluttarr/config.yaml` from `decluttarr.example.yaml` (1000:1000, mode 600), `config/decluttarr/logs/`. Bazarr config.yaml + languages form POST; Seerr with
   `seerr-setup.py` (after Jellyfin, Radarr and Sonarr are set up);
   Telegram; NPM hosts (script via CT 107 API); firewall file.

## API calls used

qBittorrent `/api/v2/auth/login`, `/api/v2/app/setPreferences`,
`/api/v2/torrents/createCategory`. Sonarr/Radarr `/api/v3/rootfolder`,
`/config/naming`, `/config/mediamanagement`, `/downloadclient` (+`/test`),
`/qualityprofile`, `/customformat`, `/notification` (+`/test`),
`/tag`. Recyclarr CLI `sync -i`. Prowlarr `/api/v1/tag`,
`/api/v1/indexerProxy` (+schema), `/api/v1/applications` (+`/test`),
`/api/v1/indexer` (+`/test`, Cardigann `definitionFile`,
`appProfileId: 1`, `priority: 25`). Bazarr `/api/system/settings`
(GET, POST form), `/api/system/languages`, `/api/system/health`.
Jellyfin from crab/CT uses header
`Authorization: MediaBrowser Token="<key>"` (v12 ignores `X-Emby-Token`;
login needs `Authorization: MediaBrowser Client=...`).
