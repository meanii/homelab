#!/usr/bin/env bash
# Configures the PBS container after the first `docker compose up -d`:
# admin password, datastore "hdd", prune/GC/verify schedules and the API token
# mantis uses. Prints the token secret once; store it in ~/.config/homelab/pbs.env.
# Run: PBS_INITIAL_PASSWORD=<VALUE> PBS_ADMIN_PASSWORD=<password> bash setup.sh
set -euo pipefail
[[ -n ${PBS_INITIAL_PASSWORD:-} && -n ${PBS_ADMIN_PASSWORD:-} ]] || { echo "set PBS_INITIAL_PASSWORD and PBS_ADMIN_PASSWORD"; exit 1; }
m() { docker exec pbs proxmox-backup-manager "$@"; }

# `user update --password` is silently ignored; the password changes only via PUT /access/password.
API=https://127.0.0.1:8007/api2/json
AUTH=$(curl -sk --data-urlencode username=admin@pbs --data-urlencode "password=$PBS_INITIAL_PASSWORD" "$API/access/ticket")
TICKET=$(jq -r .data.ticket <<<"$AUTH"); CSRF=$(jq -r .data.CSRFPreventionToken <<<"$AUTH")
curl -skf -X PUT -b "PBSAuthCookie=$TICKET" -H "CSRFPreventionToken: $CSRF" \
  --data-urlencode userid=admin@pbs --data-urlencode "password=$PBS_ADMIN_PASSWORD" \
  --data-urlencode "confirmation-password=$PBS_INITIAL_PASSWORD" "$API/access/password" >/dev/null
m datastore create hdd /datastore/hdd
m datastore update hdd --gc-schedule 'sun 10:00'
m prune-job create prune-hdd --store hdd --schedule '*-*-* 06:00' --keep-daily 7 --keep-weekly 4 --keep-monthly 6
m verify-job create verify-hdd --store hdd --schedule 'sat 10:00' --ignore-verified true --outdated-after 30
m user create mantis@pbs
m acl update /datastore/hdd DatastoreBackup --auth-id mantis@pbs   # a token gets at most its user's rights
m user generate-token mantis@pbs pve
m acl update /datastore/hdd DatastoreBackup --auth-id 'mantis@pbs!pve'
# PocketID login (OIDC client "pbs" in PocketID, callback https://pbs.home.aniicrite.dev).
# Skipped unless PBS_OIDC_CLIENT_ID and PBS_OIDC_CLIENT_SECRET are set.
if [[ -n ${PBS_OIDC_CLIENT_ID:-} && -n ${PBS_OIDC_CLIENT_SECRET:-} ]]; then
  m openid create pocketid --issuer-url https://pocketid.ghost.aniicrite.dev \
    --client-id "$PBS_OIDC_CLIENT_ID" --client-key "$PBS_OIDC_CLIENT_SECRET" \
    --username-claim email --scopes email,profile --autocreate false --default true
  m user create "${PBS_OIDC_ADMIN_EMAIL:?}@pocketid"
  m acl update / Admin --auth-id "${PBS_OIDC_ADMIN_EMAIL}@pocketid"
fi
m cert info | grep -i fingerprint
