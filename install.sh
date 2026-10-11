#!/usr/bin/env bash
#
# install.sh -- make Pi usage show up in the Omarchy agents panel.
#
# Installs a provider-agnostic Pi usage collector plus a systemd user timer
# that refreshes it, then nudges the running shell to rescan.
#
# Usage:
#   ./install.sh [--interval 15min] [--providers opencode] [--no-timer] [--yes]
#
# Run from the directory that contains pi-agent-usage (the collector).
# Idempotent: safe to re-run.

set -euo pipefail

# ---------------------------------------------------------------- defaults
INTERVAL="15min"
PROVIDERS=""
WITH_TIMER=1
ASSUME_YES=0

BIN_DIR="${HOME}/.local/bin"
COLLECTOR="${BIN_DIR}/pi-agent-usage"
UNIT_DIR="${HOME}/.config/systemd/user"
CONF_DIR="${HOME}/.config/omarchy/agents"
ENV_FILE="${CONF_DIR}/pi-usage.env"
STATE_DIR="${XDG_STATE_HOME:-${HOME}/.local/state}/omarchy/agents/usage"
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
COLLECTOR_SRC="${SCRIPT_DIR}/pi-agent-usage"

# ------------------------------------------------------------------ output
if [[ -t 1 ]]; then
  C_INFO=$'\033[1;34m'; C_OK=$'\033[1;32m'; C_WARN=$'\033[1;33m'; C_OFF=$'\033[0m'
else
  C_INFO=""; C_OK=""; C_WARN=""; C_OFF=""
fi
info() { printf '%s==>%s %s\n' "$C_INFO" "$C_OFF" "$*"; }
ok()   { printf '%s ok %s %s\n' "$C_OK" "$C_OFF" "$*"; }
warn() { printf '%swarn%s %s\n' "$C_WARN" "$C_OFF" "$*" >&2; }
die()  { printf 'error: %s\n' "$*" >&2; exit 1; }

# ------------------------------------------------------------------- args
while (( $# > 0 )); do
  case "$1" in
    --interval)  INTERVAL="${2:?--interval needs a value}"; shift 2 ;;
    --providers) PROVIDERS="${2:?--providers needs a value}"; shift 2 ;;
    --no-timer)  WITH_TIMER=0; shift ;;
    --yes|-y)    ASSUME_YES=1; shift ;;
    -h|--help)
      sed -n '2,12p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
      exit 0 ;;
    *) die "unknown option: $1 (see --help)" ;;
  esac
done

# --------------------------------------------------------------- preflight
command -v python3 >/dev/null 2>&1 || die "python3 is required but not on PATH"
[[ -f $COLLECTOR_SRC ]] || die "collector not found at $COLLECTOR_SRC (copy the whole folder, or keep pi-agent-usage next to install.sh)"

if [[ ! -d /usr/share/omarchy ]]; then
  warn "no /usr/share/omarchy found -- this does not look like an Omarchy box"
  if (( ! ASSUME_YES )); then
    read -r -p "Continue anyway? [y/N] " reply
    [[ $reply == [yY]* ]] || exit 1
  fi
fi

mkdir -p "$BIN_DIR" "$UNIT_DIR" "$CONF_DIR" "$STATE_DIR"

# --------------------------------------------------------------- collector
info "Installing collector -> $COLLECTOR"
install -m 0755 "$COLLECTOR_SRC" "$COLLECTOR"

# Optional provider allow-list, loaded by the service. Never clobber an
# existing file; only write the commented template on first install.
if [[ ! -f $ENV_FILE ]]; then
  info "Writing config template -> $ENV_FILE"
  cat > "$ENV_FILE" <<'ENV'
# Restrict the Pi tab to specific pi backends (comma-separated).
# Leave unset/empty to count every provider.
# PI_AGENT_PROVIDERS=opencode
ENV
fi

# If the caller passed --providers, persist it (or clear it) in the env file.
if [[ -n $PROVIDERS ]]; then
  if grep -q '^PI_AGENT_PROVIDERS=' "$ENV_FILE"; then
    sed -i "s|^PI_AGENT_PROVIDERS=.*|PI_AGENT_PROVIDERS=${PROVIDERS}|" "$ENV_FILE"
  else
    printf 'PI_AGENT_PROVIDERS=%s\n' "$PROVIDERS" >> "$ENV_FILE"
  fi
  ok "Provider allow-list set to: $PROVIDERS"
fi

# -------------------------------------------------------------- systemd
if (( WITH_TIMER )); then
  info "Installing systemd user units -> $UNIT_DIR"
  cat > "$UNIT_DIR/pi-agent-usage.service" <<'UNIT'
[Unit]
Description=Collect Pi agent usage for the omarchy agents panel

[Service]
Type=oneshot
EnvironmentFile=-%h/.config/omarchy/agents/pi-usage.env
ExecStart=%h/.local/bin/pi-agent-usage
UNIT

  # OnActiveSec (relative to the timer starting) guarantees a first run even
  # when the timer is (re)started long after boot; OnUnitActiveSec then keeps
  # rescheduling relative to each service run. Using OnBootSec instead can
  # leave the timer with no next elapse after a restart/reinstall.
  cat > "$UNIT_DIR/pi-agent-usage.timer" <<UNIT
[Unit]
Description=Refresh Pi agent usage periodically

[Timer]
OnActiveSec=2min
OnUnitActiveSec=${INTERVAL}

[Install]
WantedBy=timers.target
UNIT
fi

# ---------------------------------------------------------- run + activate
info "Running collector once"
# shellcheck disable=SC1090
if [[ -f $ENV_FILE ]]; then set -a; . "$ENV_FILE"; set +a; fi
"$COLLECTOR"

if (( WITH_TIMER )); then
  if systemctl --user show-environment >/dev/null 2>&1; then
    info "Enabling systemd timer (every ${INTERVAL})"
    systemctl --user daemon-reload
    systemctl --user enable --now pi-agent-usage.timer >/dev/null
    ok "timer enabled; next run:"
    systemctl --user list-timers pi-agent-usage.timer --no-pager | sed -n '2p'
  else
    warn "systemd --user is unavailable; skipping the timer."
    warn "Run '$COLLECTOR' yourself (cron, shell startup, ...) to refresh."
  fi
fi

# Ask the running shell to rescan the usage directory.
if command -v omarchy-shell >/dev/null 2>&1; then
  if omarchy-shell omarchy.agents refresh >/dev/null 2>&1; then
    ok "asked omarchy-shell to refresh the agents panel"
  else
    warn "could not reach omarchy-shell; open the agents panel to trigger a rescan"
  fi
fi

# --------------------------------------------------------------- epilogue
printf '\n'
ok "Done. The agents panel should now show a 'Pi' tab."
cat <<EOF

  record     : ${STATE_DIR}/pi.json
  run now    : ${COLLECTOR}
  timer      : systemctl --user list-timers pi-agent-usage.timer
  logs       : journalctl --user -u pi-agent-usage.service -n 20
  uninstall  : ./uninstall.sh

EOF
