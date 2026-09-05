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

### Progress and logs

Bootstrap shows stage progress and elapsed time instead of package-manager and
file-copy output. Long stages report that they are still running every 30 seconds.
On Omarchy, `omarchy toggle idle stay-awake` runs before software installation to
prevent the screensaver and idle lock during the whole bootstrap. The explicit
`stay-awake` mode is safe on repeated runs; a bare toggle could re-enable idle.
Bootstrap restores normal idle on exit unless stay-awake was already enabled.

Warnings and a deduplicated **ACTION NEEDED** checklist appear after installation,
with commands to run and config paths to edit. Missing logins are deferred, not
reported as successful setup. Optional software failures remain warnings; a fatal
script failure stops bootstrap with that script's exit code (including SSH keys).

Each run keeps private files under `/tmp/config-bootstrap.XXXXXX/`:

- `install.log` — detailed stdout/stderr, stage boundaries, timings, final summary
- `summary.txt` — warnings and remaining manual steps
- `source/` — downloaded repo, also used by printed rerun commands

The directory is mode `700`; log and summary are mode `600`. Logs are temporary:
copy them elsewhere before `/tmp` is cleaned if needed. Rerun commands using the
extracted repo also expire when it is removed. On Arch, `~/code/config` provides a
long-lived alternative once cloned successfully.

To stream detailed output too:

```sh
curl -fsSL https://raw.githubusercontent.com/SomeoneWithOptions/config/main/bootstrap.sh | BOOTSTRAP_VERBOSE=1 sh
```

`NO_COLOR=1` disables color; redirected output is always plain. Bootstrap asks
for sudo once with `sudo -v`, then refreshes that credential non-interactively
while installation runs. Omarchy's own privileged update steps reuse it. Without
a terminal, bootstrap requires cached/passwordless sudo credentials and fails
rather than waiting for input. Numbered scripts still print their own output when
run directly; `4 ConfigFiles.sh --check` retains its read-only diff output.

On Arch, bootstrap runs `omarchy update -y`, Omarchy's supported unattended
update entrypoint. Direct `sudo pacman -Syu` is intentionally rejected by
Omarchy's transaction hook because it skips update logging, snapshots, keyrings,
migrations, post-update hooks, update state, and restart checks. Bootstrap does
not bypass that guard. Omarchy normally starts a second `script(1)` transcript;
bootstrap marks its own transcript as already active so update stays on same TTY
and reuses one sudo authentication. Output still feeds Omarchy's expected
`/tmp/omarchy-update.log` (mode `600`) and bootstrap's private log. If update
fails, Software fails and bootstrap stops before package removals or installs;
warning plus retry action remain in private log and final checklist.

Logs do not intentionally include secrets or shell traces. Third-party installers
can print sensitive output: review logs before sharing them. Never put API keys
in the action checklist or Linear's `config.lua`.

Nothing in the run waits for a login. Tailscale and 1Password are installed but
left signed out. Commiter, Loom for Omarchy, and the Linear Omarchy plugin are
also installed through their unattended curl installers. Linear skips its
account-specific setup when no API key is already stored.

Bootstrap prints only pending follow-ups (including Zen first launch and SSH key
passphrases). Linear checks local config and keyring metadata without retrieving
secrets or opening an unlock prompt; unknown keyring state produces a verification
reminder. Presence checks do not validate token expiry or network access.

Common manual follow-ups:

```sh
sudo tailscale up --accept-routes   # or set TS_AUTHKEY=tskey-... before the run
~/.config/omarchy/plugins/andres.linear/bin/omarchy-linear-setup key
~/.config/omarchy/plugins/andres.linear/bin/omarchy-linear-setup check
~/.config/omarchy/plugins/andres.linear/bin/omarchy-linear-setup list
~/.config/omarchy/plugins/andres.linear/bin/omarchy-linear-setup use "Team" "Project"
```

Linear's `use` command writes `~/.config/omarchy/linear/config.lua`; the API key is
stored separately in the login keyring. For SSH keys, sign into the 1Password app,
enable **Settings → Developer → Integrate with 1Password CLI**, verify with
`op whoami`, then rerun `5 Keys.sh` using the path in the summary.
`BOOTSTRAP_KEYS=0` deliberately skips that step and its sign-in reminder.

## Scripts

| Script | Does |
|---|---|
| `1 SoftwareInstall.sh` | Packages plus personal tools: commiter everywhere; Loom and Linear plugin on Omarchy |
| `2 Fonts.sh` | Installs `fonts/` into the platform font dir |
| `3 Git.sh` | Git identity and defaults |
| `4 ConfigFiles.sh` | Copies every config below into `~`; idempotent, rerun any time. `--check` diffs instead of writing |
| `5 Keys.sh` | 1Password + SSH keys |
| `tests/smoke.sh` | Syntax/consistency checks, including bootstrap logging tests. Run before committing |
| `tests/bootstrap.sh` | Hermetic logging/failure/follow-up tests; no installs or real credentials |
| `tests/software-install.sh` | Hermetic Omarchy update-entrypoint/fail-stop regression test |

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
