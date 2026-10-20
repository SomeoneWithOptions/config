# Upstream clone baseline

`UPSTREAM.sha256` records the installed stock files reviewed against these
custom clones. It detects upstream changes; a mismatch alone does not prove
that a plugin is broken or that the laptop has modified package files.

Reviewed baseline: Omarchy stable `4.0.6-1` (`omarchy` package), 2026-10-20.
Earlier clones were written against dev `4.0.0.r6720.g8e02fc8-1`, then pinned
to `omarchy-dev 4.0.0.r1832.g23dab9e-1`. That pin broke under Qt 6.12, which
adds a built-in `QtQuick` `Color` singleton that shadows `qs.Commons.Color`
(every `Color.*` read returns `undefined`). Stock 4.0.6 imports
`qs.Commons as Commons` and reads `Commons.Color.*`; the clones and the framed
panel generator do the same. Never write a bare `Color.` in shell QML.

The 4.0.6 port also brings in idle timeouts of `0` disabling that action,
plain-text tray rows, and, for `andres.desktop-frame`, reads bar transparency
from `shell.barConfig` because third-party plugins now get a scalar bar facade
without `transparent`. Stock 4.0.6 dropped menu `disabled:` rows; the clone
keeps them.

This review ports disabled menu rows, in-process menu summons, persistent menu
surfaces, notification hotkey dispatch, duplicate-toast handling, shell socket
IPC registration, and the tray's reduced-motion duration. Custom frame geometry,
menu entrance/exit animation, app-library fallback, audio-aware idle handling,
and Loom recording cards remain in the clones. Duplicate detection also compares
Loom recording metadata so separate recordings are never collapsed together.

The DND bar widget belongs to `andres.notifications`, alongside its service.
Omarchy's scoped plugin API only exposes a plugin's own service; a separate
`andres.dnd` widget cannot read the notification service and stays hidden.

The custom notification card has no stock close-button opacity animation, so
the upstream `Style.duration(100)` change does not apply to that component.

When smoke reports checksum drift:

1. Check installed package integrity with `pacman -Qkk omarchy-dev` (or `omarchy`
   for the stable package).
2. Compare changed stock files with their reviewed baseline and the clones.
   Port behavior/API fixes while retaining intentional visual changes.
3. Run `node tests/omarchy-plugins.mjs` and `bash tests/smoke.sh`.
4. Update only reviewed hashes. Keep the checksum check strict: it found a real
   missing `runShortcut()` method after upstream moved notification hotkeys
   into the shell.

Smoke constructs a temporary `qs/` import tree for QML linting. Import errors
fail; nonfatal warnings are counted. Use `SMOKE_VERBOSE=1 bash tests/smoke.sh`
to see all QML diagnostics.

With a running Wayland session, smoke also compiles the clones with Quickshell's
real types. That check never instantiates plugin objects or their services.
