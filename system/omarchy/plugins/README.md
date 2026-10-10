# Upstream clone baseline

`UPSTREAM.sha256` records the installed stock files reviewed against these
custom clones. It detects upstream changes; a mismatch alone does not prove
that a plugin is broken or that the laptop has modified package files.

Reviewed baseline: Omarchy stable `4.0.0.r1832.g23dab9e-1` (`basecamp/omarchy`,
commit `23dab9e`, Quattro), 2026-10-10. The clones were first written against
dev `4.0.0.r6720.g8e02fc8-1`; moving back to stable swapped `ShellIpc` for
`IpcHandler`, the menu's `OverlayWindow` for a per-open `PanelWindow`, and
dropped `Style.duration()`, none of which stable ships. Plugin-local behavior
from dev (duplicate toasts, image-tag stripping, in-process summons, plain-text
menu rows) stays: it needs nothing from the shell beyond guarded calls.

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
