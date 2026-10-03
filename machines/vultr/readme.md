# vultr (Vultr VPS)

Ubuntu 26.04, 1 GB RAM. Relay for the tailnet and a self-hosted RustDesk server. SSH: `ssh vultr` (key only).

| Service | Configuration | Ports |
| --- | --- | --- |
| Tailscale peer relay | `tailscale set --relay-server-port=40000` | 40000/udp |
| RustDesk server (hbbs + hbbr) | [`rustdesk/compose.yaml`](rustdesk/compose.yaml), live at `/root/compose.yml` | 21114-21119/tcp, 21116/udp |
| ufw | [`host/ufw.sh`](host/ufw.sh) | |
| sshd | [`host/sshd.conf`](host/sshd.conf) | 22/tcp |
| fail2ban | [`host/fail2ban-sshd.local`](host/fail2ban-sshd.local): 5 failures in 10 min -> 1 h ban, journal backend | |
| Beszel agent | [`machines/mantis/beszel`](../mantis/beszel) | outbound only |

Clients that cannot connect directly relay through this server; `tailscale status` shows them as `peer-relay <ip>:40000`.

RustDesk keeps its key pair and database in `/root/data` (`id_ed25519`, `id_ed25519.pub`, `db_v2.sqlite3`). Clients pin the public key, so keep a copy of `/root/data` before rebuilding; a new key means reconfiguring every client.

## Rebuild

```bash
apt-get install -y docker.io docker-compose-v2 fail2ban
install -m644 host/fail2ban-sshd.local /etc/fail2ban/jail.d/sshd.local && systemctl restart fail2ban
./host/ufw.sh

curl -fsSL https://tailscale.com/install.sh | sh
tailscale up
tailscale set --relay-server-port=40000 --relay-server-static-endpoints=<VULTR_PUBLIC_IP>:40000

mkdir -p /root/data                      # restore the saved /root/data here first
cp rustdesk/compose.yaml /root/compose.yml
cd /root && docker compose -f compose.yml up -d
```

Then apply [`host/sshd.conf`](host/sshd.conf) (also in `/etc/ssh/sshd_config.d/50-cloud-init.conf`, which cloud-init creates with `PasswordAuthentication yes`) and install the Beszel agent.
