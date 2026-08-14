// Silence the "make Zen your default browser" nag. Zen IS the default
// (xdg-settings check default-web-browser zen.desktop => yes), but its own check
// compares the http handler's Exec first token against /proc/self/exe. Our
// ~/.local/share/applications/zen.desktop starts with `env LD_LIBRARY_PATH=...`
// (needed: Zen wants libavcodec.so.62, system ffmpeg ships .63), so the compare
// sees `env` and reports "not default" on every launch. Dropping the env wrapper
// would mean exporting LD_LIBRARY_PATH session-wide, which is worse.
user_pref("browser.shell.checkDefaultBrowser", false);

// Enable custom browser chrome CSS (loads chrome/userChrome.css on restart).
user_pref("toolkit.legacyUserProfileCustomizations.stylesheets", true);

// Keep Compact Mode edge-hover enabled so the left sidebar still opens.
// The top toolbar hover is suppressed separately in chrome/userChrome.css.
user_pref("zen.view.compact.show-sidebar-and-toolbar-on-hover", true);

// Remove Linux/native window controls entirely in Zen.
user_pref("zen.view.experimental-no-window-controls", true);
user_pref("zen.view.hide-window-controls", true);

// macOS-like web content font defaults using free Linux substitutes.
// macOS: Times / Helvetica / Menlo. Linux substitutes: Nimbus Roman / Nimbus Sans / DejaVu Sans Mono.
user_pref("font.default.x-western", "serif");
user_pref("font.name.serif.x-western", "Nimbus Roman");
user_pref("font.name.sans-serif.x-western", "Nimbus Sans");
user_pref("font.name.monospace.x-western", "DejaVu Sans Mono");
user_pref("font.name.serif.x-unicode", "Nimbus Roman");
user_pref("font.name.sans-serif.x-unicode", "Nimbus Sans");
user_pref("font.name.monospace.x-unicode", "DejaVu Sans Mono");
