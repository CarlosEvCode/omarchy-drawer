import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.Ui
import qs.Commons
import "DrawerModel.js" as DrawerModel

Panel {
  id: root
  moduleName: "evcode.drawer"
  ipcTarget: "evcode.drawer"
  manageIpc: false

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  readonly property string pluginDir: Quickshell.env("HOME") + "/.config/omarchy/plugins/evcode.drawer"
  readonly property string helperBin: {
    var localPath = pluginDir + "/bin/drawer-helper"
    return localPath
  }

  // State
  property var rawDrawerItemIds: []
  property var discoveredPlugins: []
  property var discoveredMap: ({})
  property var activeDrawerItems: DrawerModel.getActiveItemList(rawDrawerItemIds, discoveredMap)
  readonly property var compactDrawerItems: activeDrawerItems.filter(function(item) { return !item.isWide })
  readonly property var wideDrawerItems: activeDrawerItems.filter(function(item) { return !!item.isWide })
  property var barWidgetsList: []
  property bool addingMode: false
  property bool editingMode: false
  property bool headerCollapsed: false
  property string hoveredPluginName: ""

  property bool barDropActive: false
  property bool cardDropActive: false
  property int draggingIndex: -1
  property int dropTargetIndex: -1
  property int draggingWideIndex: -1
  property int dropTargetWideIndex: -1

  function resetDragState() {
    draggingIndex = -1
    dropTargetIndex = -1
    draggingWideIndex = -1
    dropTargetWideIndex = -1
    hoveredPluginName = ""
  }

  onEditingModeChanged: resetDragState()

  // Spring-Loaded Timer (OmaSafe pattern)
  Timer {
    id: springTimer
    interval: 600
    onTriggered: {
      if (root.barDropActive && !root.opened) {
        root.open()
      }
    }
  }

  // Watchdog timer to clear stuck drop states
  Timer {
    id: dropWatchdogTimer
    interval: 10000
    onTriggered: {
      root.barDropActive = false
      root.cardDropActive = false
      springTimer.stop()
    }
  }

  // Instant C++ FileView for drawer.json (0ms startup overhead, zero bash forks)
  FileView {
    id: drawerConfigFile
    path: Quickshell.env("HOME") + "/.config/omarchy/drawer.json"
    watchChanges: true
    atomicWrites: true
    printErrors: false
    onLoaded: {
      var cfg = DrawerModel.parseJsonSafe(text(), null)
      if (cfg && cfg.items && Array.isArray(cfg.items)) {
        root.rawDrawerItemIds = cfg.items
      } else {
        root.rawDrawerItemIds = []
      }
      if (cfg && typeof cfg.headerCollapsed === "boolean") {
        root.headerCollapsed = cfg.headerCollapsed
      }
      root.activeDrawerItems = DrawerModel.getActiveItemList(root.rawDrawerItemIds, root.discoveredMap)
    }
    onLoadFailed: {
      root.rawDrawerItemIds = []
      root.activeDrawerItems = []
    }
    onFileChanged: reload()
  }

  function toggleHeaderCollapsed() {
    root.headerCollapsed = !root.headerCollapsed
    barActionProc.command = [root.helperBin, "set-header-collapsed", root.headerCollapsed ? "true" : "false"]
    barActionProc.running = true
  }

  onAddingModeChanged: {
    if (addingMode) {
      listBarProc.running = false
      listBarProc.running = true
      scanManifestsProc.running = false
      scanManifestsProc.running = true
    }
  }

  function reloadAllData() {
    drawerConfigFile.reload()
    listBarProc.running = false
    listBarProc.running = true
    scanManifestsProc.running = false
    scanManifestsProc.running = true
  }

  function saveReorder(newIds) {
    if (!newIds || !Array.isArray(newIds)) return
    root.rawDrawerItemIds = newIds
    root.activeDrawerItems = DrawerModel.getActiveItemList(root.rawDrawerItemIds, root.discoveredMap)
    barActionProc.command = [root.helperBin, "reorder-items", JSON.stringify(newIds)]
    barActionProc.running = true
  }

  function reorderItem(fromIdx, toIdx) {
    if (fromIdx === toIdx || fromIdx < 0 || toIdx < 0) return
    var list = [].concat(root.rawDrawerItemIds)
    if (fromIdx >= list.length || toIdx >= list.length) return
    var item = list.splice(fromIdx, 1)[0]
    list.splice(toIdx, 0, item)
    saveReorder(list)
  }

  function reorderCompactItem(compactFromIdx, compactToIdx) {
    if (compactFromIdx === compactToIdx || compactFromIdx < 0 || compactToIdx < 0) return
    var compactList = [].concat(root.compactDrawerItems)
    if (compactFromIdx >= compactList.length || compactToIdx >= compactList.length) return
    var movingId = compactList[compactFromIdx].id
    var targetId = compactList[compactToIdx].id
    var rawList = [].concat(root.rawDrawerItemIds)
    var rawFrom = rawList.indexOf(movingId)
    var rawTo = rawList.indexOf(targetId)
    if (rawFrom !== -1 && rawTo !== -1) {
      var item = rawList.splice(rawFrom, 1)[0]
      rawList.splice(rawTo, 0, item)
      saveReorder(rawList)
    }
  }

  function reorderWideItem(wideFromIdx, wideToIdx) {
    if (wideFromIdx === wideToIdx || wideFromIdx < 0 || wideToIdx < 0) return
    var wideList = [].concat(root.wideDrawerItems)
    if (wideFromIdx >= wideList.length || wideToIdx >= wideList.length) return
    var movingId = wideList[wideFromIdx].id
    var targetId = wideList[wideToIdx].id
    var rawList = [].concat(root.rawDrawerItemIds)
    var rawFrom = rawList.indexOf(movingId)
    var rawTo = rawList.indexOf(targetId)
    if (rawFrom !== -1 && rawTo !== -1) {
      var item = rawList.splice(rawFrom, 1)[0]
      rawList.splice(rawTo, 0, item)
      saveReorder(rawList)
    }
  }

  function launchPlugin(targetId) {
    if (!targetId) return
    var meta = (discoveredMap && discoveredMap[targetId]) ? discoveredMap[targetId] : DrawerModel.resolveItemMetadata(targetId, null)
    var ipcTarget = meta.ipcTarget || targetId

    // Close drawer panel first so focus handoff is clean
    root.close()

    Qt.callLater(function() {
      if (targetId === "tiertek.tekscan" || ipcTarget === "tekscan") {
        triggerProc.command = ["bash", "-c", "omarchy-shell tekscan toggle 2>/dev/null || omarchy-shell tekscan show 2>/dev/null || true"]
        triggerProc.running = false
        triggerProc.running = true
        return
      }

      triggerProc.command = [
        "bash", "-c",
        "omarchy-shell " + ipcTarget + " open 2>/dev/null || omarchy-shell " + ipcTarget + " show 2>/dev/null || omarchy-shell " + ipcTarget + " toggle 2>/dev/null || omarchy-shell " + targetId + " open 2>/dev/null || omarchy-shell " + targetId + " toggle 2>/dev/null || true"
      ]
      triggerProc.running = false
      triggerProc.running = true
    })
  }

  function hideFromBarAndReturn(pluginId) {
    if (!pluginId) return
    if (root.host && root.host.shell && typeof root.host.shell.mutateShellConfig === "function") {
      root.host.shell.mutateShellConfig(function(draft) {
        if (draft && draft.bar && draft.bar.layout) {
          for (var s in draft.bar.layout) {
            if (Array.isArray(draft.bar.layout[s])) {
              draft.bar.layout[s] = draft.bar.layout[s].filter(function(e) {
                return !(e && e.id === pluginId)
              })
            }
          }
        }
        if (draft && Array.isArray(draft.plugins)) {
          var exists = draft.plugins.some(function(p) { return p && p.id === pluginId })
          if (!exists) draft.plugins.push({ id: pluginId })
        }
      })
    }
    barActionProc.command = [root.helperBin, "hide-from-bar", pluginId]
    barActionProc.running = true
    root.addingMode = false
    dropWatchdogTimer.restart()
  }

  function restoreToBar(pluginId) {
    if (!pluginId) return
    if (root.host && root.host.shell && typeof root.host.shell.mutateShellConfig === "function") {
      root.host.shell.mutateShellConfig(function(draft) {
        if (draft && draft.bar && draft.bar.layout) {
          for (var s in draft.bar.layout) {
            if (Array.isArray(draft.bar.layout[s])) {
              draft.bar.layout[s] = draft.bar.layout[s].filter(function(e) {
                return !(e && e.id === pluginId)
              })
            }
          }
          if (Array.isArray(draft.bar.layout.right)) {
            var drawerIdx = -1
            for (var i = 0; i < draft.bar.layout.right.length; i++) {
              if (draft.bar.layout.right[i] && draft.bar.layout.right[i].id === "evcode.drawer") {
                drawerIdx = i
                break
              }
            }
            if (drawerIdx !== -1) {
              draft.bar.layout.right.splice(drawerIdx, 0, { id: pluginId })
            } else {
              draft.bar.layout.right.push({ id: pluginId })
            }
          }
        }
      })
    }
    barActionProc.command = [root.helperBin, "restore-to-bar", pluginId]
    barActionProc.running = true
  }

  property var host: null
  property int hostScanAttempts: 0
  property var childSlots: []

  readonly property bool childPopoutOpen: {
    var active = host ? host.activePopout : null
    return !!active && active !== root && ownsPopout(active)
  }

  function ownsPopout(target) {
    if (!target) return false
    var anchor = null
    try { anchor = target.anchorItem } catch (e) { anchor = null }
    for (var i = 0; i < childSlots.length; i++) {
      var slot = childSlots[i]
      if (!slot) continue
      if (slot === target || slot.activeItem === target) return true
      if (anchor && DrawerModel.isDescendant(anchor, slot)) return true
    }
    return false
  }

  function registerChild(slot) {
    if (childSlots.indexOf(slot) === -1) childSlots = childSlots.concat([slot])
  }

  function unregisterChild(slot) {
    childSlots = childSlots.filter(function(item) { return item !== slot })
  }

  function resolveHost() {
    var found = DrawerModel.isHostBar(root.bar) ? root.bar : null
    if (!found) {
      var win = root.QsWindow.window
      found = win ? DrawerModel.findHostBar(win.contentItem) : null
    }
    if (found !== host) host = found
    if (!found && hostScanAttempts < 40) {
      hostScanAttempts++
      hostRetry.restart()
    }
  }

  Timer {
    id: hostRetry
    interval: 250
    onTriggered: root.resolveHost()
  }

  onBarChanged: {
    hostScanAttempts = 0
    Qt.callLater(resolveHost)
    slotScan.restart()
  }

  Component.onCompleted: {
    Qt.callLater(resolveHost)
    slotScan.restart()
    scanManifestsProc.running = true
  }

  // ── TOP BAR DRAG DETECTION (Drop bar widgets directly onto Drawer icon) ──
  property var barSlots: []
  property var barDragSlot: null
  property bool barDragging: false
  property string barDragId: ""
  property bool barDropHover: false
  property int idleTicks: 0
  property var watchedSlots: []

  function isModuleSlot(item) {
    return !!item && ("dragSource" in item) && ("moduleName" in item) && ("region" in item)
  }

  function ownSlot() {
    var node = root.parent
    while (node) {
      if (root.isModuleSlot(node)) return node
      node = node.parent
    }
    return null
  }

  function collectBarSlots() {
    var own = root.ownSlot()
    if (!own) return
    var top = own
    while (top.parent) top = top.parent
    var found = []
    var queue = [top]
    for (var guard = 0; queue.length > 0 && guard < 5000; guard++) {
      var node = queue.shift()
      if (!node) continue
      if (root.isModuleSlot(node)) {
        found.push(node)
        continue
      }
      var kids = node.children
      if (kids) for (var i = 0; i < kids.length; i++) queue.push(kids[i])
    }
    root.barSlots = found
    for (var j = 0; j < found.length; j++) root.watchSlot(found[j])
  }

  function watchSlot(slot) {
    if (!slot || root.watchedSlots.indexOf(slot) !== -1) return
    root.watchedSlots = root.watchedSlots.filter(function(item) { return !!item && !!item.parent }).concat([slot])
    slot.dragSourceChanged.connect(function() {
      try {
        if (slot.dragSource === true) {
          if (slot !== root.ownSlot()) root.startBarDrag(slot)
        } else if (root.barDragging && root.barDragSlot === slot) {
          root.barDropHover = root.barDragId !== "" && root.pointerOverIcon(slot)
          root.finishBarDrag()
        }
      } catch (e) {
      }
    })
  }

  function slotPointer(slot) {
    var kids = slot ? slot.children : null
    if (!kids) return null
    for (var i = 0; i < kids.length; i++)
      if (kids[i] && ("dragging" in kids[i]) && ("pressedX" in kids[i])) return kids[i]
    return null
  }

  function pointerOverIcon(slot) {
    var pointer = root.slotPointer(slot)
    if (!pointer) return false
    var p = pointer.mapToItem(button, pointer.mouseX, pointer.mouseY)
    return p.x >= 0 && p.x <= button.width && p.y >= -button.height / 2 && p.y <= button.height * 1.5
  }

  function startBarDrag(slot) {
    root.barDragging = true
    root.barDragSlot = slot
    root.barDragId = slot.customType ? "" : String(slot.moduleName || "")
  }

  function finishBarDrag() {
    var id = root.barDragId
    var dropped = root.barDropHover
    root.barDragging = false
    root.barDragSlot = null
    root.barDragId = ""
    root.barDropHover = false
    if (dropped && id && id !== root.moduleName) {
      Qt.callLater(function() {
        root.hideFromBarAndReturn(id)
      })
    }
  }

  function pollBarDrag() {
    var own = root.ownSlot()
    var active = null
    var stale = false
    for (var i = 0; i < root.barSlots.length; i++) {
      var slot = root.barSlots[i]
      try {
        if (!slot || !slot.parent) stale = true
        else if (slot !== own && slot.dragSource === true) active = slot
      } catch (e) {
        stale = true
      }
    }

    if (active) {
      if (!root.barDragging || root.barDragSlot !== active) root.startBarDrag(active)
      root.barDropHover = root.barDragId !== "" && root.pointerOverIcon(active)
      return
    }

    if (!root.barDragging) {
      root.idleTicks++
      if (stale || root.idleTicks >= 12) {
        root.idleTicks = 0
        root.collectBarSlots()
      }
      return
    }
    root.finishBarDrag()
  }

  Timer {
    id: dragWatch
    interval: root.barDragging ? 30 : 150
    running: true
    repeat: true
    onTriggered: root.pollBarDrag()
  }

  Timer {
    id: slotScan
    interval: 800
    onTriggered: root.collectBarSlots()
  }

  Connections {
    target: root.bar
    ignoreUnknownSignals: true
    function onLayoutConfigChanged() { slotScan.restart() }
  }

  Connections {
    target: root.host
    ignoreUnknownSignals: true
    function onActivePopoutChanged() {
      if (!root.opened || !root.host) return
      var active = root.host.activePopout
      if (active === root || active === null) return
      if (root.ownsPopout(active)) {
        return
      }
    }
  }

  Process {
    id: triggerProc
    running: false
  }

  Process {
    id: barActionProc
    running: false
    onRunningChanged: {
      if (!running) {
        root.reloadAllData()
      }
    }
  }

  // Load bar widgets strictly on-demand when entering Add mode
  Process {
    id: listBarProc
    running: false
    command: [root.helperBin, "list-bar-items"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var items = DrawerModel.parseJsonSafe(text, [])
        root.barWidgetsList = items
      }
    }
  }

  // Scan manifests for proper names and icons on-demand
  Process {
    id: scanManifestsProc
    running: false
    command: [root.helperBin, "list-manifests"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var list = DrawerModel.parseJsonSafe(text, [])
        var map = {}
        var fullList = []
        for (var i = 0; i < list.length; i++) {
          var manifest = list[i]
          if (manifest && manifest.id && manifest.id !== "evcode.drawer") {
            var meta = DrawerModel.resolveItemMetadata(manifest.id, manifest)
            map[manifest.id] = meta
            fullList.push(meta)
          }
        }
        for (var k in DrawerModel.KNOWN_PLUGINS_MAP) {
          if (!map[k]) {
            var kMeta = DrawerModel.KNOWN_PLUGINS_MAP[k]
            map[k] = kMeta
            fullList.push(kMeta)
          }
        }
        root.discoveredMap = map
        root.discoveredPlugins = fullList
        root.activeDrawerItems = DrawerModel.getActiveItemList(root.rawDrawerItemIds, root.discoveredMap)
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
    function list(): string { return JSON.stringify(root.rawDrawerItemIds) }
    function add(pluginId: string): void { root.hideFromBarAndReturn(pluginId) }
    function remove(pluginId: string): void { root.restoreToBar(pluginId) }
    function launch(pluginId: string): void { root.launchPlugin(pluginId) }
  }

  onOpenedChanged: {
    root.resetDragState()
    root.editingMode = false
    root.addingMode = false
    if (opened) {
      root.reloadAllData()
      Qt.callLater(function() { mainColumn.forceActiveFocus() })
    } else {
      root.barDropActive = false
      root.cardDropActive = false
      springTimer.stop()
    }
  }

  // Bar Widget Icon Button with Spring-Loaded DropArea
  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: (root.barDropHover || root.barDropActive) ? "\uf0120" : "\uf187"
    active: root.opened || root.barDropActive || root.barDropHover
    tooltipText: (root.barDropHover || root.barDropActive)
      ? "Drop to move into Drawer"
      : (root.opened ? "Close Drawer" : "Drawer (" + root.activeDrawerItems.length + " items)")
    onPressed: function(buttonCode) {
      root.toggle()
    }

    DropArea {
      anchors.fill: parent
      onEntered: function(drag) {
        root.barDropActive = true
        springTimer.restart()
        dropWatchdogTimer.restart()
      }
      onExited: {
        root.barDropActive = false
        springTimer.stop()
      }
      onDropped: function(drop) {
        root.barDropActive = false
        springTimer.stop()
        root.open()
      }
    }
  }

  // Floating Popup Shelf Surface with layer-shell popout coordination
  Shelf {
    id: shelf
    host: root.host
    anchorItem: button
    open: root.opened
    suspendDismiss: root.childPopoutOpen
    padding: Style.spacing.sm
    readonly property real calcGridWidth: {
      var count = root.compactDrawerItems.length
      var cols = Math.min(5, Math.max(1, count))
      return (cols * Style.space(48)) + ((cols - 1) * Style.space(10))
    }
    contentWidth: root.addingMode
      ? Style.space(340)
      : (root.wideDrawerItems.length > 0
          ? Math.max(Style.space(340), calcGridWidth)
          : (root.headerCollapsed ? Math.max(Style.space(120), calcGridWidth) : Math.max(Style.space(250), calcGridWidth)))
    contentHeight: mainColumn.implicitHeight
    onDismissed: {
      if (!root.childPopoutOpen && root.tileDragIndex < 0) root.close()
    }

    DropArea {
      anchors.fill: parent
      onEntered: function(drag) {
        root.cardDropActive = true
        dropWatchdogTimer.restart()
      }
      onExited: {
        root.cardDropActive = false
      }
      onDropped: function(drop) {
        root.cardDropActive = false
      }
    }

    ColumnLayout {
      id: mainColumn
      anchors.fill: parent
      spacing: root.headerCollapsed && !root.addingMode ? Style.space(4) : Style.space(12)
      focus: true
      Keys.priority: Keys.BeforeItem
      Keys.onPressed: function(event) {
        if (event.key === Qt.Key_Escape) {
          if (root.addingMode) {
            root.addingMode = false
          } else if (root.editingMode) {
            root.editingMode = false
          } else {
            root.close()
          }
          event.accepted = true
        }
      }

      // MINI EXPAND HANDLE (When header is collapsed in minimalist view)
      RowLayout {
        Layout.fillWidth: true
        visible: root.headerCollapsed && !root.addingMode

        Item { Layout.fillWidth: true }

        BorderSurface {
          implicitWidth: Style.space(32)
          implicitHeight: Style.space(16)
          radius: Style.cornerRadius > 0 ? Math.min(Style.cornerRadius, 4) : 4
          color: miniExpandHover.hovered ? Style.hoverFillFor(Color.foreground, Color.accent) : "transparent"
          borderSpec: miniExpandHover.hovered ? Border.controlSpec("hover", Color.accent, Color.accent) : Border.none
          opacity: miniExpandHover.hovered ? 1.0 : 0.45

          Behavior on opacity { NumberAnimation { duration: 120 } }
          Behavior on color { ColorAnimation { duration: 120 } }

          HoverHandler { id: miniExpandHover }

          MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: root.toggleHeaderCollapsed()
          }

          Text {
            anchors.centerIn: parent
            text: "\uf078"
            color: miniExpandHover.hovered ? Color.accent : Color.foreground
            font.family: Style.font.family
            font.pixelSize: Math.round(Style.font.caption * 0.85)
          }
        }

        Item { Layout.fillWidth: true }
      }

      // FULL HEADER
      RowLayout {
        Layout.fillWidth: true
        visible: !root.headerCollapsed || root.addingMode
        spacing: Style.space(8)

        // Back button if in adding mode
        Button {
          visible: root.addingMode
          iconText: "\uf060"
          tooltipText: "Back to Drawer"
          onClicked: root.addingMode = false
        }

        Text {
          visible: !root.addingMode
          text: root.cardDropActive ? "\uf0120" : "\uf187"
          color: Color.accent
          font.family: Style.font.family
          font.pixelSize: Style.font.title
        }

        Text {
          text: root.cardDropActive ? "Drop here" : (root.addingMode ? "Add to Drawer" : (root.editingMode ? "Edit" : (root.hoveredPluginName !== "" ? root.hoveredPluginName : "Drawer")))
          color: Color.foreground
          font.family: Style.font.family
          font.pixelSize: Style.font.title
          font.bold: true
          elide: Text.ElideRight
          Layout.fillWidth: true

          Behavior on color {
            ColorAnimation { duration: 120 }
          }
        }

        // Edit Mode Toggle Button
        Button {
          visible: !root.addingMode && root.activeDrawerItems.length > 0
          iconText: root.editingMode ? "\uf00c" : "\uf044"
          tooltipText: root.editingMode ? "Done" : "Edit"
          selected: root.editingMode
          onClicked: root.editingMode = !root.editingMode
        }

        // + Button to add plugins from bar
        Button {
          visible: !root.addingMode
          iconText: "\uf067"
          tooltipText: "Add from bar"
          selected: root.addingMode
          onClicked: {
            root.reloadAllData()
            root.editingMode = false
            root.addingMode = true
          }
        }

        // Collapse Header Button (Minimalist toggle)
        Button {
          visible: !root.addingMode
          iconText: "\uf077"
          tooltipText: "Hide header (Minimalist view)"
          onClicked: root.toggleHeaderCollapsed()
        }

        Button {
          iconText: "\uf00d"
          tooltipText: "Close (Esc)"
          onClicked: root.close()
        }
      }

      PanelSeparator {
        Layout.fillWidth: true
        visible: !root.headerCollapsed || root.addingMode
      }

      // ── MAIN VIEW: UNIFIED DRAWER WITH COMPACT GRID & FULL-WIDTH WIDE WIDGETS ──
      ColumnLayout {
        Layout.fillWidth: true
        visible: !root.addingMode && !root.settingsMode
        spacing: Style.space(10)
        clip: false

        // Empty state when drawer is empty
        BorderSurface {
          visible: root.activeDrawerItems.length === 0
          Layout.fillWidth: true
          implicitHeight: Style.space(70)
          radius: Style.cornerRadius
          color: "transparent"

          ColumnLayout {
            anchors.centerIn: parent
            spacing: Style.space(4)

            Text {
              text: "Empty Drawer"
              color: Color.foreground
              font.family: Style.font.family
              font.pixelSize: Style.font.body
              font.bold: true
              Layout.alignment: Qt.AlignHCenter
            }

            Button {
              text: "Add from bar"
              iconText: "\uf067"
              Layout.alignment: Qt.AlignHCenter
              onClicked: {
                root.reloadAllData()
                root.addingMode = true
              }
            }
          }
        }

        // 1. Compact Icon Grid (Top Section)
        Flow {
          id: itemsGrid
          visible: root.compactDrawerItems.length > 0
          readonly property int cols: Math.min(5, Math.max(1, root.compactDrawerItems.length))
          readonly property real gridWidth: (cols * Style.space(48)) + ((cols - 1) * spacing)
          Layout.preferredWidth: gridWidth
          Layout.alignment: Qt.AlignHCenter
          spacing: Style.space(10)
          clip: false

          Repeater {
            id: itemsRepeater
            model: root.compactDrawerItems

            delegate: Item {
              id: itemDelegate
              required property var modelData
              required property int index

              readonly property string childId: String(modelData.id || modelData)
              readonly property var registryEntry: {
                var registry = root.host ? root.host.barWidgetRegistry : null
                var widgets = registry ? registry.widgets : null
                return widgets && widgets[childId] ? widgets[childId] : null
              }
              readonly property bool firstParty: !!registryEntry && !!registryEntry.metadata && registryEntry.metadata.firstParty === true

              readonly property bool isDragging: root.editingMode && root.draggingIndex === index
              readonly property bool isDropTarget: root.editingMode && root.dropTargetIndex === index && root.draggingIndex !== index

              readonly property Item activeItem: nativeWidgetLoader.item

              width: Style.space(48)
              height: Style.space(48)
              clip: true
              z: isDragging ? 1000 : (tileHover.hovered ? 100 : 1)

              Component.onCompleted: root.registerChild(itemDelegate)
              Component.onDestruction: root.unregisterChild(itemDelegate)

              BorderSurface {
                anchors.fill: parent
                clip: true
                radius: Style.cornerRadius
                color: isDragging
                  ? Qt.alpha(Color.accent, 0.25)
                  : ((tileHover.hovered && (!nativeWidgetLoader.item || !nativeWidgetLoader.item.visible || root.editingMode)) ? Style.hoverFillFor(Color.foreground, Color.accent) : "transparent")
                borderSpec: root.editingMode
                  ? (isDragging || isDropTarget ? Border.controlSpec("hover", Color.accent, Color.accent) : Border.controlSpec("urgent", Color.urgent, Color.urgent))
                  : ((isDragging || isDropTarget || (tileHover.hovered && (!nativeWidgetLoader.item || !nativeWidgetLoader.item.visible))) ? Border.controlSpec("hover", Color.accent, Color.accent) : Border.none)

                scale: isDragging ? 1.15 : (isDropTarget ? 1.08 : 1.0)
                opacity: isDragging ? 0.35 : 1.0

                Behavior on scale {
                  NumberAnimation { duration: 120; easing.type: Easing.OutCubic }
                }
                Behavior on opacity {
                  NumberAnimation { duration: 120; easing.type: Easing.OutCubic }
                }
                Behavior on color {
                  ColorAnimation { duration: 120 }
                }

                Loader {
                  id: nativeWidgetLoader
                  active: !root.editingMode && registryEntry !== null
                  anchors.centerIn: parent
                  sourceComponent: registryEntry ? registryEntry.component : null

                  function syncProperties() {
                    var target = item
                    if (!target || !root.host) return
                    if ("bar" in target) {
                      var nextBar = firstParty ? root.host : root.host.pluginBarApiFor(childId, childId, true)
                      if (target.bar !== nextBar) target.bar = nextBar
                    }
                    if ("moduleName" in target && target.moduleName !== childId) target.moduleName = childId
                    var childSettings = DrawerModel.childSettings(childId, root.host ? root.host.shell.shellConfig : null)
                    if ("settings" in target) target.settings = childSettings
                  }

                  onLoaded: syncProperties()

                  Connections {
                    target: root
                    function onHostChanged() { nativeWidgetLoader.syncProperties() }
                    function onOpenedChanged() {
                      if (root.opened) nativeWidgetLoader.syncProperties()
                    }
                  }
                }

                Text {
                  visible: root.editingMode || nativeWidgetLoader.status !== Loader.Ready || !nativeWidgetLoader.item
                  anchors.centerIn: parent
                  text: modelData.icon || "\uf013"
                  color: (isDragging || tileHover.hovered || isDropTarget) ? Color.accent : Color.foreground
                  font.family: Style.font.family
                  font.pixelSize: Style.font.iconLarge
                  scale: (tileHover.hovered || isDragging) ? 1.15 : 1.0

                  Behavior on scale {
                    NumberAnimation { duration: 120; easing.type: Easing.OutCubic }
                  }
                  Behavior on color {
                    ColorAnimation { duration: 120 }
                  }
                }
              }

              // Edit Mode "X" Badge in Top-Right Corner
              BorderSurface {
                visible: root.editingMode && !isDragging
                anchors.top: parent.top
                anchors.right: parent.right
                anchors.topMargin: -Style.space(4)
                anchors.rightMargin: -Style.space(4)
                width: Style.space(18)
                height: Style.space(18)
                radius: 9
                color: Color.urgent || "#ff4455"
                z: 300

                Text {
                  anchors.centerIn: parent
                  text: "\uf00d"
                  color: "#ffffff"
                  font.family: Style.font.family
                  font.pixelSize: Math.round(Style.font.caption * 0.8)
                  font.bold: true
                }
              }

              // Floating Name Pill
              BorderSurface {
                id: floatingPill
                visible: !root.editingMode && !isDragging && tileHover.hovered && (!nativeWidgetLoader.item || !nativeWidgetLoader.item.visible)
                opacity: visible ? 1.0 : 0.0
                anchors.horizontalCenter: parent.horizontalCenter
                y: -implicitHeight - Style.space(6)
                z: 200
                implicitHeight: Style.space(24)
                implicitWidth: pillLabel.implicitWidth + Style.space(16)
                radius: Style.cornerRadius > 0 ? Style.cornerRadius : 4
                color: Color.background
                borderSpec: Border.controlSpec("hover", Color.accent, Color.accent)

                Behavior on opacity {
                  NumberAnimation { duration: 120; easing.type: Easing.OutCubic }
                }

                Text {
                  id: pillLabel
                  anchors.centerIn: parent
                  text: modelData.name || modelData.id
                  color: Color.foreground
                  font.family: Style.font.family
                  font.pixelSize: Style.font.caption
                  font.bold: true
                }
              }

              HoverHandler {
                id: tileHover
                enabled: !root.editingMode
                onHoveredChanged: {
                  if (hovered && root.draggingIndex < 0) {
                    root.hoveredPluginName = modelData.name || modelData.id
                  } else if (!hovered && root.hoveredPluginName === (modelData.name || modelData.id)) {
                    root.hoveredPluginName = ""
                  }
                }
              }

              MouseArea {
                id: editMouseArea
                anchors.fill: parent
                enabled: root.editingMode || nativeWidgetLoader.status !== Loader.Ready || !nativeWidgetLoader.item
                preventStealing: true
                cursorShape: dragging ? Qt.ClosedHandCursor : (root.editingMode ? Qt.SizeAllCursor : Qt.PointingHandCursor)

                property real pressX: 0
                property real pressY: 0
                property bool dragging: false
                property bool justDragged: false

                onPressed: function(mouse) {
                  pressX = mouse.x
                  pressY = mouse.y
                  dragging = false
                  justDragged = false
                }

                onPositionChanged: function(mouse) {
                  if (root.editingMode && (mouse.buttons & Qt.LeftButton)) {
                    var dist = Math.abs(mouse.x - pressX) + Math.abs(mouse.y - pressY)
                    if (!dragging && dist >= Style.space(6)) {
                      dragging = true
                      root.draggingIndex = index
                    }
                    if (dragging) {
                      var pt = mapToItem(itemsGrid, mouse.x, mouse.y)
                      var targetItem = itemsGrid.childAt(pt.x, pt.y)
                      if (targetItem && ("index" in targetItem) && targetItem.index !== undefined) {
                        root.dropTargetIndex = targetItem.index
                      } else {
                        root.dropTargetIndex = -1
                      }
                    }
                  }
                }

                onReleased: function(mouse) {
                  if (dragging) {
                    dragging = false
                    justDragged = true
                    if (root.dropTargetIndex >= 0 && root.dropTargetIndex !== root.draggingIndex) {
                      root.reorderCompactItem(root.draggingIndex, root.dropTargetIndex)
                    }
                    root.resetDragState()
                  }
                }

                onCanceled: {
                  if (dragging) {
                    dragging = false
                    root.resetDragState()
                  }
                }

                onClicked: function(mouse) {
                  if (justDragged) {
                    justDragged = false
                    return
                  }
                  if (root.editingMode) {
                    root.restoreToBar(modelData.id)
                  } else {
                    root.launchPlugin(modelData.id)
                  }
                }
              }
            }
          }
        }

        // Subtle separator if both compact items and wide widgets are present
        PanelSeparator {
          Layout.fillWidth: true
          visible: root.compactDrawerItems.length > 0 && root.wideDrawerItems.length > 0
        }

        // 2. Wide Widgets Stack (Bottom Section - Full Width)
        ColumnLayout {
          id: wideWidgetsCol
          visible: root.wideDrawerItems.length > 0
          Layout.fillWidth: true
          spacing: Style.space(8)

          Repeater {
            id: wideItemsRepeater
            model: root.wideDrawerItems

            delegate: Item {
              id: wideItemDelegate
              required property var modelData
              required property int index

              readonly property string childId: String(modelData.id || modelData)
              readonly property var registryEntry: {
                var registry = root.host ? root.host.barWidgetRegistry : null
                var widgets = registry ? registry.widgets : null
                return widgets && widgets[childId] ? widgets[childId] : null
              }
              readonly property bool firstParty: !!registryEntry && !!registryEntry.metadata && registryEntry.metadata.firstParty === true

              readonly property bool isDragging: root.editingMode && root.draggingWideIndex === index
              readonly property bool isDropTarget: root.editingMode && root.dropTargetWideIndex === index && root.draggingWideIndex !== index

              readonly property Item activeItem: nativeWideWidgetLoader.item
              readonly property bool itemReady: !root.editingMode && nativeWideWidgetLoader.status === Loader.Ready && !!nativeWideWidgetLoader.item && nativeWideWidgetLoader.item.visible

              Layout.fillWidth: true
              implicitHeight: Math.max(Style.space(42), nativeWideWidgetLoader.item && nativeWideWidgetLoader.item.implicitHeight > 0 ? (nativeWideWidgetLoader.item.implicitHeight + Style.space(8)) : Style.space(42))
              z: isDragging ? 1000 : (wideTileHover.hovered ? 100 : 1)

              Component.onCompleted: {
                root.registerChild(wideItemDelegate)
                if (nativeWideWidgetLoader.item) nativeWideWidgetLoader.syncProperties()
              }
              Component.onDestruction: root.unregisterChild(wideItemDelegate)

              BorderSurface {
                anchors.fill: parent
                radius: Style.cornerRadius
                color: isDragging
                  ? Qt.alpha(Color.accent, 0.25)
                  : ((wideTileHover.hovered && (!itemReady || root.editingMode)) ? Style.hoverFillFor(Color.foreground, Color.accent) : "transparent")
                borderSpec: root.editingMode
                  ? (isDragging || isDropTarget ? Border.controlSpec("hover", Color.accent, Color.accent) : Border.controlSpec("urgent", Color.urgent, Color.urgent))
                  : ((isDragging || isDropTarget || (!itemReady && wideTileHover.hovered)) ? Border.controlSpec("hover", Color.accent, Color.accent) : Border.none)

                scale: isDragging ? 1.04 : (isDropTarget ? 1.02 : 1.0)
                opacity: isDragging ? 0.35 : 1.0

                Behavior on scale {
                  NumberAnimation { duration: 120; easing.type: Easing.OutCubic }
                }
                Behavior on opacity {
                  NumberAnimation { duration: 120; easing.type: Easing.OutCubic }
                }
                Behavior on color {
                  ColorAnimation { duration: 120 }
                }

                Item {
                  id: wideContentWrapper
                  anchors.fill: parent
                  anchors.leftMargin: Style.space(8)
                  anchors.rightMargin: Style.space(8)
                  clip: false

                  Loader {
                    id: nativeWideWidgetLoader
                    anchors.centerIn: parent
                    active: !root.editingMode && registryEntry !== null
                    sourceComponent: registryEntry ? registryEntry.component : null

                    function syncProperties() {
                      var target = item
                      if (!target || !root.host) return
                      if ("bar" in target) {
                        var nextBar = firstParty ? root.host : root.host.pluginBarApiFor(childId, childId, true)
                        if (target.bar !== nextBar) target.bar = nextBar
                      }
                      if ("moduleName" in target && target.moduleName !== childId) target.moduleName = childId
                      var childSettings = DrawerModel.childSettings(childId, root.host ? root.host.shell.shellConfig : null)
                      if ("settings" in target) target.settings = childSettings
                    }

                    onLoaded: syncProperties()

                    Connections {
                      target: root
                      function onHostChanged() { nativeWideWidgetLoader.syncProperties() }
                      function onOpenedChanged() {
                        if (root.opened) nativeWideWidgetLoader.syncProperties()
                      }
                    }
                  }
                }

                // Fallback / Edit / Idle view for wide widget
                RowLayout {
                  visible: !itemReady || root.editingMode
                  anchors.fill: parent
                  anchors.leftMargin: Style.space(12)
                  anchors.rightMargin: Style.space(12)
                  spacing: Style.space(10)

                  Text {
                    visible: root.editingMode
                    text: "\uf0c9"
                    color: (isDragging || isDropTarget) ? Color.accent : Color.muted
                    font.family: Style.font.family
                    font.pixelSize: Style.font.caption
                  }

                  Text {
                    text: modelData.icon || "\uf001"
                    color: Color.accent
                    font.family: Style.font.family
                    font.pixelSize: Style.font.icon
                  }

                  Text {
                    text: modelData.name || modelData.id
                    color: Color.foreground
                    font.family: Style.font.family
                    font.pixelSize: Style.font.body
                    font.bold: true
                    elide: Text.ElideRight
                    Layout.fillWidth: true
                  }

                  Text {
                    visible: root.editingMode
                    text: "\uf00d"
                    color: Color.urgent || "#ff4455"
                    font.family: Style.font.family
                    font.pixelSize: Style.font.body
                    font.bold: true
                  }
                }
              }

              HoverHandler {
                id: wideTileHover
                enabled: root.editingMode || !itemReady
              }

              MouseArea {
                id: wideMouseArea
                anchors.fill: parent
                enabled: root.editingMode || !itemReady
                preventStealing: true
                cursorShape: dragging ? Qt.ClosedHandCursor : (root.editingMode ? Qt.SizeAllCursor : Qt.PointingHandCursor)

                property real pressX: 0
                property real pressY: 0
                property bool dragging: false
                property bool justDragged: false

                onPressed: function(mouse) {
                  pressX = mouse.x
                  pressY = mouse.y
                  dragging = false
                  justDragged = false
                }

                onPositionChanged: function(mouse) {
                  if (root.editingMode && (mouse.buttons & Qt.LeftButton)) {
                    var dist = Math.abs(mouse.x - pressX) + Math.abs(mouse.y - pressY)
                    if (!dragging && dist >= Style.space(6)) {
                      dragging = true
                      root.draggingWideIndex = index
                    }
                    if (dragging) {
                      var pt = mapToItem(wideWidgetsCol, mouse.x, mouse.y)
                      var targetItem = wideWidgetsCol.childAt(pt.x, pt.y)
                      if (targetItem && ("index" in targetItem) && targetItem.index !== undefined) {
                        root.dropTargetWideIndex = targetItem.index
                      } else {
                        root.dropTargetWideIndex = -1
                      }
                    }
                  }
                }

                onReleased: function(mouse) {
                  if (dragging) {
                    dragging = false
                    justDragged = true
                    if (root.dropTargetWideIndex >= 0 && root.dropTargetWideIndex !== root.draggingWideIndex) {
                      root.reorderWideItem(root.draggingWideIndex, root.dropTargetWideIndex)
                    }
                    root.resetDragState()
                  }
                }

                onCanceled: {
                  if (dragging) {
                    dragging = false
                    root.resetDragState()
                  }
                }

                onClicked: function(mouse) {
                  if (justDragged) {
                    justDragged = false
                    return
                  }
                  if (root.editingMode) {
                    root.restoreToBar(modelData.id)
                  } else {
                    root.launchPlugin(modelData.id)
                  }
                }
              }
            }
          }
        }
      }

      // ── ADD VIEW: SELECT WIDGETS FROM BAR ────────────────────────────────
      ColumnLayout {
        Layout.fillWidth: true
        visible: root.addingMode
        spacing: Style.space(6)

        Text {
          text: "Select a plugin to move into Drawer:"
          color: Color.muted
          font.family: Style.font.family
          font.pixelSize: Style.font.caption
          wrapMode: Text.WordWrap
          Layout.fillWidth: true
        }

        Flickable {
          Layout.fillWidth: true
          Layout.preferredHeight: Math.min(Style.space(280), barWidgetsCol.implicitHeight)
          contentHeight: barWidgetsCol.implicitHeight
          clip: true

          ColumnLayout {
            id: barWidgetsCol
            width: parent.width
            spacing: Style.space(4)

            Repeater {
              model: root.barWidgetsList

              delegate: BorderSurface {
                required property var modelData
                required property int index

                readonly property var meta: (root.discoveredMap && root.discoveredMap[modelData.id]) ? root.discoveredMap[modelData.id] : DrawerModel.resolveItemMetadata(modelData.id, null)

                Layout.fillWidth: true
                implicitHeight: Style.space(40)
                radius: Style.cornerRadius
                color: rowHover.containsMouse ? Style.hoverFillFor(Color.foreground, Color.accent) : "transparent"

                borderSpec: rowHover.containsMouse
                  ? Border.controlSpec("hover", Color.accent, Color.accent)
                  : Border.none

                MouseArea {
                  id: rowHover
                  anchors.fill: parent
                  hoverEnabled: true
                  cursorShape: Qt.PointingHandCursor
                  onClicked: root.hideFromBarAndReturn(modelData.id)
                }

                RowLayout {
                  anchors.fill: parent
                  anchors.leftMargin: Style.space(10)
                  anchors.rightMargin: Style.space(10)
                  spacing: Style.space(10)

                  Text {
                    text: meta.icon || "\uf013"
                    color: rowHover.containsMouse ? Color.accent : Color.foreground
                    font.family: Style.font.family
                    font.pixelSize: Style.font.icon
                    Layout.preferredWidth: Style.space(24)
                  }

                  Text {
                    text: meta.name || modelData.id
                    color: Color.foreground
                    font.family: Style.font.family
                    font.pixelSize: Style.font.body
                    font.bold: true
                    elide: Text.ElideRight
                    Layout.fillWidth: true
                  }

                  Text {
                    text: "\uf067"
                    color: rowHover.containsMouse ? Color.accent : Color.muted
                    font.family: Style.font.family
                    font.pixelSize: Style.font.caption
                  }
                }
              }
            }
          }
        }
      }
    }
  }
}
