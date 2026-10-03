#!/usr/bin/env bash
# Sets up crab's 2 TB HDD (ext4, label "data") as storage for mantis:
#   /mnt/data/pbs    Proxmox Backup Server datastore (pbs/compose.yaml)
#   /mnt/data/media  NFS export for mantis (storage crab-media), capped at 1.2 TB
#                    by an ext4 project quota so media can never fill the disk PBS uses
# Also adds the firewall rules and the Beszel filesystem name.
# Stop PBS first (docker stop pbs): enabling quotas needs the disk unmounted.
# Run: sudo bash storage-setup.sh
set -euo pipefail
[[ $(id -u) -eq 0 ]] || { echo "run with sudo"; exit 1; }
MANTIS=192.168.0.122
NPM=192.168.0.203
DEV=/dev/disk/by-label/data
MNT=/mnt/data
MEDIA=$MNT/media
PROJECT=1000                  # project id of the media tree
MEDIA_LIMIT_KIB=1258291200    # 1200 GiB

apt-get install -y -qq nfs-kernel-server quota >/dev/null

# 1. mount point and project quotas
mkdir -p "$MNT"
mountpoint -q "$MNT" || chattr +i "$MNT"   # empty mount point stays read-only when the disk is missing
if ! tune2fs -l "$DEV" | grep -q 'features:.*project'; then
  if mountpoint -q "$MNT"; then umount "$MNT"; fi
  e2fsck -fy "$DEV"
  tune2fs -O quota,project "$DEV"
  tune2fs -Q prjquota "$DEV"
fi
sed -i '\#^LABEL=data #d' /etc/fstab
echo "LABEL=data $MNT ext4 defaults,noatime,nofail,prjquota 0 2" >>/etc/fstab
systemctl daemon-reload
mountpoint -q "$MNT" || mount "$MNT"
chmod 755 "$MNT"

# 2. directories (uid/gid 1000 = anil here and the media apps in CT 116-118 through their idmap)
# Docker is rootless: PBS container uid 34 (backup) is host uid 100000 + 34 - 1
install -d -o 100033 -g 100033 -m750 "$MNT/pbs"
install -d -o 1000 -g 1000 -m775 "$MEDIA" "$MEDIA/torrents" "$MEDIA/library" "$MEDIA/template"
install -d -o 1000 -g 1000 -m775 "$MEDIA"/torrents/{movies,tv,anime} "$MEDIA"/library/{movies,tv,anime} "$MEDIA"/template/{iso,cache}
chattr -R -p "$PROJECT" +P "$MEDIA"
setquota -P "$PROJECT" 0 "$MEDIA_LIMIT_KIB" 0 0 "$MNT"

# 3. NFS 4.2 export, mantis only
cat >/etc/exports <<EOF
# /mnt/data/media for mantis only (Proxmox storage crab-media, bind-mounted into CT 116-118 as /data)
$MEDIA $MANTIS(rw,sync,no_subtree_check,no_root_squash,sec=sys)
EOF
cat >/etc/nfs.conf.d/homelab.conf <<'EOF'
[nfsd]
vers3=n
vers4.0=n
vers4.1=n
vers4.2=y
EOF
systemctl enable nfs-server
systemctl restart nfs-server

# 4. firewall: PBS and NFS from mantis, PBS UI from NPM
ufw allow from "$MANTIS" to any port 8007 proto tcp comment 'PBS from mantis'
ufw allow from "$NPM" to any port 8007 proto tcp comment 'PBS UI via NPM (CT 107)'
ufw allow from "$MANTIS" to any port 2049 proto tcp comment 'NFS from mantis'

# 5. Beszel: show the disk as "Data HDD"
sed -i 's#^Environment="EXTRA_FILESYSTEMS=.*#Environment="EXTRA_FILESYSTEMS=sda1__Data HDD"#' /etc/systemd/system/beszel-agent.service.d/smart.conf
systemctl daemon-reload
systemctl restart beszel-agent

findmnt "$MNT"; exportfs -v; repquota -P "$MNT"
