# Pi usage in the Omarchy agents panel

Make the stock `omarchy.agents` bar widget show **Pi** usage on Omarchy,
including when Pi runs through a backend Omarchy doesn't know about
(`opencode`, `openrouter`, …).

No third-party code, no changes to `/usr/share/omarchy` — just a small
collector and a systemd user timer.

---

## The problem

The bar's agents widget discovers one JSON record per agent in
`~/.local/state/omarchy/agents/usage/` and draws a tab for each. The stock
collectors *do* scan `~/.pi/agent/sessions`, but they filter hard on the
backend:

| Collector | Only counts pi sessions where |
|---|---|
| `omarchy-agent-usage-claude` | `provider == "anthropic"` |
| `omarchy-agent-usage-codex`  | `provider == "openai-codex"` |

If Pi is configured with any other provider, every record stays at zero, the
widget finds nothing to show, and it **hides itself completely** — no icon, no
panel, no hint. This is the exact upstream gap in
[basecamp/omarchy#8270](https://github.com/basecamp/omarchy/issues/8270).

The data is already there: Pi writes `provider`, `model`, and token `usage` on
every assistant message, whatever the backend. This project just reads it.

## Install

Copy the folder to the target machine and run the installer:

```bash
scp -r omarchy-pi-agents user@other-machine:~
ssh user@other-machine
cd ~/omarchy-pi-agents
./install.sh
```

That's it. The agents panel grows a **Pi** tab within a few seconds (the
installer asks the running shell to rescan).

Options:

```bash
./install.sh --providers opencode     # only count pi sessions on this backend
./install.sh --interval 5min          # refresh cadence (systemd time span)
./install.sh --no-timer               # install collector only, no systemd
./install.sh --no-icon                # skip cloning the widget for the Pi mark
./install.sh --yes                    # non-interactive
```

Re-running is safe and idempotent.

## What it installs

