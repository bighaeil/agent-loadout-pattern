#!/usr/bin/env bash
# loadout.sh <tool> [tool...] — print the named tools' self-descriptions.
#   = the loadout a routine "downloads" at wake (drawn from the toolbox). Descriptions come from each tool's
#     --describe (single source of truth) — the skill never re-describes them.
set -euo pipefail

[ "$#" -ge 1 ] || { echo "usage: loadout.sh <tool> [tool...]" >&2; exit 2; }
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$DIR/_log.sh"
tlog INVOKED "$*"

echo "🧰 loadout for this mission"
for t in "$@"; do
  line="$(bash "$DIR/$t.sh" --describe 2>/dev/null || true)"
  if [ -z "$line" ]; then
    echo "  - $t (?): no --describe — add one to $t.sh"
    continue
  fi
  IFS='|' read -r name kind desc <<<"$line"
  echo "  - $name ($kind): $desc"
done
