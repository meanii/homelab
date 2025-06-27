# Homelab Stacks

> My personal homelab stack: self-hosted services, automation, and reverse proxy setup – all running on Proxmox. 🦉

---

## Table of Contents

- [About](#about)
- [Getting Started](#getting_started)
- [Running Services](#running_services)
- [Architecture](#architecture)
- [TODO](#todo)

---

## About <a name = "about"></a>

This repository contains a collection of services I run on my homelab, now hosted on **Proxmox**. The setup uses:

- **Proxmox** for VM/container orchestration.
- A **VPS** as a public-facing FRP tunnel server.
- **Nginx Proxy Manager** as a centralized reverse proxy.
- **frp (Fast Reverse Proxy)** for secure tunneling behind NAT.
- **Docker** for managing all services.

Public access is routed through the VPS using **frps**, tunneled to my local network with **frpc**, and managed through **Nginx Proxy Manager**, giving me full control over HTTPS, access rules, and subdomain routing.

---

## Getting Started <a name = "getting_started"></a>

### Prerequisites

- Proxmox host with Docker installed (or LXC with Docker)
- Public VPS (used for tunnel server)
- Domain name (e.g., `example.com`)

---

## Running Services <a name = "running_services"></a>

### Reverse Proxy & Secure Tunnel

- [`nginxproxymanager`](proxmox/nginxproxymanager)  
  Centralized reverse proxy UI + `frpc` tunnel client.
- `frps` (runs on VPS)  
  Reverse tunnel server that bridges internet requests to local services.

### Media Stack

- [`media`](proxmox/media)
  - **Jellyfin** – Media streaming
  - **qBittorrent** + **qBittorrentBot** – Torrent downloads + Telegram control
  - **Radarr**, **Sonarr**, **Prowlarr** – Media automation
  - **Jellyseerr** – Discovery and request frontend


---

## Architecture <a name="architecture"></a>

```text
               ┌──────────────────────────────┐
               │        Public Internet       │
               └──────────────┬───────────────┘
                              │
                    [DNS: *.example.com]
                              │
               ┌──────────────▼──────────────┐
               │        frps (VPS)           │
               │      [Reverse Tunnel]       │
               └──────────────┬──────────────┘
                              │
               ┌──────────────▼──────────────┐
               │       frpc (Proxmox)        │
               │      [Tunnel Client]        │
               └──────────────┬──────────────┘
                              │
               ┌──────────────▼──────────────┐
               │  Nginx Proxy Manager (NPM)  │
               │      [Reverse Proxy]        │
               └──────────────┬──────────────┘
                              │
     ┌───────────────┬────────┴────────┬────────────────┐
     ▼               ▼                 ▼                ▼
 [Media]      [Notes/Docs]        [Utilities]      [Monitoring]
 Jellyfin     Memos               Pi-hole           Uptime-Kuma
 qBit/Radarr  Glance              sshm              Glance
````

---

## TODO <a name = "todo"></a>

* [ ] Add backup automation playbooks
* [ ] Expand Kubernetes service deployments
* [ ] Add documentation for Glance and Memos setup
* [ ] Setup Grafana + Prometheus for resource monitoring

---

## Homelab Snapshot

<img src="assets/homelab.jpg" width="300" height="300">

---

## Repository Layout

```
homelab/
├── docker/                  # Docker services
│   └── pi-hole/             # Encrypted DNS + Pi-hole
├── proxmox/                 # Main stack now runs here
│   ├── nginxproxymanager/   # Reverse proxy + frp
│   └── media/               # Jellyfin, qBit, Radarr, etc.
├── kubernetes/              # K8s manifests
│   └── uptime-kube/
├── services/                # Custom systemd services
│   └── sshm/
├── playbooks/               # Ansible automation
├── assets/                  # Diagrams & images
└── readme.md
```
