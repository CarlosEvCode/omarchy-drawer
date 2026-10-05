.pragma library

// DrawerModel.js - Core metadata & discovery logic for Omarchy Drawer

var KNOWN_PLUGINS_MAP = {
  "tiertek.tekscan": {
    id: "tiertek.tekscan",
    name: "TekScan",
    icon: "\uf0ec",
    ipcTarget: "tiertek.tekscan"
  },
  "io.github.nobledoodle.omarchroma": {
    id: "io.github.nobledoodle.omarchroma",
    name: "Omarchroma",
    icon: "\udb80\udfd8",
    ipcTarget: "io.github.nobledoodle.omarchroma"
  },
  "io.github.rsd.omavnc": {
    id: "io.github.rsd.omavnc",
    name: "omaVNC",
    icon: "\uf108",
    ipcTarget: "io.github.rsd.omavnc"
  },
  "io.github.brukb.omarchy-zerotier": {
    id: "io.github.brukb.omarchy-zerotier",
    name: "ZeroTier",
    icon: "\uf0ac",
    ipcTarget: "io.github.brukb.omarchy-zerotier"
  },
  "io.github.ricky.whatsapp": {
    id: "io.github.ricky.whatsapp",
    name: "WhatsApp",
    icon: "\uf232",
    ipcTarget: "io.github.ricky.whatsapp"
  },
  "io.github.sudoapwh.readout": {
    id: "io.github.sudoapwh.readout",
    name: "Readout",
    icon: "\uf2db",
    ipcTarget: "readout"
  },
  "omarchy.agents": {
    id: "omarchy.agents",
    name: "Agents",
    icon: "\uf544",
    ipcTarget: "agents"
  },
  "omarchy.media": {
    id: "omarchy.media",
    name: "Media",
    icon: "\uf001",
    ipcTarget: "media"
  },
  "ajkulundu.mediaplusplus": {
    id: "ajkulundu.mediaplusplus",
    name: "Media++",
    icon: "\uf001",
    ipcTarget: "mediaplusplus"
  },
  "io.github.mtolhuys.fathom": {
    id: "io.github.mtolhuys.fathom",
    name: "Fathom",
    icon: "\uf002",
    ipcTarget: "fathom"
  },
  "io.github.aryan-techie.bluetooth": {
    id: "io.github.aryan-techie.bluetooth",
    name: "Bluetooth",
    icon: "\uf293",
    ipcTarget: "bluetooth"
  },
  "io.github.deunnis.lacquer": {
    id: "io.github.deunnis.lacquer",
    name: "Lacquer",
    icon: "\uf53f",
    ipcTarget: "lacquer"
  },
  "evcode.hotspot": {
    id: "evcode.hotspot",
    name: "Hotspot",
    icon: "\uf1eb",
    ipcTarget: "hotspot"
  },
  "evcode.network": {
    id: "evcode.network",
    name: "Network",
    icon: "\uf1eb",
    ipcTarget: "network"
  },
  "omarchy.audio": {
    id: "omarchy.audio",
    name: "Audio",
    icon: "\uf028",
    ipcTarget: "audio"
  },
  "omarchy.monitor": {
    id: "omarchy.monitor",
    name: "Display",
    icon: "\uf108",
    ipcTarget: "monitor"
  },
  "omarchy.power": {
    id: "omarchy.power",
    name: "Power",
    icon: "\uf011",
    ipcTarget: "power"
  },
  "omarchy.tailscale": {
    id: "omarchy.tailscale",
    name: "Tailscale",
    icon: "\uf0c2",
    ipcTarget: "tailscale"
  },
  "omarchy.tray": {
    id: "omarchy.tray",
    name: "System Tray",
    icon: "\uf078",
    ipcTarget: "tray"
  },
  "omarchy.system-update": {
    id: "omarchy.system-update",
    name: "System Update",
    icon: "\uf021",
    ipcTarget: "system-update"
  },
  "omarchy.indicators": {
    id: "omarchy.indicators",
    name: "Indicators",
    icon: "\uf0eb",
    ipcTarget: "indicators"
  },
  "omarchy.keyboard-layout": {
    id: "omarchy.keyboard-layout",
    name: "Keyboard",
    icon: "\uf11c",
    ipcTarget: "keyboard-layout"
  },
  "omarchy.clock": {
    id: "omarchy.clock",
    name: "Clock",
    icon: "\uf017",
    ipcTarget: "clock"
  },
  "omarchy.active-window": {
    id: "omarchy.active-window",
    name: "Active Window",
    icon: "\uf2d0",
    ipcTarget: "active-window"
  },
  "omarchy.workspaces": {
    id: "omarchy.workspaces",
    name: "Workspaces",
    icon: "\uf108",
    ipcTarget: "workspaces"
  },
  "omarchy.menu": {
    id: "omarchy.menu",
    name: "Menu",
    icon: "\uf0c9",
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

  return {
    id: pluginId,
    name: name,
    icon: icon,
    ipcTarget: ipcTarget
  };
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
