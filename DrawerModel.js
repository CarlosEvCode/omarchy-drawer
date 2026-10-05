.pragma library

// DrawerModel.js - Core metadata & discovery logic for Omarchy Drawer

var KNOWN_PLUGINS_MAP = {
  "evcode.hotspot": {
    id: "evcode.hotspot",
    name: "Hotspot & Repeater",
    icon: "󱛄",
    entryPoint: "Panel.qml",
    ipcTarget: "evcode.hotspot"
  },
  "evcode.network": {
    id: "evcode.network",
    name: "Network",
    icon: "󰤨",
    entryPoint: "Panel.qml",
    ipcTarget: "evcode.network"
  },
  "tiertek.tekscan": {
    id: "tiertek.tekscan",
    name: "TekScan",
    icon: "",
    entryPoint: "BarWidget.qml",
    ipcTarget: "tekscan"
  },
  "io.github.nobledoodle.omarchroma": {
    id: "io.github.nobledoodle.omarchroma",
    name: "Omarchroma",
    icon: "\udb80\udfd8",
    entryPoint: "BarWidget.qml",
    ipcTarget: "io.github.nobledoodle.omarchroma"
  },
  "io.github.rsd.omavnc": {
    id: "io.github.rsd.omavnc",
    name: "omaVNC",
    icon: "󰍹",
    entryPoint: "BarWidget.qml",
    ipcTarget: "io.github.rsd.omavnc"
  },
  "io.github.brukb.omarchy-zerotier": {
    id: "io.github.brukb.omarchy-zerotier",
    name: "ZeroTier",
    icon: "󰲝",
    entryPoint: "BarWidget.qml",
    ipcTarget: "io.github.brukb.omarchy-zerotier"
  },
  "io.github.ricky.whatsapp": {
    id: "io.github.ricky.whatsapp",
    name: "WhatsApp",
    icon: "\uf232",
    entryPoint: "BarWidget.qml",
    ipcTarget: "io.github.ricky.whatsapp"
  },
  "io.github.sudoapwh.readout": {
    id: "io.github.sudoapwh.readout",
    name: "Readout",
    icon: "󰘚",
    entryPoint: "Panel.qml",
    ipcTarget: "readout"
  },
  "omarchy.agents": {
    id: "omarchy.agents",
    name: "Agents",
    icon: "󰚩",
    entryPoint: "Panel.qml",
    ipcTarget: "agents"
  },
  "omarchy.media": {
    id: "omarchy.media",
    name: "Media",
    icon: "\uf001",
    entryPoint: "BarWidget.qml",
    ipcTarget: "media"
  },
  "ajkulundu.mediaplusplus": {
    id: "ajkulundu.mediaplusplus",
    name: "Media++",
    icon: "\uf001",
    entryPoint: "BarWidget.qml",
    ipcTarget: "mediaplusplus"
  },
  "io.github.mtolhuys.fathom": {
    id: "io.github.mtolhuys.fathom",
    name: "Fathom",
    icon: "\uf002",
    entryPoint: "BarWidget.qml",
    ipcTarget: "fathom"
  },
  "io.github.aryan-techie.bluetooth": {
    id: "io.github.aryan-techie.bluetooth",
    name: "Bluetooth",
    icon: "\uf293",
    entryPoint: "Panel.qml",
    ipcTarget: "bluetooth"
  },
  "io.github.deunnis.lacquer": {
    id: "io.github.deunnis.lacquer",
    name: "Lacquer",
    icon: "\uf53f",
    entryPoint: "Panel.qml",
    ipcTarget: "lacquer"
  },
  "omarchy.audio": {
    id: "omarchy.audio",
    name: "Audio",
    icon: "\uf028",
    entryPoint: "Panel.qml",
    ipcTarget: "audio"
  },
  "omarchy.monitor": {
    id: "omarchy.monitor",
    name: "Display",
    icon: "\uf108",
    entryPoint: "Panel.qml",
    ipcTarget: "monitor"
  },
  "omarchy.power": {
    id: "omarchy.power",
    name: "Power",
    icon: "\uf011",
    entryPoint: "Panel.qml",
    ipcTarget: "power"
  },
  "omarchy.tailscale": {
    id: "omarchy.tailscale",
    name: "Tailscale",
    icon: "󰖂",
    entryPoint: "Panel.qml",
    ipcTarget: "tailscale"
  },
  "omarchy.tray": {
    id: "omarchy.tray",
    name: "System Tray",
    icon: "\uf078",
    entryPoint: "BarWidget.qml",
    ipcTarget: "tray"
  },
  "omarchy.system-update": {
    id: "omarchy.system-update",
    name: "System Update",
    icon: "\uf021",
    entryPoint: "BarWidget.qml",
    ipcTarget: "system-update"
  },
  "omarchy.indicators": {
    id: "omarchy.indicators",
    name: "Indicators",
    icon: "\uf0eb",
    entryPoint: "BarWidget.qml",
    ipcTarget: "indicators"
  },
  "omarchy.keyboard-layout": {
    id: "omarchy.keyboard-layout",
    name: "Keyboard",
    icon: "\uf11c",
    entryPoint: "BarWidget.qml",
    ipcTarget: "keyboard-layout"
  },
  "omarchy.clock": {
    id: "omarchy.clock",
    name: "Clock",
    icon: "\uf017",
    entryPoint: "Panel.qml",
    ipcTarget: "clock"
  },
  "omarchy.active-window": {
    id: "omarchy.active-window",
    name: "Active Window",
    icon: "\uf2d0",
    entryPoint: "BarWidget.qml",
    ipcTarget: "active-window"
  },
  "omarchy.workspaces": {
    id: "omarchy.workspaces",
    name: "Workspaces",
    icon: "\uf108",
    entryPoint: "BarWidget.qml",
    ipcTarget: "workspaces"
  },
  "omarchy.menu": {
    id: "omarchy.menu",
    name: "Menu",
    icon: "\uf0c9",
    entryPoint: "BarWidget.qml",
    ipcTarget: "menu"
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
  var icon = (manifest && manifest.icon) || known.icon || "\uf013";
  var ipcTarget = known.ipcTarget || pluginId;
  var entryPoint = (manifest && manifest.entryPoints && (manifest.entryPoints.barWidget || manifest.entryPoints.panel))
    || known.entryPoint
    || "Panel.qml";

  return {
    id: pluginId,
    name: name,
    icon: icon,
    entryPoint: entryPoint,
    ipcTarget: ipcTarget,
    manifest: manifest || null
  };
}

function isPlainObject(value) {
  return value !== null && typeof value === "object" && !Array.isArray(value);
}

function pluginStub(shellConfig, id) {
  if (!isPlainObject(shellConfig) || !Array.isArray(shellConfig.plugins)) return null;
  for (var i = 0; i < shellConfig.plugins.length; i++) {
    var entry = shellConfig.plugins[i];
    if (isPlainObject(entry) && String(entry.id) === id) return entry;
  }
  return null;
}

function childSettings(id, shellConfig) {
  var out = {};
  var stub = pluginStub(shellConfig, id);
  if (stub) {
    for (var stubKey in stub) if (stubKey !== "id") out[stubKey] = stub[stubKey];
  }
  return out;
}

function isHostBar(candidate) {
  return !!candidate
    && typeof candidate.pluginBarApiFor === "function"
    && typeof candidate.requestPopout === "function"
    && !!candidate.barWidgetRegistry;
}

function findHostBar(rootItem) {
  if (!rootItem) return null;
  var stack = [rootItem];
  var visited = 0;
  while (stack.length > 0 && visited < 8000) {
    var node = stack.pop();
    visited++;
    if (!node) continue;
    var candidate = null;
    try { candidate = node.bar; } catch (e) { candidate = null; }
    if (isHostBar(candidate)) return candidate;
    var kids = node.children;
    if (!kids) continue;
    for (var i = 0; i < kids.length; i++) stack.push(kids[i]);
  }
  return null;
}

function isDescendant(item, ancestor) {
  var node = item;
  for (var guard = 0; node && guard < 64; guard++, node = node.parent) {
    if (node === ancestor) return true;
  }
  return false;
}

function clamp(value, min, max) {
  if (value < min) return min;
  if (value > max) return max;
  return value;
}

function getActiveItemList(itemIds, discoveredMap) {
  var list = [];
  var ids = itemIds || [];
  for (var i = 0; i < ids.length; i++) {
    var id = ids[i];
    if (!id || id === "evcode.drawer") continue;
    var meta = (discoveredMap && discoveredMap[id]) ? discoveredMap[id] : resolveItemMetadata(id, null);
    list.push(meta);
  }
  return list;
}

