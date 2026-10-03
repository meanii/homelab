#!/bin/sh
# Usage: api.sh METHOD PATH [JSON]  -- calls the local Beszel hub as the admin user from .env
set -e
. /root/beszel/.env
T=$(curl -fsS -X POST localhost:8090/api/collections/users/auth-with-password -H Content-Type:application/json -d "{\"identity\":\"$USER_EMAIL\",\"password\":\"$USER_PASSWORD\"}" | sed -E "s/.*\"token\":\"([^\"]+)\".*/\1/")
if [ -n "$3" ]; then curl -fsS -X "$1" "localhost:8090$2" -H "Authorization: $T" -H Content-Type:application/json -d @-; else curl -fsS -X "$1" "localhost:8090$2" -H "Authorization: $T"; fi
