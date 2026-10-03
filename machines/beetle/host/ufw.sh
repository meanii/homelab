#!/usr/bin/env bash
# Host firewall on beetle. Allow SSH first so enabling cannot cut the session.
# Docker-published ports bypass ufw; services that only Caddy needs are
# published on 127.0.0.1 in their compose files instead.
set -euo pipefail
ufw allow 2269/tcp comment ssh
for r in 80/tcp 443/tcp 443/udp 7000/tcp 6000/tcp 9080/tcp 9443/tcp 3478/udp 41641/udp; do ufw allow "$r"; done
ufw allow in on tailscale0
ufw default deny incoming
ufw default allow outgoing
ufw --force enable
ufw status verbose