| Path | Purpose |
|---|---|
| `~/.local/bin/pi-agent-usage` | The collector (Python 3, stdlib only) |
| `~/.config/systemd/user/pi-agent-usage.service` | Runs the collector (oneshot) |
| `~/.config/systemd/user/pi-agent-usage.timer` | 2 min after login, then every 15 min |
| `~/.config/omarchy/agents/pi-usage.env` | Optional settings (created once, never clobbered) |
| `~/.config/omarchy/plugins/<user>.agents/assets/pi.svg` | Pi mark for the panel hero (see [Pi icon](#pi-icon)) |
| `~/.local/state/omarchy/agents/usage/pi.json` | The record the panel reads |

The collector scans `~/.pi/agent/sessions` and `~/.omp/agent/sessions`,
aggregates every assistant message, and atomically replaces `pi.json`
(temp file + `rename`, mode `600`) so the panel never reads a partial file.

## Pi icon

The panel draws a provider mark as `assets/<id>.svg` **relative to its own
plugin directory**, so a user mark requires a user-owned copy of the widget.
`install.sh` uses the documented clone workflow and drops in two files:

| File | Surface it is used on |
|---|---|
| `assets/pi.svg` | dark surfaces (white mark) |
| `assets/pi-light.svg` | light surfaces (dark mark) |

```bash
omarchy plugin clone omarchy.agents   # -> ~/.config/omarchy/plugins/<user>.agents
```

Skip it with `./install.sh --no-icon`.

**Trade-off:** the clone is yours to maintain and stops tracking upstream
fixes to the agents widget. If the mark does not appear immediately after
cloning, run `omarchy restart shell` once — the disabled stock widget
otherwise keeps the `omarchy.agents` IPC target and shadows the clone's
handler. The bar button itself stays the generic agents glyph; only the
provider mark inside the panel is provider-specific.

## How it works

```
~/.pi/agent/sessions/**/*.jsonl ─┐
~/.omp/agent/sessions/**/*.jsonl ┴─► pi-agent-usage ─► pi.json ─► omarchy.agents panel
                                    (systemd timer)
```

The record follows Omarchy's contract, so the panel needs no changes:

```jsonc
{
  "schemaVersion": 1,
  "id": "pi",
  "name": "Pi",
  "ready": true,
  "hasLocalStats": true,
  "todayPrompts": 33, "todaySessions": 2, "todayTotalTokens": 901523,
  "todayTokensByModel": { "deepseek-v4.1-flash": 901523 },
  "recentDays": [ { "date": "2026-10-11", "messageCount": 901523 }, ... ],
  "totalPrompts": 197, "totalSessions": 20, "activeDays": 11,
  "activeDates": ["2026-09-25", ...],
  "modelUsage": { "gpt-6.1-sol": { "inputTokens": 0, "outputTokens": 0,
                                    "cacheReadInputTokens": 0,
                                    "cacheCreationInputTokens": 0 } },
  "limits": [], "tierLabel": "", "usageStatusText": "", "authHelpText": ""
}
```

`recentDays[].messageCount` is tokens (same naming quirk the stock collectors
use). `limits` is empty on purpose — Pi has no usage endpoint, so the tab is
local stats only and shows no rate-limit meters.

## Verify

```bash
~/.local/bin/pi-agent-usage                      # run now, prints a summary
systemctl --user list-timers pi-agent-usage.timer
journalctl --user -u pi-agent-usage.service -n 20
omarchy-shell omarchy.agents refresh             # force the panel to rescan
```

If the tab doesn't appear: confirm `pi.json` exists and has
`totalPrompts > 0`, and that the panel is enabled
(`omarchy plugin list | grep agents`).

## Configuration

Edit `~/.config/omarchy/agents/pi-usage.env` (then
`systemctl --user restart pi-agent-usage.timer` or just wait for the next run):

```ini
# Only count sessions that ran through these pi providers (comma-separated).
# Unset/empty = every provider.
PI_AGENT_PROVIDERS=opencode
```

Use this if you want to avoid the intentional overlap: pi sessions on
`anthropic`/`openai-codex` already appear in the stock **Claude** and
**Codex** tabs, so a provider-agnostic Pi tab shows them a second time.

Change the cadence by editing `OnUnitActiveSec=` in
`~/.config/systemd/user/pi-agent-usage.timer`, then:

```bash
systemctl --user daemon-reload && systemctl --user restart pi-agent-usage.timer
```

## Uninstall

```bash
./uninstall.sh          # or ./uninstall.sh --yes
```

Removes the collector, both units, and `pi.json`. The
`~/.config/omarchy/agents/pi-usage.env` template is left behind on purpose.

## Limitations

- **No rate-limit meters / plan / balance.** Pi exposes no usage endpoint, so
  only local token stats are available.
- **Totals include the currently running session**, which is why they tick up
  between runs.
- Counts assistant messages as "prompts", matching the stock collectors'
  semantics.
- Reads files live; it never writes to your Pi session data.

## Alternatives

- **Community plugin** with a richer engine (append cursors, OpenCode DB
  adapter, more adapters via manifests):
  [rohaquinlop/omarchy-agent-collectors](https://github.com/rohaquinlop/omarchy-agent-collectors)
  ```bash
  omarchy plugin add https://github.com/rohaquinlop/omarchy-agent-collectors.git --enable
  ```
- **Upstream fix**: broaden the two `scan_pi_*` filters in
  `/usr/share/omarchy/bin/omarchy-agent-usage-{claude,codex}` so any provider
  is counted. That is the real long-term fix for
  [basecamp/omarchy#8270](https://github.com/basecamp/omarchy/issues/8270);
  editing the package files locally works but is overwritten on
  `omarchy update`.

## Files

```
omarchy-pi-agents/
├── README.md
├── install.sh          # self-contained installer (uses pi-agent-usage + assets)
├── uninstall.sh
├── pi-agent-usage      # the collector
└── assets/
    ├── pi.svg          # panel hero mark, dark surfaces
    └── pi-light.svg    # panel hero mark, light surfaces
```
