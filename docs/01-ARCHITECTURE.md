# Omarchy Drawer — System Architecture & Specification

## 1. Overview
**Omarchy Drawer** (`evcode.drawer`) is a native shell plugin for Omarchy Quattro that solves the "bar saturation" problem.

Instead of displaying 10–15 individual plugin icons directly across the top bar, **Omarchy Drawer** groups secondary and utility plugins into an animated, collapsible drawer / floating mini-dock that reveals on **hover** or **click**.

---

## 2. Architectural Pillars

```
┌────────────────────────────────────────────────────────────────────────┐
│                        OMARCHY BAR SURFACE                             │
│                                                                        │
│  [ Menu ] [ Workspaces ] ─── [ Clock ] ─── [ Tray ] [ ❖ Drawer ] [ Power]
│                                                          │             │
│                                           (Hover / Click)              │
│                                                          ▼             │
│                                           ┌──────────────────────────┐ │
│                                           │  Animated Drawer / Dock  │ │
│                                           │  [TekScan] [Chroma]      │ │
│                                           │  [ZeroTier] [VNC] [Apps] │ │
│                                           └──────────────────────────┘ │
└────────────────────────────────────────────────────────────────────────┘
```

### 2.1 Interaction Modes
1. **`inline-drawer` (Default / Waybar Style)**:
   - Resides directly on the bar next to other widgets.
   - Closed: Shows an elegant expander glyph (`‹`, `…` or `❖`).
   - Open (on Hover/Click): Slides open horizontally along the bar, revealing child plugin icons with smooth CSS/QML cubic-bezier easing.
2. **`popover-dock`**:
   - Opens an anchored floating pill/dock below the bar with quick-launch icons, tooltips, and keyboard navigation (`1..9` quick keys).

---

## 3. Plugin File Structure

```text
/home/evcode/Proyectos/omarchy-drawer/
├── manifest.json              # Official Omarchy Quattro plugin manifest
├── BarWidget.qml              # Main bar entry point (expander + inline drawer)
├── Panel.qml                  # Popover / Mini-dock surface entry point
├── DrawerModel.js             # Discovery, state tracking, and plugin invocation engine
├── ManagePopup.qml            # Right-click GUI for picking items in the drawer
├── ui/
│   ├── DrawerItem.qml         # Individual icon button with dimmed/active states
│   └── ExpanderGlyph.qml      # Animated chevron / grid icon
├── bin/
│   └── omarchy-drawer         # CLI interface for shell IPC controls
├── docs/                      # Technical specifications & design references
├── preview.png                # Marketplace showcase banner
└── README.md                  # User guide and quickstart
```

---

## 4. Omarchy Quattro Plugin Contract

Following `https://plugins.omarchy.org/develop.html`:
- **Kinds**: `["bar-widget", "panel"]`
- **Entry Points**:
  - `barWidget`: `"BarWidget.qml"`
  - `panel`: `"Panel.qml"`
- **IPC Support**: Exposes `omarchy-shell drawer toggle|open|close|add <id>|remove <id>`
- **Styling**: Inherits Omarchy's `Style.qml`, `Color.qml`, and `Style.cornerRadius` live theme tokens with zero hardcoded palette values.
