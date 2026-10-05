.pragma library

// DrawerModel.js - Core logic for Omarchy Drawer (evcode.drawer)
// Handles discovery of plugins, state persistence, configuration, and invocation.

var DEFAULT_CONFIG = {
  trigger: "hover", // "hover" | "click"
  mode: "inline-drawer", // "inline-drawer" | "popover-dock"
  animationDuration: 280,
  dimInactive: true,
  items: [
    "tiertek.tekscan",
    "io.github.nobledoodle.omarchroma",
    "io.github.rsd.omavnc",
    "io.github.brukb.omarchy-zerotier",
    "io.github.ricky.whatsapp"
  ]
};

var KNOWN_PLUGINS_MAP = {
  "tiertek.tekscan": {
    id: "tiertek.tekscan",
    name: "TekScan",
    icon: "\uf0ec",
    description: "LAN & IP Scanner",
    ipcTarget: "tiertek.tekscan",
    category: "System"
  },
  "io.github.nobledoodle.omarchroma": {
    id: "io.github.nobledoodle.omarchroma",
    name: "Omarchroma",
    icon: "\udb80\udfd8",
    description: "Force theme synchronization",
    ipcTarget: "io.github.nobledoodle.omarchroma",
    category: "Appearance"
  },
  "io.github.rsd.omavnc": {
    id: "io.github.rsd.omavnc",
    name: "omaVNC",
    icon: "\uf108",
    description: "Remote display & VNC passthrough",
    ipcTarget: "io.github.rsd.omavnc",
    category: "Network"
  },
  "io.github.brukb.omarchy-zerotier": {
    id: "io.github.brukb.omarchy-zerotier",
    name: "ZeroTier",
    icon: "\uf0ac",
    description: "Virtual Mesh Network",
    ipcTarget: "io.github.brukb.omarchy-zerotier",
    category: "Network"
  },
  "io.github.ricky.whatsapp": {
    id: "io.github.ricky.whatsapp",
    name: "WhatsApp",
    icon: "\uf232",
    description: "WhatsApp Web quick client",
    ipcTarget: "io.github.ricky.whatsapp",
    category: "Communication"
  },
  "io.github.sudoapwh.readout": {
    id: "io.github.sudoapwh.readout",
    name: "Readout",
    icon: "\uf2db",
    description: "System & hardware telemetry",
    ipcTarget: "readout",
    category: "System"
  },
  "omarchy.agents": {
    id: "omarchy.agents",
    name: "Agents",
    icon: "\uf544",
    description: "AI Model usage & rate limits",
    ipcTarget: "agents",
    category: "AI"
  },
  "omarchy.media": {
    id: "omarchy.media",
    name: "Media",
    icon: "\uf001",
    description: "Media player controls",
    ipcTarget: "media",
    category: "Media"
  },
  "io.github.mtolhuys.fathom": {
    id: "io.github.mtolhuys.fathom",
    name: "Fathom",
    icon: "\uf002",
    description: "App launcher & search",
    ipcTarget: "fathom",
    category: "Navigation"
  },
  "io.github.aryan-techie.bluetooth": {
    id: "io.github.aryan-techie.bluetooth",
    name: "Bluetooth",
    icon: "\uf293",
    description: "Bluetooth device manager",
    ipcTarget: "bluetooth",
    category: "Hardware"
  },
  "io.github.deunnis.lacquer": {
    id: "io.github.deunnis.lacquer",
    name: "Lacquer",
    icon: "\uf53f",
    description: "Theme customizer",
    ipcTarget: "lacquer",
    category: "Appearance"
  },
  "evcode.hotspot": {
    id: "evcode.hotspot",
    name: "Hotspot",
    icon: "\uf1eb",
    description: "Wi-Fi Hotspot controls",
    ipcTarget: "hotspot",
    category: "Network"
  },
  "evcode.network": {
    id: "evcode.network",
    name: "Network",
    icon: "\uf1eb",
    description: "Network configuration",
    ipcTarget: "network",
    category: "Network"
  }
};

function parseJsonSafe(jsonStr, fallback) {
  if (!jsonStr || typeof jsonStr !== "string") return fallback;
  try {
    return JSON.parse(jsonStr);
  } catch (e) {
    return fallback;
  }
}

function resolveItemMetadata(pluginId, manifest) {
  var known = KNOWN_PLUGINS_MAP[pluginId] || {};
  var name = (manifest && (manifest.name || (manifest.barWidget && manifest.barWidget.displayName))) || known.name || pluginId;
  var description = (manifest && (manifest.description || (manifest.barWidget && manifest.barWidget.description))) || known.description || "";
  var icon = (manifest && manifest.icon) || known.icon || "\uf013";
  var ipcTarget = known.ipcTarget || pluginId;
  var category = (manifest && manifest.barWidget && manifest.barWidget.category) || known.category || "Utility";

  return {
    id: pluginId,
    name: name,
    description: description,
    icon: icon,
    ipcTarget: ipcTarget,
    category: category,
    manifest: manifest || null
  };
}

function getActiveItemList(itemIds, discoveredMap) {
  var list = [];
  var ids = itemIds || DEFAULT_CONFIG.items;
  for (var i = 0; i < ids.length; i++) {
    var id = ids[i];
    var meta = (discoveredMap && discoveredMap[id]) ? discoveredMap[id] : resolveItemMetadata(id, null);
    list.push(meta);
  }
  return list;
}
