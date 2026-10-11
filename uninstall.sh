#!/usr/bin/env bash
#
# uninstall.sh -- remove the Pi usage collector and its timer.
#
# Usage: ./uninstall.sh [--yes]
#
# Leaves ~/.config/omarchy/agents/pi-usage.env in place (it may hold your
# own settings); delete it by hand if you want it gone.

set -euo pipefail

ASSUME_YES=0
while (( $# > 0 )); do
  case "$1" in
    --yes|-y) ASSUME_YES=1; shift ;;
    -h|--help) sed -n '2,9p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "unknown option: $1" >&2; exit 1 ;;
  esac
done

UNIT_DIR="${HOME}/.config/systemd/user"
COLLECTOR="${HOME}/.local/bin/pi-agent-usage"
STATE_DIR="${XDG_STATE_HOME:-${HOME}/.local/state}/omarchy/agents/usage"

if (( ! ASSUME_YES )); then
  read -r -p "Remove the Pi usage collector and timer? [y/N] " reply
  [[ $reply == [yY]* ]] || exit 1
fi

if command -v systemctl >/dev/null 2>&1; then
  systemctl --user disable --now pi-agent-usage.timer 2>/dev/null || true
fi

rm -f "$UNIT_DIR/pi-agent-usage.timer" "$UNIT_DIR/pi-agent-usage.service"
rm -f "$COLLECTOR"
rm -f "$STATE_DIR/pi.json"

if command -v systemctl >/dev/null 2>&1; then
  systemctl --user daemon-reload 2>/dev/null || true
fi

if command -v omarchy-shell >/dev/null 2>&1; then
  omarchy-shell omarchy.agents refresh >/dev/null 2>&1 || true
fi

echo "ok removed. (left ${HOME}/.config/omarchy/agents/pi-usage.env in place)"
