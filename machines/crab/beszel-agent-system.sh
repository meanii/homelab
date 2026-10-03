#!/usr/bin/env bash
# Installs crab's Beszel agent as a system service with S.M.A.R.T. access.
# Expects the user-level install from readme.md (binary in ~/.local/bin, settings
# in ~/.config/beszel-agent/env) and moves it to the system layout used on the
# other machines, keeping the saved fingerprint so the hub sees the same system.
# Run: sudo bash beszel-agent-system.sh
set -euo pipefail
[[ $(id -u) -eq 0 && -n ${SUDO_USER:-} ]] || { echo "run with sudo from your user"; exit 1; }
U=$SUDO_USER; H=$(getent passwd "$U" | cut -d: -f6); UID_N=$(id -u "$U")

apt-get install -y -qq smartmontools >/dev/null
id beszel >/dev/null 2>&1 || useradd --system --home-dir /nonexistent --shell /usr/sbin/nologin beszel
getent group docker >/dev/null && usermod -aG docker beszel

install -D -m755 "$H/.local/bin/beszel-agent" /opt/beszel-agent/beszel-agent
install -m600 "$H/.config/beszel-agent/env" /etc/beszel-agent.env
install -d -o beszel -g beszel -m750 /var/lib/beszel-agent
[[ -f $H/.config/beszel/fingerprint ]] && install -o beszel -g beszel -m644 "$H/.config/beszel/fingerprint" /var/lib/beszel-agent/fingerprint

cat >/etc/systemd/system/beszel-agent.service <<'UNIT'
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
UNIT
mkdir -p /etc/systemd/system/beszel-agent.service.d
cat >/etc/systemd/system/beszel-agent.service.d/smart.conf <<'UNIT'
[Service]
AmbientCapabilities=CAP_SYS_RAWIO CAP_SYS_ADMIN
CapabilityBoundingSet=CAP_SYS_RAWIO CAP_SYS_ADMIN
SupplementaryGroups=disk
Environment="SMART_DEVICES=/dev/nvme0n1:nvme,/dev/nvme1n1:nvme,/dev/sda"
Environment="EXTRA_FILESYSTEMS=sda1__Data HDD"
UNIT

# stop the user service before the system one connects
sudo -u "$U" XDG_RUNTIME_DIR=/run/user/$UID_N systemctl --user disable --now beszel-agent 2>/dev/null || true
rm -f "$H/.config/systemd/user/beszel-agent.service"
sudo -u "$U" XDG_RUNTIME_DIR=/run/user/$UID_N systemctl --user daemon-reload || true

systemctl daemon-reload
systemctl enable --now beszel-agent
sleep 5
systemctl is-active beszel-agent
