# config

Machine configuration for the only two setups I run: **Omarchy 4 (Quattro)** on
Arch, and **macOS**. The repo is the source of truth: `4 ConfigFiles.sh` copies
files into `~`, and an `omarchy update` hook replays it so migrations cannot
quietly revert customizations.

## New machine

On Arch, install Omarchy first. Then, on either platform:

```sh
curl -fsSL https://raw.githubusercontent.com/SomeoneWithOptions/config/main/bootstrap.sh | sh
```

`bootstrap.sh` downloads this repo to /tmp, runs the numbered scripts in order,
and clones the repo to `~/code/config` for the post-update hook.

## Scripts

| Script | Does |
|---|---|
| `1 SoftwareInstall.sh` | Packages: pacman/yay on Arch, Homebrew on macOS |
| `2 Fonts.sh` | Installs `fonts/` into the platform font dir |
| `3 Git.sh` | Git identity and defaults |
| `4 ConfigFiles.sh` | Copies every config below into `~`; idempotent, rerun any time |
| `5 Keys.sh` | 1Password + SSH keys |
| `tests/smoke.sh` | Syntax/consistency checks. Run before committing |

## Layout

Shared by both platforms:

- `fish/`, `nvim/`, `zed/`, `ghostty/`, `alacritty/`, `fontconfig/`, `gtk-*`,
  `mise/`, `git/` — app config
- `bin/ghui`, `bin/hunk` — helpers installed to `~/.local/bin` everywhere
- `pi/agent/` — pi agent extensions and skills

macOS only:

- `aerospace/` — tiling window manager

Omarchy/Arch only:

- `hypr/` — Hyprland Lua config (`*.lua`) plus `xdph.conf` for screen sharing
- `omarchy/plugins/andres.*` — Quattro shell plugins (bar widgets, frame, menu,
  notifications, idle)
- `omarchy/install-framed-panels.py` — generates `andres.{audio,bluetooth,clock,monitor,network,power,tailscale}`
  by cloning the stock panels and attaching them to the desktop frame. Generated,
  so those seven are not tracked here
- `omarchy/shell.json` / `shell.toml` — bar layout and machine-level theme overrides
- `omarchy/hooks/post-update.d/` — reapply this repo after `omarchy update`
- `quickshell/flicko-picker/` — animated screenshot region picker
- the rest of `bin/` — Hyprland/Omarchy helpers
- `systemd/user/` — battery power-profile and mise Go update timers
- `zen/`, `xdg/` — browser prefs and default-app associations

`terraform/` is unrelated to laptops: it provisions a personal AWS box.

Waybar, Walker, SwayOSD, mako, hypridle and hyprlock are gone: Quattro's
`omarchy-shell` replaces all of them.
