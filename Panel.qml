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

  function reloadAllData() {
    loadDrawerConfigProc.running = false
    loadDrawerConfigProc.running = true
    listBarProc.running = false
    listBarProc.running = true
  }

  function launchPlugin(targetId) {
    if (!targetId) return
    var meta = (discoveredMap && discoveredMap[targetId]) ? discoveredMap[targetId] : DrawerModel.resolveItemMetadata(targetId, null)
    var ipcTarget = meta.ipcTarget || targetId

    // Try driving through mounted loader instances
    for (var i = 0; i < mountedLoadersRepeater.count; i++) {
      var loader = mountedLoadersRepeater.itemAt(i)
      if (loader && loader.modelData === targetId && loader.item) {
        if (typeof loader.item.toggle === "function") { loader.item.toggle() }
        else if (typeof loader.item.open === "function") { loader.item.open() }
        else if (typeof loader.item.show === "function") { loader.item.show() }
        else if (typeof loader.item.togglePanel === "function") { loader.item.togglePanel() }
      }
    }

    // Trigger IPC commands
    triggerProc.command = [
      "bash", "-c",
      "omarchy-shell " + ipcTarget + " toggle 2>/dev/null || omarchy-shell " + targetId + " toggle 2>/dev/null || omarchy-shell shell toggle " + targetId + " 2>/dev/null || omarchy-shell " + ipcTarget + " open 2>/dev/null || true"
    ]
    triggerProc.running = false
    triggerProc.running = true

    root.close()
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
          var meta = root.discoveredMap[modelData]
          var entry = (meta && meta.manifest && meta.manifest.entryPoints)
            ? (meta.manifest.entryPoints.barWidget || meta.manifest.entryPoints.panel || "BarWidget.qml")
            : "BarWidget.qml"
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
    }
  }

  // Bar Widget Icon Button
  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: "\uf187"
    active: root.opened
    tooltipText: root.opened ? "Close Drawer" : "Drawer (" + root.activeDrawerItems.length + " items)"
    onPressed: function(buttonCode) {
      root.toggle()
    }
  }

  // Floating Popup Panel Surface
  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(root.addingMode ? Style.space(340) : Math.max(Style.space(260), (Math.min(5, Math.max(3, root.activeDrawerItems.length)) * Style.space(56)) + Style.space(32)))
    contentHeight: panel.fittedContentHeight(mainColumn.implicitHeight, Style.space(480))

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onCloseRequested: {
        if (root.addingMode) {
          root.addingMode = false
        } else if (root.editingMode) {
          root.editingMode = false
        } else {
          root.close()
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
            text: "\uf187"
            color: Color.accent
            font.family: Style.font.family
            font.pixelSize: Style.font.title
          }

          Text {
            text: root.addingMode ? "Add to Drawer" : (root.editingMode ? "Edit" : (root.hoveredPluginName !== "" ? root.hoveredPluginName : "Drawer"))
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

          // Edit Mode Toggle Button (Square Edit \uf044 / Done \uf00c)
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

        // ── MAIN VIEW: UNIFIED DRAWER ICONS ──────────────────────────────────
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
            visible: root.activeDrawerItems.length > 0
            Layout.fillWidth: true
            spacing: Style.space(10)
            clip: false

            Repeater {
              model: root.activeDrawerItems

              delegate: Item {
                required property var modelData
                required property int index

                width: Style.space(48)
                height: Style.space(48)
                z: tileHover.containsMouse ? 100 : 1

                BorderSurface {
                  anchors.fill: parent
                  radius: Style.cornerRadius
                  color: tileHover.containsMouse ? Color.subtextBackground : "transparent"
                  borderSpec: root.editingMode
                    ? Border.controlSpec("urgent", Color.urgent, Color.urgent)
                    : (tileHover.containsMouse ? Border.controlSpec("hover", Color.accent, Color.accent) : Border.none)

                  Behavior on color {
                    ColorAnimation { duration: 120 }
                  }

                  Text {
                    anchors.centerIn: parent
                    text: modelData.icon || "\uf013"
                    color: tileHover.containsMouse ? Color.accent : Color.foreground
                    font.family: Style.font.family
                    font.pixelSize: Style.font.displayMedium
                    scale: tileHover.containsMouse ? 1.15 : 1.0

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
                  visible: root.editingMode
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
                  visible: !root.editingMode && tileHover.containsMouse
                  opacity: (!root.editingMode && tileHover.containsMouse) ? 1.0 : 0.0
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

                MouseArea {
                  id: tileHover
                  anchors.fill: parent
                  hoverEnabled: true
                  cursorShape: Qt.PointingHandCursor

                  onEntered: {
                    root.hoveredPluginName = modelData.name || modelData.id
                  }

                  onExited: {
                    if (root.hoveredPluginName === (modelData.name || modelData.id)) {
                      root.hoveredPluginName = ""
                    }
                  }

                  onClicked: {
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
}
