# Nginx Proxy Manager + frp: Centralized Reverse Proxy & Secure Tunnel Solution

This repository provides a **Dockerized setup** for securely exposing internal web services to the public internet using [Nginx Proxy Manager (NPM)](https://nginxproxymanager.com/) for reverse proxy management and [frp (Fast Reverse Proxy)](https://github.com/fatedier/frp) for tunneling through NAT/firewalls.

---

## Directory Structure

```
nginxproxymanager/
├── compose.yaml          # Docker Compose for NPM + frpc
├── frpc.toml             # frpc client config (connects to tunnel server)
├── frps/
│   ├── compose.yaml      # Docker Compose for frps server
│   ├── frps.toml         # frps server config
│   └── nginx.conf        # Example Nginx SSL reverse proxy config
└── readme.md             # This file
```

---

## Architecture Diagram

```
                ┌───────────────────────────────┐
                │        Public Internet        │
                └──────────────┬────────────────┘
                               │
                      [DNS: *.example.com]
                               │
                ┌──────────────▼───────────────┐
                │        frps (Server)         │
                │  (Public VPS, ports 7000+)   │
                └──────────────┬───────────────┘
                               │
                    [FRP Tunnel over 7000]
                               │
                ┌──────────────▼───────────────┐
                │         frpc (Client)        │
                │ (On-premises, behind NAT)    │
                └──────────────┬───────────────┘
                               │
                ┌──────────────▼───────────────┐
                │   Nginx Proxy Manager (NPM)  │
                │    (Docker, ports 80/443/81) │
                └──────────────┬───────────────┘
                               │
                ┌──────────────▼───────────────┐
                │   Internal Web Services      │
                └───────────────────────────────┘
```

---

## How It Works & Centralized Access Control

- **All public traffic** for your domain (e.g., `*.example.com`) is routed to the frps server (on a public VPS).
- **frps** forwards HTTP(S) traffic via a secure tunnel to **frpc** on your internal network.
- **frpc** passes this traffic to **Nginx Proxy Manager**, which acts as the *sole entry point* for all web services behind your firewall.
- **Nginx Proxy Manager (NPM)** provides a web UI to:
  - Add/remove proxy hosts (services)
  - Manage SSL certificates (Let's Encrypt)
  - Set up access control (IP allow/deny, HTTP Auth, etc.)
  - Route traffic to specific internal services based on domain/subdomain

**To ban/block public access to all services:**
- Simply remove or disable the relevant proxy host(s) in NPM, or set up global access restrictions (IP whitelisting, HTTP Auth) via the NPM UI.
- All public HTTP(S) traffic is funneled through a single, manageable route, giving you centralized control.

---

## Quick Start

### Prerequisites

- Docker & Docker Compose installed on both local and server machines.
- A domain (e.g., `example.com`) with DNS pointing to your frps server.
- Sufficient server permissions to open required ports (7000, 80, 443).

### 1. Deploy frps (Server Side)

- Edit `frps/frps.toml` for your environment (set web dashboard password, adjust ports if needed).
- (Optional) Update `frps/nginx.conf` for SSL termination.
- Start with:

```bash
cd frps
docker compose up -d
```

### 2. Deploy Nginx Proxy Manager + frpc (Client Side)

- Set `serverAddr` in `frpc.toml` to your frps server's public IP or domain.
- Adjust `customDomains` in `frpc.toml` for your domain/subdomains.
- Start with:

```bash
docker compose up -d
```

### 3. Configure DNS

- Point your wildcard or specific subdomains (e.g., `*.example.com`) to your frps server's public IP.

### 4. Access & Manage

- Visit `http://<frps-server-domain>` or your chosen subdomain.
- Use Nginx Proxy Manager's web UI (default: `http://<host-ip>:81`, login: `admin@example.com` / `changeme`) to add/manage proxy hosts, SSL certificates, and access rules.

---

## Example Use Cases

- Expose self-hosted services (e.g., Home Assistant, Nextcloud) behind NAT/firewall to the internet securely.
- Manage multiple web services and SSL certificates from a single dashboard.
- Use wildcard domains for dynamic subdomain proxying.
- Instantly block or allow public access to all services via NPM.
- Create dev/staging environments accessible from anywhere.

---

## Security Notes

- Change all default passwords before exposing services to the internet.
- Secure your frps dashboard and Nginx Proxy Manager admin panel with strong authentication.
- Consider setting up IP restrictions for admin interfaces.
- Enable SSL for all publicly accessible services.
- Regularly update Docker images for security patches.
- Consider implementing rate limiting for exposed services.

---

## Troubleshooting

- **Connection Issues**: Verify firewall rules allow traffic on ports 7000, 80, and 443.
- **Tunnel Problems**: Check frpc logs for connection errors to frps server.
- **SSL Certificate Errors**: Ensure DNS is properly configured and pointing to your frps server.
- **NPM Access Issues**: Default credentials may need reset via Docker commands if forgotten.

---

## Summary Table

| Component               | Role                                      | Control Point         |
|-------------------------|-------------------------------------------|-----------------------|
| frps (Server)           | Public-facing tunnel server               | VPS/Cloud             |
| frpc (Client)           | Tunnel client, forwards to NPM            | On-premises           |
| Nginx Proxy Manager     | Central reverse proxy, SSL, access control| Web UI (port 81)      |
| Internal Services       | Actual web apps (never exposed directly)  | NPM Proxy Host config |

---

## References

- [Nginx Proxy Manager Documentation](https://nginxproxymanager.com/guide/)
- [frp (Fast Reverse Proxy) Documentation](https://github.com/fatedier/frp)
- [Nginx Proxy Manager Setup Guide](https://www.linode.com/docs/guides/using-nginx-proxy-manager/)
- [Reverse Proxy Concepts](https://www.nginx.com/resources/glossary/reverse-proxy-server/)
- [Docker Compose Documentation](https://docs.docker.com/compose/)

---

> **Nginx Proxy Manager is a fantastic tool for anyone looking to simplify their reverse proxy and SSL management tasks. When combined with frp, it creates a powerful solution for securely exposing internal services. Whether you're hosting a single website or managing multiple applications, it makes the process smoother with its user-friendly interface, SSL automation, and robust reverse proxy capabilities.**
