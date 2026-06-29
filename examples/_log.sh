#!/usr/bin/env bash
# _log.sh — boundary logging helper. Source it, then call `tlog`.
#
#   tlog <event> [detail]    event: INVOKED | OK | DRY | ERR
#   → logs/tool_invocations.log:  <utc> | <tool> | <event> | <detail>
#
# Separates "the interface was called" (INVOKED) from "what the implementation did"
# (OK/DRY/ERR) — so you verify tool use from logs, not from side effects.
__DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LOG_FILE="${LOG_FILE:-$__DIR/logs/tool_invocations.log}"

tlog() {
  local ev="${1:-?}"; shift 2>/dev/null || true
  mkdir -p "$(dirname "$LOG_FILE")" 2>/dev/null || true
  printf '%s | %-14s | %-7s | %s\n' \
    "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$(basename "$0" .sh)" "$ev" "$*" \
    >> "$LOG_FILE" 2>/dev/null || true
}
