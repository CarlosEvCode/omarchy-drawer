# Drawer & Quick-Launch Dock for Omarchy (`evcode.drawer`)

A native status bar widget and collapsible popout dock for the [Omarchy](https://omarchy.org/) desktop shell. It consolidates secondary status bar widgets into a unified, minimal tray with on-demand expansion, drag-and-drop reordering, interactive widget hosting, and a persistent ultra-minimalist mode.

![Omarchy Drawer Preview](preview.png)

---

## Features

- **Top Bar Decluttering**:
  Group any number of secondary widgets (ZeroTier, TekScan, Omarchroma, OmaVNC, WhatsApp, Tailscale, Hotspot, etc.) into a single compact bar icon, freeing up valuable space on your status bar.

- **Interactive Native Widget Hosting**:
  Embeds live plugin components directly into drawer tiles while maintaining their popout lifecycle, active badges, and status indicators.

- **Direct In-Drawer Add Mode (`+`)**:
  Move widgets from your top bar into the Drawer with a single click directly inside the panel, without editing configuration files manually.

- **Visual Drag & Drop Reordering (`✕`)**:
  Freely drag and drop tiles within the grid to customize your layout. The order is automatically saved and synchronized to `~/.config/omarchy/drawer.json`.

- **Collapsible Minimalist Mode (`▲` / `▼`)**:
  Toggle between full controls and a clean, icon-only grid. Your header preference is persistently saved across sessions and system reboots.

- **Zero Startup Overhead (0ms Boot)**:
  Uses native Quickshell `FileView` for asynchronous configuration monitoring with zero subprocess forks on boot, ensuring instant shell startup.

- **Popout & Focus Coordination**:
  Seamlessly manages layer-shell focus and sub-popout dismissal (`suspendDismiss`), allowing child plugins to open their own menus smoothly without prematurely closing the drawer.

- **Omarchy Theme Integration**:
  Naturally inherits Omarchy colors, borders, font tokens, and hover states (`Style`, `Color`, `Border`) for seamless aesthetic harmony.

---

## Installation

### Standard Installation (Single Command)

Install and enable Omarchy Drawer instantly with zero extra setup:

```bash
omarchy plugin add https://github.com/CarlosEvCode/omarchy-drawer.git --enable
omarchy restart shell
```

### Optional: Global CLI Helper (`omarchy-drawer`)

If you want to control the drawer from terminal scripts, IPC or custom keybindings via the `omarchy-drawer` command, you can optionally run the installer to link the binary to `~/.local/bin`:

```bash
cd ~/.config/omarchy/plugins/evcode.drawer
chmod +x install.sh
./install.sh
```

### Uninstallation

To disable or remove the plugin:

```bash
omarchy plugin disable evcode.drawer
# Or run ./install.sh --uninstall to also clean up CLI symlinks
```

---

## Controls and Keybindings

| Action | Control |
|---|---|
| **Open / Close Drawer** | Left Click on bar widget |
| **Toggle Minimalist Mode** | Click `▲` (collapse) or `▼` (expand) in header |
| **Enter Add Mode** | Click `+` button in header |
| **Enter Edit / Reorder Mode** | Click `Edit` button in header |
| **Reorder Plugins** | Drag & drop any tile while in Edit mode |
| **Remove Plugin from Drawer** | Click `✕` badge on any tile in Edit mode |
| **Launch / Open Plugin** | Click any plugin tile |
| **Dismiss Panel** | Press `Esc` or click outside |

---

## CLI Helper Reference

The drawer can be controlled from scripts, keybindings, or the terminal via `omarchy-drawer`:

```bash
# Toggle drawer panel open / closed
omarchy-drawer toggle

# Open / close the drawer panel explicitly
omarchy-drawer open
omarchy-drawer close

# Launch or toggle a specific plugin directly
omarchy-drawer toggle <plugin_id>
omarchy-drawer launch <plugin_id>
# Example: omarchy-drawer toggle tiertek.tekscan

# List all plugins currently inside the drawer (JSON)
omarchy-drawer list

# List all widgets currently visible on the top bar (JSON)
omarchy-drawer bar-items

# Move a widget from the top bar into the drawer
omarchy-drawer add <plugin_id>

# Remove a widget from the drawer and restore it to the top bar
omarchy-drawer remove <plugin_id>
```

---

## Configuration

Drawer state is persisted in `~/.config/omarchy/drawer.json`:

```json
{
  "id": "evcode.drawer",
  "items": [
    "io.github.brukb.omarchy-zerotier",
    "io.github.nobledoodle.omarchroma",
    "omarchy.tailscale",
    "tiertek.tekscan",
    "io.github.rsd.omavnc"
  ],
  "headerCollapsed": false
}
```

---

## License

[MIT](LICENSE) © 2026 evcode
