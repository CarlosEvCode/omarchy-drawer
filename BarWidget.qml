import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "DrawerModel.js" as DrawerModel
import "ui"

BarWidget {
  id: root
  moduleName: "evcode.drawer"

  // Settings properties
  property string triggerMode: root.setting("trigger", "hover")
  property string displayMode: root.setting("mode", "inline-drawer")
  property int animationDuration: root.setting("animationDuration", 280)
  property bool dimInactive: root.setting("dimInactive", true)
  property var itemIds: root.setting("items", [
    "tiertek.tekscan",
    "io.github.nobledoodle.omarchroma",
    "io.github.rsd.omavnc",
    "io.github.brukb.omarchy-zerotier",
    "io.github.ricky.whatsapp"
  ])

  // Internal state
  property bool expanded: false
  property var discoveredPlugins: []
  property var discoveredMap: ({})
  property var activeItems: DrawerModel.getActiveItemList(itemIds, discoveredMap)

  readonly property bool isHoverTrigger: triggerMode === "hover"
  readonly property bool isInlineMode: displayMode === "inline-drawer"
  readonly property bool opened: isInlineMode ? expanded : (panelLoader.item ? panelLoader.item.opened : false)

  function open() {
    if (isInlineMode) {
      expanded = true
    } else if (panelLoader.item) {
      panelLoader.item.open()
    }
  }

  function close() {
    if (isInlineMode) {
      expanded = false
    } else if (panelLoader.item) {
      panelLoader.item.close()
    }
  }

  function toggle() {
    if (isInlineMode) {
      expanded = !expanded
    } else if (panelLoader.item) {
      panelLoader.item.toggle()
    }
  }

  function openManage() {
    if (managePopupLoader.item) {
      managePopupLoader.item.open = true
    }
  }

  function reloadFromDisk() {
    loadConfigProc.running = false
    loadConfigProc.running = true
  }

  function updateConfig(newConfig) {
    if (!newConfig) return
    if (newConfig.trigger !== undefined) triggerMode = newConfig.trigger
    if (newConfig.mode !== undefined) displayMode = newConfig.mode
    if (newConfig.dimInactive !== undefined) dimInactive = newConfig.dimInactive
    if (newConfig.items !== undefined) {
      itemIds = newConfig.items
      root.recalculateActiveItems()
    }
    saveConfigProcess.command = [
      "bash", "-c",
      "mkdir -p ~/.config/omarchy && cat << 'EOF' > ~/.config/omarchy/drawer.json\n" + JSON.stringify(newConfig, null, 2) + "\nEOF"
    ]
    saveConfigProcess.running = true
  }

  function addItem(pluginId) {
    if (!pluginId) return
    var list = itemIds.slice(0)
    if (list.indexOf(pluginId) === -1) {
      list.push(pluginId)
      updateConfig({
        trigger: triggerMode,
        mode: displayMode,
        dimInactive: dimInactive,
        items: list
      })
    }
  }

  function removeItem(pluginId) {
    if (!pluginId) return
    var list = itemIds.slice(0)
    var idx = list.indexOf(pluginId)
    if (idx !== -1) {
      list.splice(idx, 1)
      updateConfig({
        trigger: triggerMode,
        mode: displayMode,
        dimInactive: dimInactive,
        items: list
      })
    }
  }

  function recalculateActiveItems() {
    activeItems = DrawerModel.getActiveItemList(itemIds, discoveredMap)
  }

  // Scan installed plugins for discovery
  Process {
    id: scanPluginsProc
    running: true
    command: [
      "bash", "-c",
      "for f in ~/.config/omarchy/plugins/*/manifest.json /usr/share/omarchy/shell/plugins/*/manifest.json; do [ -f \"$f\" ] && cat \"$f\" && echo '---JSON_SPLIT---'; done"
    ]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var chunks = String(text || "").split("---JSON_SPLIT---")
        var map = {}
        var list = []
        for (var i = 0; i < chunks.length; i++) {
          var chunk = chunks[i].trim()
          if (!chunk) continue
          var manifest = DrawerModel.parseJsonSafe(chunk, null)
          if (manifest && manifest.id && manifest.id !== "evcode.drawer") {
            var meta = DrawerModel.resolveItemMetadata(manifest.id, manifest)
            map[manifest.id] = meta
            list.push(meta)
          }
        }
        // Add any default known plugins not present in scan
        for (var k in DrawerModel.KNOWN_PLUGINS_MAP) {
          if (!map[k]) {
            var kMeta = DrawerModel.KNOWN_PLUGINS_MAP[k]
            map[k] = kMeta
            list.push(kMeta)
          }
        }
        root.discoveredMap = map
        root.discoveredPlugins = list
        root.recalculateActiveItems()
      }
    }
  }

  Process {
    id: saveConfigProcess
    running: false
  }

  // Load custom config if exists
  Process {
    id: loadConfigProc
    running: true
    command: ["bash", "-c", "[ -f ~/.config/omarchy/drawer.json ] && cat ~/.config/omarchy/drawer.json || echo '{}'"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var cfg = DrawerModel.parseJsonSafe(text, null)
        if (cfg && cfg.items) {
          if (cfg.trigger !== undefined) root.triggerMode = cfg.trigger
          if (cfg.mode !== undefined) root.displayMode = cfg.mode
          if (cfg.dimInactive !== undefined) root.dimInactive = cfg.dimInactive
          if (cfg.items !== undefined) root.itemIds = cfg.items
          root.recalculateActiveItems()
        }
      }
    }
  }

  // Timer for smooth hover exit debounce
  Timer {
    id: hoverExitTimer
    interval: 220
    repeat: false
    onTriggered: {
      if (!containerHover.hovered) {
        root.expanded = false
      }
    }
  }

  IpcHandler {
    target: "evcode.drawer"
    function open(): void { root.open() }
    function close(): void { root.close() }
    function show(): void { root.open() }
    function hide(): void { root.close() }
    function toggle(): void { root.toggle() }
    function list(): string { return JSON.stringify(root.itemIds) }
    function add(pluginId: string): void { root.addItem(pluginId) }
    function remove(pluginId: string): void { root.removeItem(pluginId) }
    function manage(): void { root.openManage() }
  }

  implicitWidth: isInlineMode ? (expander.implicitWidth + itemsContainer.width) : expander.implicitWidth
  implicitHeight: expander.implicitHeight

  HoverHandler {
    id: containerHover
    enabled: root.isHoverTrigger && root.isInlineMode
    onHoveredChanged: {
      if (hovered) {
        hoverExitTimer.stop()
        root.expanded = true
      } else {
        hoverExitTimer.restart()
      }
    }
  }

  Row {
    id: mainRow
    anchors.fill: parent
    spacing: 0

    // Collapsible tray of items
    Item {
      id: itemsContainer
      visible: root.isInlineMode
      clip: true
      height: parent.height
      width: root.expanded ? (root.activeItems.length * Style.bar.iconSlot) : 0

      Behavior on width {
        NumberAnimation {
          duration: root.animationDuration
          easing.type: Easing.OutCubic
        }
      }

      Row {
        anchors.left: parent.left
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        spacing: 0

        Repeater {
          model: root.activeItems

          delegate: DrawerItem {
            bar: root.bar
            dimInactive: root.dimInactive
            itemData: modelData
          }
        }
      }
    }

    // Expander glyph button
    ExpanderGlyph {
      id: expander
      bar: root.bar
      expanded: root.expanded
      isHoverTrigger: root.isHoverTrigger
      onToggleRequested: {
        root.toggle()
      }
      onManageRequested: {
        root.openManage()
      }
    }
  }

  // Panel loader for popover-dock mode
  Loader {
    id: panelLoader
    active: !root.isInlineMode
    source: Qt.resolvedUrl("Panel.qml")
    visible: false
    onLoaded: {
      if (item) {
        item.bar = root.bar
        item.anchorItem = expander
        item.hostWidget = root
        item.activeItems = root.activeItems
        item.dimInactive = root.dimInactive
        item.manageRequested.connect(root.openManage)
      }
    }
  }

  // Manage popup dialog
  Loader {
    id: managePopupLoader
    active: true
    source: Qt.resolvedUrl("ManagePopup.qml")
    visible: false
    onLoaded: {
      if (item) {
        item.bar = root.bar
        item.anchorItem = expander
        item.hostWidget = root
        item.discoveredPlugins = root.discoveredPlugins
        item.activeItemIds = root.itemIds
        item.triggerModeSetting = root.triggerMode
        item.displayModeSetting = root.displayMode
        item.dimInactiveSetting = root.dimInactive
      }
    }
  }

  onDiscoveredPluginsChanged: {
    if (managePopupLoader.item) {
      managePopupLoader.item.discoveredPlugins = root.discoveredPlugins
    }
  }

  onItemIdsChanged: {
    if (managePopupLoader.item) {
      managePopupLoader.item.activeItemIds = root.itemIds
    }
  }

  onActiveItemsChanged: {
    if (panelLoader.item) {
      panelLoader.item.activeItems = root.activeItems
    }
  }
}
