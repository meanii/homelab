#!/usr/bin/env bash
# Installs or reconfigures the Beszel agent as a systemd service (Linux amd64).
# Run as root:  KEY='ssh-ed25519 ...' TOKEN='<token>' ./install-agent.sh
#
# The agent dials out to the hub over WebSocket (HUB_URL). Its own listener
# is bound to localhost, so no port is exposed on the host.
set -euo pipefail

VERSION=${VERSION:-0.20.0}
HUB_URL=${HUB_URL:-https://beszel.ghost.aniicrite.dev}
[[ -n ${KEY-} ]] || { echo "KEY (hub public key) is required" >&2; exit 1; }
[[ -n ${TOKEN-} ]] || { echo "TOKEN (universal or per-system token) is required" >&2; exit 1; }
[[ $(id -u) -eq 0 ]] || { echo "run as root" >&2; exit 1; }

bin=/opt/beszel-agent/beszel-agent
if ! [[ -x $bin ]] || ! "$bin" -v 2>/dev/null | grep -q "$VERSION"; then
	tmp=$(mktemp -d)
	trap 'rm -rf "$tmp"' EXIT
	base=https://github.com/henrygd/beszel/releases/download/v$VERSION
	tarball=beszel-agent_linux_amd64.tar.gz
	curl -fsSL -o "$tmp/$tarball" "$base/$tarball"
	curl -fsSL -o "$tmp/sums" "$base/beszel_${VERSION}_checksums.txt"
	(cd "$tmp" && grep " $tarball\$" sums | sha256sum -c -)
	tar -xzf "$tmp/$tarball" -C "$tmp" beszel-agent
	install -D -m755 "$tmp/beszel-agent" "$bin"
fi

id beszel >/dev/null 2>&1 || useradd --system --home-dir /nonexistent --shell /usr/sbin/nologin beszel
getent group docker >/dev/null && usermod -aG docker beszel

umask 077
cat >/etc/beszel-agent.env <<EOF
KEY=$KEY
TOKEN=$TOKEN
HUB_URL=$HUB_URL
LISTEN=127.0.0.1:45876
EOF
chmod 600 /etc/beszel-agent.env

cat >/etc/systemd/system/beszel-agent.service <<'EOF'
[Unit]
Description=Beszel Agent Service
Wants=network-online.target
After=network-online.target

[Service]
EnvironmentFile=/etc/beszel-agent.env
ExecStart=/opt/beszel-agent/beszel-agent
User=beszel
Restart=on-failure
RestartSec=5
StateDirectory=beszel-agent
KeyringMode=private
LockPersonality=yes
NoNewPrivileges=yes
ProtectClock=yes
ProtectHome=read-only
ProtectHostname=yes
ProtectKernelLogs=yes
ProtectSystem=strict
RemoveIPC=yes
RestrictSUIDSGID=true

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable beszel-agent >/dev/null 2>&1
systemctl restart beszel-agent
sleep 3
systemctl is-active beszel-agent
