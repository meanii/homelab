
# Cup 🥤

## What is Cup?

[Cup](https://github.com/sergi0g/cup) is a lightweight container image update checker that helps identify when your Docker images have newer versions available. It supports various registries like Docker Hub, GitHub Container Registry (ghcr.io), Quay, and more – all without hitting rate limits.

You can view container image update status through a simple web interface (on port **8000**) or via CLI.

---

## Infrastructure Overview

This setup is designed for a self-hosted homelab managed using **Proxmox**, with individual directory structures and service compositions for modularity. Here's a look at how it's organized:

```bash
proxmox/
├── cup                         # Container update checker (Cup) setup
│   ├── compose.yaml            # Docker Compose file for Cup agent/server
│   ├── cup.json                # JSON config/output (structured state)
│   └── readme.md               # This documentation file
├── glance
│   └── home.yml                # System overview dashboard config
├── homeassistant
│   └── compose.yaml            # Smart home automation system
├── media
│   ├── compose.yaml            # Media stack (Plex/Jellyfin/Sonarr/etc)
│   ├── qbitbot
│   │   └── config.json.template# Torrent automation configuration template
│   └── readme.md
├── nginxproxymanager
│   ├── compose.yaml            # Nginx Proxy Manager instance
│   ├── frpc.toml               # FRP (client) config
│   ├── frps
│   │   ├── compose.yaml        # FRP (server) deployment
│   │   ├── frps.toml           
│   │   └── nginx.conf
│   └── readme.md
└── speedtest-tracker
    ├── compose.yaml            # Self-hosted internet speed monitoring
    ├── readme.md
    └── sample.env.sample
```

Each subdirectory includes a `compose.yaml` file and relevant configs to deploy and manage individual services independently using Docker Compose. This provides scalability, modularity, and ease of maintenance.

---

## Getting Started with Cup

Create the setup using this script or manually:

### One-liner Setup Script for cup agent

```bash
mkdir -p ~/.cup && cat > ~/.cup/compose.yaml <<EOF
services:
  cup:
    image: ghcr.io/sergi0g/cup:latest
    container_name: cup
    restart: unless-stopped
    command: serve
    ports:
      - 8000:8000
    environment:
      - CUP_AGENT=true
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock
EOF

docker compose -f ~/.cup/compose.yaml up -d
```



---

## Final Notes

- This infra is managed manually via Docker Compose grouped by logical services
- Cup backs the observability layer to ensure all containers are up to date
- Services are exposed and reverse-proxied using **Nginx Proxy Manager** and optionally tunneled via FRP