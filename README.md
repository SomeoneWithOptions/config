# config

Laptop configuration for **Omarchy 4 (Quattro)** on Arch. The repo is the source
of truth: `4 ConfigFiles.sh` copies files into `~`, and an `omarchy update` hook
replays it so migrations cannot quietly revert customizations.

## New laptop

Install Omarchy first, then:

```sh
curl -fsSL https://raw.githubusercontent.com/SomeoneWithOptions/config/main/bootstrap.sh | sh
```

`bootstrap.sh` downloads this repo to /tmp, runs the numbered scripts in order,
and clones the repo to `~/code/config` for the post-update hook.

## Scripts

| Script | Does |
|---|---|
| `1 SoftwareInstall.sh` | Packages (pacman/yay, plus apt and brew branches) |
| `2 Fonts.sh` | Installs `fonts/` into `~/.local/share/fonts` |
| `3 Git.sh` | Git identity and defaults |
| `4 ConfigFiles.sh` | Copies every config below into `~`; idempotent, rerun any time |
| `5 Keys.sh` | 1Password + SSH keys |
| `tests/smoke.sh` | Syntax/consistency checks. Run before committing |

## Layout

- `hypr/` — Hyprland Lua config (`*.lua`) plus `xdph.conf` for screen sharing
- `omarchy/plugins/andres.*` — Quattro shell plugins (bar widgets, frame, menu,
  notifications, idle)
- `omarchy/install-framed-panels.py` — generates `andres.{audio,bluetooth,clock,monitor,network,power}`
  by cloning the stock panels and attaching them to the desktop frame. Generated,
  so those six are not tracked here
- `omarchy/shell.json` / `shell.toml` — bar layout and machine-level theme overrides
- `bin/` — helpers installed to `~/.local/bin`
- `quickshell/flicko-picker/` — animated screenshot region picker
- `fish/`, `nvim/`, `zed/`, `ghostty/`, `alacritty/`, `gtk-*`, `fontconfig/` — app config
- `pi/agent/` — pi agent extensions and skills
- `systemd/user/` — battery power-profile and mise Go update timers

Waybar, Walker, SwayOSD, mako, hypridle and hyprlock are gone: Quattro's
`omarchy-shell` replaces all of them.
