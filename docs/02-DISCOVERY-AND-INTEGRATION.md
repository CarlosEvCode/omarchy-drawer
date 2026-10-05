# Discovery, Integration & Execution Engine

## 1. Plugin Discovery Engine
`DrawerModel.js` scans installed plugins to populate the drawer items without hardcoding:

### 1.1 Discovery Sources
1. **Third-party Plugins**: `~/.config/omarchy/plugins/*/manifest.json`
2. **First-party Shell Plugins**: `/usr/share/omarchy/shell/plugins/*/manifest.json`
3. **Custom Desktop Launchers**: Registered `.desktop` files in `~/.local/share/applications/`

### 1.2 Plugin Metadata Resolution
For each discovered plugin, `DrawerModel.js` extracts:
- `id`: e.g. `tiertek.tekscan`, `io.github.nobledoodle.omarchroma`
- `name`: Human-readable display name
- `icon`: Resolves icon from manifest or Freedesktop icon theme
- `kind`: `bar-widget`, `panel`, `overlay`
- `ipcTarget`: Discovered IPC namespace (e.g. `tekscan`, `omarchroma`, `fathom`)

---

## 2. Invocation Mechanisms

When the user clicks an item inside the Drawer:

```
                      User Clicks Item in Drawer
                                  │
         ┌────────────────────────┼────────────────────────┐
         ▼                        ▼                        ▼
   [Kind: Panel]            [Kind: Overlay]          [Kind: App / CLI]
         │                        │                        │
         ▼                        ▼                        ▼
Open anchored popup      Trigger IPC command       Execute launcher
via shell PanelLoader    `omarchy-shell <target>`  via QsProcess
```

1. **Panel-based plugins** (e.g., TekScan, Omarchroma, Readout):
   - Triggers the plugin's panel popup directly via Quickshell IPC or opens the plugin's dedicated floating window.
2. **Overlay-based plugins** (e.g., Fathom, Emojis, Clipboard):
   - Invokes shell IPC trigger (`omarchy-shell fathom open`).
3. **App shortcuts**:
   - Launches command through `Process` or `xdg-open`.

---

## 3. Configuration & State Persistence

Stored in `~/.config/omarchy/shell.json` under `bar.layout` widget settings or `~/.config/omarchy/drawer.json`:

```json
{
  "id": "evcode.drawer",
  "trigger": "hover",
  "mode": "inline-drawer",
  "dimInactive": true,
  "items": [
    "tiertek.tekscan",
    "io.github.nobledoodle.omarchroma",
    "io.github.rsd.omavnc",
    "io.github.brukb.omarchy-zerotier",
    "io.github.ricky.whatsapp"
  ]
}
```
