#!/usr/bin/env bash
# Adds the storages that live on crab's 2 TB HDD (see machines/crab) and what the
# media containers (CT 116-118) need on the host:
#   crab-pbs    Proxmox Backup Server, datastore "hdd", vzdump backups
#   crab-media  NFS 4.2 export /mnt/data/media: ISO images, CT templates and the
#               media tree that CT 116-118 bind-mount as /data
#   uid/gid 1000 mapping allowed for containers (lxc.idmap in 116-118.conf)
#   hookscript require-crab-media.sh: those CTs only start when the NFS share is mounted
# Run on mantis as root:
#   PBS_TOKEN_SECRET=<VALUE> PBS_FINGERPRINT=<VALUE> bash crab-storage.sh
# PBS_FINGERPRINT: on crab, docker exec pbs proxmox-backup-manager cert info
set -euo pipefail
[[ -n ${PBS_TOKEN_SECRET:-} && -n ${PBS_FINGERPRINT:-} ]] || { echo "set PBS_TOKEN_SECRET and PBS_FINGERPRINT"; exit 1; }
CRAB=192.168.0.10
HERE=$(dirname "$0")

pvesm add pbs crab-pbs --server "$CRAB" --datastore hdd --username 'mantis@pbs!pve' \
  --password "$PBS_TOKEN_SECRET" --fingerprint "$PBS_FINGERPRINT" --content backup
pvesm add nfs crab-media --server "$CRAB" --export /mnt/data/media \
  --content iso,vztmpl --options vers=4.2,hard

grep -qx 'root:1000:1' /etc/subuid || echo 'root:1000:1' >>/etc/subuid
grep -qx 'root:1000:1' /etc/subgid || echo 'root:1000:1' >>/etc/subgid

pvesm set local --content iso,vztmpl,backup,snippets
install -D -m755 "$HERE/require-crab-media.sh" /var/lib/vz/snippets/require-crab-media.sh
pvesm status
