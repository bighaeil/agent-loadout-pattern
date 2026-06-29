#!/usr/bin/env bash
# read_news.sh — fetch new items since the last watermark (hides the source + watermark mechanics).
#   Illustrative: reads a JSON array from $NEWS_URL and prints items newer than a stored watermark.
#   A real implementation might hit a DB, an API, a queue — the interface ("give me what's new")
#   stays the same.
set -euo pipefail

[ "${1:-}" = "--describe" ] && { echo "read_news|read|new items since the watermark"; exit 0; }

source "$(dirname "${BASH_SOURCE[0]}")/_log.sh"
trap 'tlog ERR "exit=$?"' ERR
tlog INVOKED ""

WM_FILE="${WM_FILE:-$(dirname "${BASH_SOURCE[0]}")/../logs/news.watermark}"
since="$(cat "$WM_FILE" 2>/dev/null || echo '1970-01-01T00:00:00Z')"

curl -s "${NEWS_URL:-http://localhost:8009/news}" \
  | jq -r --arg s "$since" '.[] | select(.publishedAt > $s) | "\(.publishedAt)|\(.headline)"'

tlog OK "since=$since"
