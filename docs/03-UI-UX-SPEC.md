# UI, Animations & Interaction Specification

## 1. Visual Aesthetics & Styling Tokens

Omarchy Drawer follows Omarchy Quattro's strict design principles:
- **Zero Hardcoded Colors**: Uses `Style.bar.iconSlot`, `Color.foreground`, `Color.background`, and `Color.accent`.
- **Subtle Resting State**: Inactive icons render with `opacity: 0.45` and monochrome/symbolic tinting, instantly lighting up to `opacity: 1.0` with glowing accent backgrounds on hover.
- **Smooth Easing**: Expander slide animation uses `Easing.OutCubic` over `280ms`.

---

## 2. Layouts

### 2.1 Inline Expanding Bar Drawer
```text
[Collapsed State]
... [Audio] [Display] [ ‹ ] [Power]

[Hover / Expanded State]
... [Audio] [Display] [ ‹ | 📡 TekScan | 🎨 Chroma | 🌐 ZeroTier | 💬 WhatsApp ] [Power]
```

- When the mouse rests over the chevron/expander `‹`, the drawer smoothly expands its width to the left (if placed on the right section) or to the right (if on the left section).
- Clicking any child item executes its action and gently collapses the drawer unless pinned open.

### 2.2 Popover Mini-Dock Mode
```text
┌────────────────────────────────────────────────────────┐
│  ❖ Drawer — 5 Quick Plugins                [⚙ Manage]  │
├────────────────────────────────────────────────────────┤
│  [1] 📡 TekScan       — Network & IP Scanner           │
│  [2] 🎨 Omarchroma    — Palette Sync                   │
│  [3] 🌐 ZeroTier      — Virtual Mesh Network           │
│  [4] 🖥️ omaVNC        — Remote Screen Passthrough      │
│  [5] 💬 WhatsApp      — Messaging Webview              │
└────────────────────────────────────────────────────────┘
```

---

## 3. Right-Click Manage Menu (`ManagePopup.qml`)

Right-clicking the Drawer expander opens a fast checkbox selector:
- Lists all discovered plugins in the system.
- Checkbox to toggle inclusion in the drawer.
- Up/Down buttons to reorder positions.
- Switch between `Hover` vs `Click` trigger mode.
- Switch between `Inline bar drawer` vs `Popover dock`.
