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
curl -fsSL https://go.sanetomore.com/config | sh
```

`https://go.sanetomore.com/config` is a permanent redirect to `bootstrap.sh` in
this repo. The direct URL
`https://raw.githubusercontent.com/SomeoneWithOptions/config/main/bootstrap.sh`
is the redirect target and a fallback. `bootstrap.sh` must keep its name and
stay at the repo root because the published redirect points at that exact path.
It downloads this repo to /tmp and runs the numbered scripts in order. On Arch,
`4 ConfigFiles.sh` also clones the repo to `~/code/config` for the post-update
drift check.

### Progress and logs

Bootstrap shows stage progress and elapsed time instead of package-manager and
file-copy output. Long stages report that they are still running every 30 seconds.
During the Software stage the view goes app-by-app: each operation reports
itself as it runs (`→ Installing Zen browser…`) and its pending line becomes
the result once finished (`✓ Zen browser installed`, `– Zed already installed`,
`! Zen browser installation failed`), keeping completed rows above. The current
operation's elapsed time replaces the generic stage heartbeat (every 30 s:
`  … Installing Zen browser… (30s)`). On capable terminals the active line is
rewritten in place; non-TTY and `TERM=dumb` output stays newline-only without
cursor escapes, and `NO_COLOR=1` disables color. Nothing else in the UI parses
installer output: the renderer reads only explicit progress records written to
a private events file, while raw command output remains in the detailed log.
With `BOOTSTRAP_VERBOSE=1` the streamed transcript already carries those
readable records, so no duplicate progress rows are printed. Installers whose
real script does more than add packages keep running when the app is already
installed — `omarchy install service 1password` also wires the Chromium
extension policy and re-opens the app, and `omarchy install browser zen` also
installs the Firefox policy distribution and the Wayland environment file — so
those runs are reported as configuration (`→ Configuring 1Password…` →
`✓ 1Password configured`) instead of a skip. On Omarchy,
`omarchy toggle idle stay-awake` runs before software installation to
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
curl -fsSL https://go.sanetomore.com/config | BOOTSTRAP_VERBOSE=1 sh
```

Same short URL as above; the equivalent direct URL is
`https://raw.githubusercontent.com/SomeoneWithOptions/config/main/bootstrap.sh`.

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
| `bootstrap.sh` | Stage driver: downloads the repo and runs 1..5 |
| `1 SoftwareInstall.sh` | Entrypoint for software install: sources `scripts/lib/` and `scripts/install/` modules, switches on platform, prints the summary |
| `2 Fonts.sh` | Installs `theme/fonts/` into the platform font dir |
| `3 Git.sh` | Git identity and defaults |
| `4 ConfigFiles.sh` | Entrypoint for the config replay: parses `--check`, sources the `scripts/apply/` modules in order, prints the drift total |
| `5 Keys.sh` | 1Password + SSH keys |
| `tests/smoke.sh` | Syntax/consistency checks, including bootstrap logging tests. Run before committing |
| `tests/bootstrap.sh` | Hermetic logging/failure/follow-up tests; no installs or real credentials |
| `tests/software-install.sh` | Hermetic Omarchy/macOS update-entrypoint, app progress events, and fail-stop regression tests |

Sourced modules (pulled in by the numbered drivers; never executed on their own):

| Module | Does |
|---|---|
| `scripts/lib/report.sh` | Reporting, action, and progress records |
| `scripts/lib/common.sh` | `log` `warn` `note` `run_or_warn` `has_command` `progress_step` |
| `scripts/lib/copy.sh` | CHECK-aware fs ops: `report_drift` `copy_required` `copy_required_if_missing` `copy_executable_required` `copy_dir_required` `append_line_once` `link_agent_skill` |
| `scripts/lib/pkg.sh` | `pacman_*` `arch_install_if_missing` `ensure_homebrew` `brew_*` |
| `scripts/install/tools.sh` | Vendor installers: pi, commiter, loom, linear, npm CLIs, turso, rtk |
| `scripts/install/arch.sh` | Arch/Omarchy: system update, stock-app removal, package list, dev-envs, zed, zen, tailscale, 1password |
| `scripts/install/macos.sh` | Homebrew formulae/casks, node@24, quarantine strip |
| `scripts/apply/dotfiles.sh` | Every managed file copy (both platforms) |
| `scripts/apply/generated.sh` | Framed Omarchy panels: generate/compare + shell restart |
| `scripts/apply/settings.sh` | Live machine state: login shell, hyprctl reload, default browser, omarchy theme, user systemd timer |
| `scripts/apply/migrations.sh` | Retired hook + retired timer removal, `~/code/config` clone |

