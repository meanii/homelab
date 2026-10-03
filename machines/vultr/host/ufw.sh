#!/usr/bin/env bash
# Host firewall on vultr: SSH, Tailscale peer relay, RustDesk.
set -euo pipefail
ufw allow 22/tcp
ufw allow 40000/udp            # tailscale peer relay
ufw allow 21114:21119/tcp      # rustdesk hbbs/hbbr
ufw allow 21116/udp            # rustdesk hbbs
ufw default deny incoming
ufw default allow outgoing
ufw --force enable
ufw status verbose
