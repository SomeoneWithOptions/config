# Upstream clone baseline

Reviewed against Omarchy stable **4.5.0-3**, 2026-11-06. `UPSTREAM.sha256`
pins the stock files reviewed for these clones. A mismatch calls for review;
it does not by itself mean a clone is broken.

The 4.5 port retains framed panels and menu animations, all-visible tray icons,
workspace pills with app icons, audio-aware idle handling and the Matrix
screensaver. It adds the current menu's translations, IME input, multi-select
flow and concurrent guards; the tray's widget section; workspace layout state
(navigation stays global 1-10, see `system/hypr/workspaces.lua`); and shell-socket IPC registration via `ShellIpc`.

Notifications now use the 4.5 keyed scene, persistence, grouping, markup and
keyboard/action engine. The black drawer and curved joins remain. `Loom.js`,
`Store.js`, `Toast.qml` and the service preserve recording metadata, Play/Upload/
Delete cards, persistent recording lifetime and separate recording groups.
Repeated standard toasts collapse; recordings with different paths or different
actions do not. Recording actions use positional arguments, not interpolated
shell commands. Stock notifications and menu services remain disabled while
these clones run.

The notification clone vendors its Loom card. Config replay must not run the
external Loom overlay helper over this different 4.5 implementation. The DND
widget stays in the service's own plugin because scoped APIs only expose the
plugin's own service.

Use `qs.Commons as Commons` for `Commons.Color.*`: Qt 6.12's `QtQuick.Color`
otherwise shadows the theme singleton.

After upstream changes:

1. Check installed package integrity with `pacman -Qkk omarchy`.
2. Review changed stock files against the old reviewed baseline and these clones.
3. Port applicable behavior/API changes while preserving intentional styling.
4. Run `node tests/omarchy-plugins.mjs` and `bash tests/smoke.sh`.
5. Update hashes only for reviewed sources, including new notification modules.

Smoke lints QML and, with a running Wayland session, compiles components against
real Quickshell types without instantiating services or windows. It does not
restart the live shell. Use `SMOKE_VERBOSE=1` for full lint diagnostics.
