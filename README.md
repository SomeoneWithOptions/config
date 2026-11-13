# config

Dotfiles and machine setup for **Omarchy** (Arch) and **macOS**.

```sh
curl -fsSL https://go.sanetomore.com/config | sh
```

Linux desktop baseline: **Omarchy 4.5.0-3**. Custom shell clones retain the
framed desktop, workspace pills and Loom cards while following 4.5's notification,
menu and IPC behavior. Workspaces stay global 1-10 across monitors: 4.5's
per-monitor blocks renumbered workspaces on lid close/undock, so
`system/hypr/workspaces.lua` disables them and `andres.workspaces` pins block 0. See
[plugin maintenance](system/omarchy/plugins/README.md) before refreshing upstream hashes.

Laptop setup also restores:

- Battery charge thresholds: start 85%, stop 90%, only on supported batteries.
  Installs a persistent udev rule; verify thresholds after reboot.
- Superwhisper dictation (Omarchy's `superwhisper-bin`): offline mode (Cohere
  Transcribe + S1 Mini, about 2.2 GB of models), English, semi-formal tone,
  auto-paste. Software setup installs it, enables its user service, downloads the
  offline models and selects it as the Omarchy dictation backend.
  `4 ConfigFiles.sh` applies `apps/superwhisper/settings` through the
  `superwhisper` CLI; the microphone stays per machine. Shortcuts: **Super+Ctrl+X**
  (Omarchy) and **Right Ctrl** (Superwhisper toggle).
- Solitude overlay with Catppuccin Mocha terminal colors; Bluetooth headset mic
  auto-connect; balanced power on AC and power-saver on battery.
- OpenCode preferences, shared Pi skill paths, caveman instructions and an
  `opencode-op` / Fish wrapper. `keys.env` contains 1Password references only;
  sign into the 1Password CLI on each machine. Existing injected keys are reused.
  Fresh OpenCode seed retains this laptop's allow-all permissions using the
  current [OpenCode configuration schema](https://opencode.ai/docs/config); no service
  password or Herdr integration is copied.
- `claude-api`: separate API-billed Claude configuration, resolving its key
  through 1Password (or an existing `T3CODE_ANTHROPIC_API_KEY`). Subscription
  command remains `claude`.
- Zen's temporary FFmpeg 8 codec workaround. The launcher isolates libraries
  under `~/.local/lib/ffmpeg-firefox`; system FFmpeg stays managed by Arch.
  Software setup extracts only needed libraries from signature-verified
  [Arch archive](https://archive.archlinux.org/) packages `ffmpeg 2:8.1.2-11`
  and `x265 4.2-2` on x86_64. Existing working bundles are kept. Dependency and
  H.264-decoder loading are checked; browser playback is not exercised by setup.
  Set `CONFIG_ZEN_MEDIA=0` to skip provisioning. Reassess this workaround when
  Zen supports the system FFmpeg ABI.

Run `1 SoftwareInstall.sh` before `4 ConfigFiles.sh` on fresh machines. Config
replay installs files/settings; it may need sudo for the battery udev rule.
Agent preferences are seeded only, preserving choices later made inside apps.
No credentials, models or shared-library binaries belong in git.

```sh
bash '4 ConfigFiles.sh' --check        # managed files, battery, power, dictation, Zen
bash '4 ConfigFiles.sh' --check-seeds  # also flag changed seeds; omit their values
bash tests/smoke.sh                   # isolated installers + plugin compatibility
```

Both check modes leave configuration unchanged. `--check-seeds` reports seed
differences without printing local secrets or overwriting app preferences.
Live laptop files are not updated merely by changing this repository.

Pi web-research keys live in separate 1Password `development` items: `Exa <> API Key`
(`EXA_API_KEY`), `Firecrawl <> API Key` (`FIRECRAWL_API_KEY`), and `Brave <> Search API Key`
(`BRAVE_SEARCH_API_KEY`, optional `BRAVE_AI_API_KEY`). Each service loads/caches its
own item for five minutes. Item IDs survive renames. Override account/vault with
`WEB_RESEARCH_OP_ACCOUNT` / `WEB_RESEARCH_OP_VAULT`; override individual item IDs
with `WEB_RESEARCH_OP_EXA_ITEM`, `WEB_RESEARCH_OP_FIRECRAWL_ITEM`, or
`WEB_RESEARCH_OP_BRAVE_ITEM` (replaces shared `WEB_RESEARCH_OP_ITEM`).
