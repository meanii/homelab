#!/bin/sh
# Proxmox hookscript for CTs that bind-mount crab's media share (/mnt/pve/crab-media -> /data).
# pre-start fails while the NFS share is not mounted, so no container starts against an
# empty directory (Jellyfin or Radarr would then mark the whole library missing).
[ "$2" = pre-start ] || exit 0
for i in $(seq 1 30); do
  mountpoint -q /mnt/pve/crab-media && exit 0
  pvesm status --storage crab-media >/dev/null 2>&1   # triggers the mount
  sleep 2
done
echo "crab-media (NFS from crab) is not mounted; not starting CT $1" >&2
exit 1
