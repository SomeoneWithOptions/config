# config

Machine configuration for the only two setups I run: **Omarchy 4 (Quattro)** on
Arch, and **macOS**. `4 ConfigFiles.sh` copies files into `~`. After every
`omarchy update` a hook runs `4 ConfigFiles.sh --check`, which writes nothing:
it diffs `~` against the repo and notifies when migrations or other tools
changed a managed file. You then either apply the repo state or port the live
change into the repo. Nothing is overwritten behind your back.

## New machine

On Arch, install Omarchy first. Then, on either platform:

```sh
curl -fsSL https://raw.githubusercontent.com/SomeoneWithOptions/config/main/bootstrap.sh | sh
```

`bootstrap.sh` downloads this repo to /tmp and runs the numbered scripts in
order. On Arch, `4 ConfigFiles.sh` also clones the repo to `~/code/config` for
the post-update drift check.

Nothing in the run waits for a login. Tailscale and 1Password are installed but
left signed out. Commiter, Loom for Omarchy, and the Linear Omarchy plugin are
also installed through their unattended curl installers. Linear skips its
account-specific setup when no API key is already stored.

Manual follow-ups:

```sh
sudo tailscale up --accept-routes   # or set TS_AUTHKEY=tskey-... before the run
~/.config/omarchy/plugins/andres.linear/bin/omarchy-linear-setup key
~/.config/omarchy/plugins/andres.linear/bin/omarchy-linear-setup use "Team" "Project"
```

## Scripts

| Script | Does |
|---|---|
| `1 SoftwareInstall.sh` | Packages plus personal tools: commiter everywhere; Loom and Linear plugin on Omarchy |
| `2 Fonts.sh` | Installs `fonts/` into the platform font dir |
| `3 Git.sh` | Git identity and defaults |
| `4 ConfigFiles.sh` | Copies every config below into `~`; idempotent, rerun any time. `--check` diffs instead of writing |
| `5 Keys.sh` | 1Password + SSH keys |
| `tests/smoke.sh` | Syntax/consistency checks. Run before committing |

## Layout

Shared by both platforms:

- `fish/`, `zed/`, `foot/`, `ghostty/`, `alacritty/`, `fontconfig/`, `gtk-*`,
  `git/` — app config
- `bin/ghui`, `bin/hunk` — helpers installed to `~/.local/bin` everywhere
- `pi/agent/` — pi agent extensions and skills

macOS only:

- `aerospace/` — tiling window manager

Omarchy/Arch only:

- `hypr/` — Hyprland Lua config (`*.lua`) plus `xdph.conf` for screen sharing
- `omarchy/plugins/andres.*` — Quattro shell plugins (bar widgets, frame, menu,
  notifications, idle, dnd); `andres.tray` gives every application tray menu the
  same attached, outward-curved frame used by built-in panels. `andres.idle` and
  `andres.dnd` are status-only icons: each shows solely while its non-default
  state is on (staying awake, notifications silenced)
- `omarchy/install-framed-panels.py` — generates `andres.{audio,bluetooth,clock,monitor,network,power,tailscale}`
  by cloning the stock panels and attaching them to the desktop frame. Generated,
  so those seven are not tracked here
- `omarchy/shell.json` / `shell.toml` — bar layout and machine-level theme overrides
- `omarchy/hooks/` — post-update drift report (`~/.local/state/omarchy/config-drift.diff`) and Zed theme sync
- `quickshell/flicko-picker/` — animated screenshot region picker; the optional
  `color` file there pins its accent to a fixed hex, otherwise it follows the theme
- the rest of `bin/` — Hyprland/Omarchy helpers
- `systemd/user/` — mise Go upgrades and random-background timers
- `zen/`, `xdg/` — browser prefs and default-app associations

Waybar, Walker, SwayOSD, mako, hypridle and hyprlock are gone: Quattro's
`omarchy-shell` replaces all of them.
