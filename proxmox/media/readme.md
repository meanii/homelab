# 🎥 Media Server Setup

This project sets up a self-hosted media server stack using Docker Compose with the following services:

- **Jellyfin** – Media streaming server
- **qBittorrent** – Torrent client
- **qBittorrentBot** – Telegram bot to control qBittorrent remotely
- **Radarr** – Movie management and automation
- **Sonarr** – TV show management and automation
- **Prowlarr** – Indexer management
- **Jellyseerr** – Media request and discovery frontend for Jellyfin
- **Bazarr** – Subtitle downloader for movies and shows
- **FileFlows Server** – Media processing & automation engine
- **FileFlows Node** – Worker node for FileFlows processing
- **Nginx Proxy Manager + FRP** – Centralized reverse proxy with secure tunneling (public/local)

---

## Directory Structure

```bash
proxmox/
├── compose.yaml              # Docker Compose file
├── jellyfin/                 # Jellyfin config & cache
│   ├── config/
│   └── cache/
├── qbittorrent/              # qBittorrent config
├── radarr/                   # Radarr config
├── sonarr/                   # Sonarr config
├── prowlarr/                 # Prowlarr config
├── jellyseerr/               # Jellyseerr config
├── bazarr/                   # Bazarr config
├── qbitbot/                  # qBittorrentBot config
├── fileflow/                 # FileFlows config and temp data
│   ├── data/
│   ├── log/
│   ├── tmp/
│   └── comon/
├── downloads/                # Downloaded torrent files
│   ├── completed/
│   │   ├── movies/
│   │   └── shows/
│   ├── incomplete/
│   └── torrents/
├── media/                    # Final organized media location
    ├── movies/
    └── shows/
````

---

## Quick Start

### 1. Clone this Repository

```bash
git clone https://github.com/meanii/homelab.git
cd homelab/proxmox/media/
```

### 2. Create Required Directories

```bash
mkdir -p \
  jellyfin/{config,cache} \
  qbittorrent/config \
  radarr/config \
  sonarr/config \
  prowlarr/config \
  jellyseerr/config \
  bazarr/config \
  qbitbot \
  fileflow/{data,log,tmp,comon} \
  downloads/{completed/{movies,shows},incomplete,torrents} \
  media/{movies,shows}
```

### 3. Set Up Environment (Optional)

Edit `.env` if you're using one for credentials, UID/GID, or custom ports.

---

### 4. Start All Services

```bash
docker compose up -d
```

---

## Web Interfaces

| Service            | Local URL                       | Remote (via NPM/FRP)                |
| ------------------ | ------------------------------- | ----------------------------------- |
| **Jellyfin**       | `http://<your-ip>:8096`         | `https://jellyfin.yourdomain.com`   |
| **qBittorrent**    | `http://<your-ip>:8080`         | `https://qbit.yourdomain.com`       |
| **Radarr**         | `http://<your-ip>:7878`         | `https://radarr.yourdomain.com`     |
| **Sonarr**         | `http://<your-ip>:8989`         | `https://sonarr.yourdomain.com`     |
| **Prowlarr**       | `http://<your-ip>:9696`         | `https://prowlarr.yourdomain.com`   |
| **Bazarr**         | `http://<your-ip>:6767`         | `https://bazarr.yourdomain.com`     |
| **Jellyseerr**     | `http://<your-ip>:5055`         | `https://jellyseerr.yourdomain.com` |
| **FileFlows**      | `http://<your-ip>:19200`        | `https://fileflows.yourdomain.com`  |
| **qBittorrentBot** | Setup via `qbitbot/config.json` | N/A (controlled via Telegram bot)   |

---

## 🔐 Reverse Proxy + Secure Tunnel (NPM + FRP)

This stack integrates with [**Nginx Proxy Manager + FRP**](https://github.com/meanii/homelab/tree/main/proxmox/nginxproxymanager) for centralized domain-based access and public tunneling.

> 📁 NPM/FRP Setup:
> See [`proxmox/nginxproxymanager`](https://github.com/meanii/homelab/tree/main/proxmox/nginxproxymanager)

**Features:**

* Automatic SSL (Let's Encrypt)
* Custom subdomains per service
* Public tunnel using FRP
* UI dashboard for proxy rules

To enable:

1. Deploy the Nginx Proxy Manager + FRP stack using the provided repo.
2. Point subdomains in your DNS to the FRP server (or use a wildcard domain).
3. Create proxy hosts in NPM to map to local IPs and service ports.
4. (Optional) Password-protect or IP restrict sensitive services.

---

## Automation Notes

* **Radarr/Sonarr** import completed torrents from `downloads/completed/` to `media/`
* **Bazarr** downloads and syncs subtitles for movies/TV
* **FileFlows** automates renaming, transcoding, metadata fixing
* **Prowlarr** manages indexers and integrates with Radarr/Sonarr

---

## Permissions Tips

Ensure proper ownership:

```bash
sudo chown -R $USER:$USER project-root/
```

Confirm UID/GID match your host user (e.g. `PUID=1000`, `PGID=1000`).

---

## Notes

* Jellyfin uses `network_mode: host` for direct streaming performance.
* qBittorrent uses port 8080; change `WEBUI_PORT` if needed.
* Nginx Proxy Manager simplifies exposing services with TLS and FRP tunnel support.
* Configure Telegram bot token/chat ID for `qBittorrentBot` in `qbitbot/config.json`.

---
