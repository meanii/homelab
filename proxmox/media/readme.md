# 🎥 Media Server Setup

This project sets up a self-hosted media server stack using Docker Compose with the following services:

- **Jellyfin** – Media streaming server
- **qBittorrent** – Torrent client
- **qBittorrentBot** – Telegram bot to control qBittorrent remotely
- **Radarr** – Movie management and automation
- **Sonarr** – TV show management and automation
- **Prowlarr** – Indexer management
- **Jellyseerr** – Media request and discovery frontend for Jellyfin

---

## 📁 Directory Structure

```bash
project-root/
├── compose.yaml           # Docker Compose file
├── jellyfin/              # Jellyfin config & cache
│   ├── config/
│   └── cache/
├── qbittorrent/           # qBittorrent config
├── radarr/                # Radarr config
├── sonarr/                # Sonarr config
├── prowlarr/              # Prowlarr config
├── jellyseerr/            # Jellyseerr config
├── qbitbot/               # qBittorrentBot config
├── downloads/             # Downloaded torrent files
│   ├── completed/
│   │   ├── movies/        # Completed movie downloads
│   │   └── shows/         # Completed show downloads
│   ├── incomplete/        # Active/in-progress torrents
│   └── torrents/          # .torrent files
└── media/                 # Final organized media location
    ├── movies/            # Sorted movies
    └── shows/             # Sorted TV shows
```

---

## 🚀 Quick Start

### 1. Clone this Repository

```bash
git clone https://github.com/meanii/homelab.git
cd homelab/proxmox/media/
```

### 2. Create Required Directories

Run the following to create all necessary folders:

```bash
mkdir -p \
  jellyfin/{config,cache} \
  qbittorrent/config \
  radarr/config \
  sonarr/config \
  prowlarr/config \
  jellyseerr/config \
  qbitbot \
  downloads/{completed/{movies,shows},incomplete,torrents} \
  media/{movies,shows}
```

### 3. Set Up Environment (Optional)

Edit `.env` if you're using one for credentials, UID/GID, or ports.

---

### 4. Start All Services

```bash
docker compose up -d
```

---

## 🔗 Web Interfaces

| Service            | URL                                                     |
| ------------------ | ------------------------------------------------------- |
| **Jellyfin**       | `http://<your-ip>:8096` _(or your custom domain)_       |
| **qBittorrent**    | `http://<your-ip>:8080` _(user/pass: admin/adminadmin)_ |
| **Radarr**         | `http://<your-ip>:7878`                                 |
| **Sonarr**         | `http://<your-ip>:8989`                                 |
| **Prowlarr**       | `http://<your-ip>:9696`                                 |
| **Jellyseerr**     | `http://<your-ip>:5055`                                 |
| **qBittorrentBot** | Setup via `qbitbot/config.json` and Telegram            |

---

## 🔄 Automation Notes

- **Radarr** and **Sonarr** monitor and manage content in the `media/` directory.
- **Prowlarr** centralizes indexer configuration and integrates with Radarr/Sonarr.
- **qBittorrent** handles torrent downloads, using the `downloads/` directory.
- Radarr/Sonarr auto-import completed files from `downloads/completed/` to `media/`.

---

## ✅ Permissions Tips

Ensure Docker has permission to access all folders:

```bash
sudo chown -R $USER:$USER project-root/
```

Also verify UID/GID in the environment match your host user (e.g. `PUID=1000`, `PGID=1000`).

---

## 📌 Notes

- Jellyfin uses `network_mode: host` for performance and discovery. Ensure port 8096 is open.
- You can expose Jellyfin remotely via HTTPS using a reverse proxy or by setting `JELLYFIN_PublishedServerUrl`.
- Secure qBittorrent with a password and consider enabling VPN or firewall rules.
- Set up your Telegram bot token and chat ID in `qbitbot/config.json`.

---
