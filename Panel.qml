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

  readonly property string helperBin: Quickshell.env("HOME") + "/.local/bin/drawer-helper"

  // State
  property var rawDrawerItemIds: []
  property var discoveredPlugins: []
  property var discoveredMap: ({})
  property var activeDrawerItems: DrawerModel.getActiveItemList(rawDrawerItemIds, discoveredMap)
  property var barWidgetsList: []
  property bool addingMode: false
  property bool editingMode: false
  property string hoveredPluginName: ""

  property bool barDropActive: false
  property bool cardDropActive: false
  property int draggingIndex: -1
  property int dropTargetIndex: -1

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

  function reloadAllData() {
    loadDrawerConfigProc.running = false
    loadDrawerConfigProc.running = true
    listBarProc.running = false
    listBarProc.running = true
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

  function launchPlugin(targetId) {
    if (!targetId) return
    var meta = (discoveredMap && discoveredMap[targetId]) ? discoveredMap[targetId] : DrawerModel.resolveItemMetadata(targetId, null)
    var ipcTarget = meta.ipcTarget || targetId

    // 1. Close drawer panel first so focus handoff is clean
    root.close()

    // 2. Open target plugin smoothly after drawer close
    Qt.callLater(function() {
      if (targetId === "tiertek.tekscan" || ipcTarget === "tekscan") {
        triggerProc.command = ["bash", "-c", "omarchy-shell tekscan toggle 2>/dev/null || omarchy-shell tekscan show 2>/dev/null || true"]
        triggerProc.running = false
        triggerProc.running = true
        return
      }

      var handled = false
      for (var i = 0; i < mountedLoadersRepeater.count; i++) {
        var loader = mountedLoadersRepeater.itemAt(i)
        if (loader && loader.modelData === targetId && loader.item) {
          if (typeof loader.item.open === "function") {
            loader.item.open()
            handled = true
          } else if (typeof loader.item.show === "function") {
            loader.item.show()
            handled = true
          } else if (typeof loader.item.toggle === "function") {
            loader.item.toggle()
            handled = true
          } else if (typeof loader.item.togglePanel === "function") {
            loader.item.togglePanel()
            handled = true
          } else if (loader.item.controller && typeof loader.item.controller.show === "function") {
            loader.item.controller.show()
            handled = true
          }
          break
        }
      }

      if (!handled) {
        triggerProc.command = [
          "bash", "-c",
          "omarchy-shell " + ipcTarget + " open 2>/dev/null || omarchy-shell " + ipcTarget + " show 2>/dev/null || omarchy-shell " + ipcTarget + " toggle 2>/dev/null || omarchy-shell " + targetId + " open 2>/dev/null || omarchy-shell " + targetId + " toggle 2>/dev/null || true"
        ]
        triggerProc.running = false
        triggerProc.running = true
      }
    })
  }

  function hideFromBarAndReturn(pluginId) {
    if (!pluginId) return
    barActionProc.command = [root.helperBin, "hide-from-bar", pluginId]
    barActionProc.running = true
    root.addingMode = false
  }

  function restoreToBar(pluginId) {
    if (!pluginId) return
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
  }

  Component.onCompleted: {
    Qt.callLater(resolveHost)
  }

  Connections {
    target: root.host
    ignoreUnknownSignals: true
    function onActivePopoutChanged() {
      if (!root.opened || !root.host) return
      var active = root.host.activePopout
      if (active === root || active === null) return
      if (root.ownsPopout(active)) {
        // Child opened popout, keep alive
        return
      }
    }
  }

  // Load hidden plugins eagerly in background so their IPC and panels exist
  Item {
    id: mountedPluginsHolder
    visible: false
    Repeater {
      id: mountedLoadersRepeater
      model: root.rawDrawerItemIds
      delegate: Loader {
        required property string modelData
        active: true
        source: {
          var userPath = Quickshell.env("HOME") + "/.config/omarchy/plugins/" + modelData + "/"
          var meta = (root.discoveredMap && root.discoveredMap[modelData]) ? root.discoveredMap[modelData] : DrawerModel.resolveItemMetadata(modelData, null)
          var entry = meta.entryPoint || "Panel.qml"
          return Qt.resolvedUrl(userPath + entry)
        }
        onLoaded: {
          if (item) {
            if ("bar" in item) item.bar = root.bar
            if ("anchorItem" in item) item.anchorItem = button
          }
        }
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

  // Load bar widgets strictly from shell.json
  Process {
    id: listBarProc
    running: true
    command: [root.helperBin, "list-bar-items"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var items = DrawerModel.parseJsonSafe(text, [])
        root.barWidgetsList = items
      }
    }
  }

  // Load drawer items strictly from ~/.config/omarchy/drawer.json
  Process {
    id: loadDrawerConfigProc
    running: true
    command: ["bash", "-c", "[ -f ~/.config/omarchy/drawer.json ] && cat ~/.config/omarchy/drawer.json || echo '{\"items\":[]}'"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var cfg = DrawerModel.parseJsonSafe(text, null)
        if (cfg && cfg.items && Array.isArray(cfg.items)) {
          root.rawDrawerItemIds = cfg.items
        } else {
          root.rawDrawerItemIds = []
        }
        root.activeDrawerItems = DrawerModel.getActiveItemList(root.rawDrawerItemIds, root.discoveredMap)
      }
    }
  }

  // Scan manifests for proper names and icons
  Process {
    id: scanManifestsProc
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
        for (var k in DrawerModel.KNOWN_PLUGINS_MAP) {
          if (!map[k]) {
            var kMeta = DrawerModel.KNOWN_PLUGINS_MAP[k]
            map[k] = kMeta
            list.push(kMeta)
          }
        }
        root.discoveredMap = map
        root.discoveredPlugins = list
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
  }

  onOpenedChanged: {
    if (opened) {
      root.reloadAllData()
      root.addingMode = false
      root.editingMode = false
      root.hoveredPluginName = ""
      root.draggingIndex = -1
      root.dropTargetIndex = -1
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
    text: root.barDropActive ? "\uf0120" : "\uf187"
    active: root.opened || root.barDropActive
    tooltipText: root.opened ? "Close Drawer" : (root.barDropActive ? "Drop here to open" : "Drawer (" + root.activeDrawerItems.length + " items)")
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
    contentWidth: root.addingMode ? Style.space(340) : Math.max(Style.space(260), (Math.min(5, Math.max(3, root.activeDrawerItems.length)) * Style.space(56)) + Style.space(32))
    contentHeight: mainColumn.implicitHeight
    onDismissed: {
      if (!root.childPopoutOpen) root.close()
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
      spacing: Style.space(12)

      // HEADER
      RowLayout {
        Layout.fillWidth: true
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
          text: root.cardDropActive ? "Drop here" : (root.addingMode ? "Add to Drawer" : (root.editingMode ? "Edit (Drag to reorder)" : (root.hoveredPluginName !== "" ? root.hoveredPluginName : "Drawer")))
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

        Button {
          iconText: "\uf00d"
          tooltipText: "Close (Esc)"
          onClicked: root.close()
        }
      }

      PanelSeparator {
        Layout.fillWidth: true
      }

      // ── MAIN VIEW: UNIFIED DRAWER ICONS WITH NATIVE WIDGET HOSTING & DRAG-REORDER ──
      ColumnLayout {
        Layout.fillWidth: true
        visible: !root.addingMode
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

        // Icon Grid
        Flow {
          id: itemsGrid
          visible: root.activeDrawerItems.length > 0
          Layout.fillWidth: true
          spacing: Style.space(10)
          clip: false

          Repeater {
            id: itemsRepeater
            model: root.activeDrawerItems

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

              readonly property bool isDragging: root.draggingIndex === index
              readonly property bool isDropTarget: root.dropTargetIndex === index && root.draggingIndex !== index

              readonly property Item activeItem: nativeWidgetLoader.item

              width: Style.space(48)
              height: Style.space(48)
              z: isDragging ? 1000 : (tileHover.hovered ? 100 : 1)

              Component.onCompleted: root.registerChild(itemDelegate)
              Component.onDestruction: root.unregisterChild(itemDelegate)

              BorderSurface {
                anchors.fill: parent
                radius: Style.cornerRadius
                color: isDragging ? Qt.alpha(Color.accent, 0.25) : (tileHover.hovered ? Color.subtextBackground : "transparent")
                borderSpec: root.editingMode
                  ? Border.controlSpec("urgent", Color.urgent, Color.urgent)
                  : (isDropTarget || tileHover.hovered ? Border.controlSpec("hover", Color.accent, Color.accent) : Border.none)

                scale: isDragging ? 1.15 : (isDropTarget ? 1.08 : 1.0)

                Behavior on scale {
                  NumberAnimation { duration: 100; easing.type: Easing.OutCubic }
                }
                Behavior on color {
                  ColorAnimation { duration: 120 }
                }

                Loader {
                  id: nativeWidgetLoader
                  anchors.centerIn: parent
                  active: !root.editingMode && registryEntry !== null
                  sourceComponent: registryEntry ? registryEntry.component : null
                  onLoaded: {
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
                }

                Text {
                  visible: root.editingMode || nativeWidgetLoader.status !== Loader.Ready || !nativeWidgetLoader.item
                  anchors.centerIn: parent
                  text: modelData.icon || "\uf013"
                  color: (isDragging || tileHover.hovered || isDropTarget) ? Color.accent : Color.foreground
                  font.family: Style.font.family
                  font.pixelSize: Style.font.displayMedium
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
                cursorShape: root.editingMode ? Qt.SizeAllCursor : Qt.PointingHandCursor

                property real pressX: 0
                property real pressY: 0
                property bool hasMoved: false

                onPressed: function(mouse) {
                  pressX = mouse.x
                  pressY = mouse.y
                  hasMoved = false
                }

                onPositionChanged: function(mouse) {
                  if (mouse.buttons & Qt.LeftButton) {
                    var dist = Math.abs(mouse.x - pressX) + Math.abs(mouse.y - pressY)
                    if (dist > 8) {
                      hasMoved = true
                      root.draggingIndex = index

                      var globalPos = mapToItem(itemsGrid, mouse.x, mouse.y)
                      var child = itemsGrid.childAt(globalPos.x, globalPos.y)
                      if (child && child !== itemDelegate) {
                        for (var k = 0; k < itemsRepeater.count; k++) {
                          if (itemsRepeater.itemAt(k) === child) {
                            root.dropTargetIndex = k
                            break
                          }
                        }
                      }
                    }
                  }
                }

                onReleased: function(mouse) {
                  if (hasMoved && root.draggingIndex >= 0 && root.dropTargetIndex >= 0) {
                    root.reorderItem(root.draggingIndex, root.dropTargetIndex)
                  }
                  root.draggingIndex = -1
                  root.dropTargetIndex = -1
                  hasMoved = false
                }

                onCanceled: {
                  root.draggingIndex = -1
                  root.dropTargetIndex = -1
                  hasMoved = false
                }

                onClicked: {
                  if (hasMoved) return
                  if (root.editingMode) {
                    root.restoreToBar(modelData.id)
                  } else if (!nativeWidgetLoader.item) {
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
          color: Color.subtext
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
                color: rowHover.containsMouse ? Color.subtextBackground : "transparent"

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
                    color: rowHover.containsMouse ? Color.accent : Color.subtext
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