## Layout

Numbered scripts `1` and `4` are thin drivers. Shared helpers live in
`scripts/lib/`, platform and vendor installers in `scripts/install/`, and the
config replay body in `scripts/apply/` (was a top-level `config` dir: nineteen sibling
dirs are application config, and the name collided). Those files are sourced,
never executed: no shebang, mode 644, pulled in by a numbered driver.
`scripts/install/*.sh` only defines functions; `scripts/apply/*.sh` runs its
statements at source time, which is what the config replay has always done.

The tree groups by domain, not platform. `apps/aerospace/` is macOS-only and
`system/` is Linux/Omarchy-only in practice; those notes stay in the prose, not
the directory names. `bin/` stays at the root: its eight files span desktop and
shell, and the name mirrors the `~/.local/bin` destination. `theme/` absorbed
fonts even though `2 Fonts.sh` installs that tree rather than the config replay
— grouping is by what a thing is, not by which script reads it.

```
.
├── 1 SoftwareInstall.sh  2 Fonts.sh  3 Git.sh  4 ConfigFiles.sh  5 Keys.sh
├── bootstrap.sh   README.md
├── scripts/     lib/  install/  apply/
├── system/      omarchy/ hypr/ quickshell/ systemd/ xdg/
├── apps/        alacritty/ foot/ ghostty/ zed/ zen/ herdr/ aerospace/
├── shell/       fish/ git/
├── agents/      pi/ skills/
├── theme/       fonts/ fontconfig/ gtk-3.0/ gtk-4.0/
├── bin/
└── tests/
```

- `scripts/` — sourced modules for the numbered drivers (never executed directly)
- `system/` — Omarchy/Arch only
  - `system/hypr/` — Hyprland Lua config (`*.lua`) plus `xdph.conf` for screen sharing
  - `system/omarchy/plugins/andres.*` — Quattro shell plugins (bar widgets, frame,
    menu, notifications, idle, dnd); `andres.tray` gives every application tray
    menu the same attached, outward-curved frame used by built-in panels.
    `andres.idle` and `andres.dnd` are status-only icons: each shows solely while
    its non-default state is on (staying awake, notifications silenced)
  - `system/omarchy/install-framed-panels.py` — generates `andres.{audio,bluetooth,clock,monitor,network,power,tailscale}`
    by cloning the stock panels and attaching them to the desktop frame. Generated,
    so those seven are not tracked here
  - `system/omarchy/shell.json` / `shell.toml` — bar layout and machine-level theme overrides
  - `system/omarchy/hooks/` — post-update drift report (`~/.local/state/omarchy/config-drift.diff`) and Zed theme sync
  - `system/quickshell/flicko-picker/` — animated screenshot region picker; the
    optional `color` file there pins its accent to a fixed hex, otherwise it
    follows the theme
  - `system/systemd/user/` — mise Go upgrades and random-background timers
  - `system/xdg/` — default-app associations
- `apps/` — application config. Shared by both platforms unless noted:
  `apps/alacritty/`, `apps/foot/`, `apps/ghostty/`, `apps/zed/`, `apps/herdr/`;
  `apps/aerospace/` is macOS only (tiling window manager); `apps/zen/` is
  Omarchy/Arch only (browser prefs)
- `shell/` — shared: `shell/fish/`, `shell/git/`
- `agents/pi/agent/` — pi agent extensions and skills (shared)
- `agents/skills/` — shared skills (`herdr`, `orchestrator`) copied to
  `~/.agents/skills` and symlinked into pi and Claude Code
- `theme/` — shared: `theme/fonts/` (installed by `2 Fonts.sh`), `theme/fontconfig/`,
  `theme/gtk-3.0/`, `theme/gtk-4.0/`
- `bin/ghui`, `bin/hunk` — helpers installed to `~/.local/bin` everywhere; the
  rest of `bin/` are Hyprland/Omarchy helpers
- `tests/` — syntax and hermetic bootstrap checks

Waybar, Walker, SwayOSD, mako, hypridle and hyprlock are gone: Quattro's
`omarchy-shell` replaces all of them.
