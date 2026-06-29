#!/usr/bin/env bash
# notify.sh — send a notification (hides the URL + payload mechanics).
# Usage: notify.sh <TYPE> <TITLE> <MESSAGE>
#   DRY_RUN=1  → log only, do NOT send (a stub implementation; interface unchanged).
#   NOTIFY_URL → override the endpoint.
set -euo pipefail

[ "${1:-}" = "--describe" ] && { echo "notify|action|send a notification (webhook)"; exit 0; }

source "$(dirname "${BASH_SOURCE[0]}")/_log.sh"
trap 'tlog ERR "exit=$?"' ERR
[ "$#" -eq 3 ] || { echo "usage: notify.sh <TYPE> <TITLE> <MESSAGE>" >&2; exit 2; }
TYPE="$1"; TITLE="$2"; MSG="$3"
tlog INVOKED "$TYPE | $TITLE"

payload="$(jq -n --arg t "$TYPE" --arg ti "$TITLE" --arg m "$MSG" '{type:$t,title:$ti,message:$m}')"

if [ "${DRY_RUN:-0}" = "1" ]; then
  tlog DRY "$TYPE"
  echo "[DRY_RUN] would POST: $payload"
  exit 0
fi

curl -s -X POST "${NOTIFY_URL:-http://localhost:9000/notify}" \
     -H 'Content-Type: application/json' -d "$payload"
tlog OK "$TYPE"
