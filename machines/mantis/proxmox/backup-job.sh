#!/usr/bin/env bash
# vzdump jobs to the Proxmox Backup Server on crab (storage crab-pbs, see
# crab-storage.sh). Only the critical containers: Immich (with its photo library)
# nightly; Vaultwarden, NPM, PocketID and the media apps (116 Jellyfin, 117 arr,
# 118 Tdarr: configs only) weekly. The media itself is a bind mount (/data) and
# vzdump never includes bind mounts; /scratch holds the media apps' temp files.
# Retention is the PBS prune job.
set -euo pipefail
common=(--storage crab-pbs --mode snapshot --compress zstd \
  --notification-mode notification-system --notes-template '{{guestname}}' --enabled 1)
pvesh create /cluster/backup --id daily-immich --schedule '01:00' --vmid 100 "${common[@]}"
pvesh create /cluster/backup --id weekly-backup --schedule 'sun 02:00' --vmid 101,107,115,116,117,118 \
  --exclude-path /scratch "${common[@]}"
