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

  // Path to backend helpers
  readonly property string helperBin: Quickshell.env("HOME") + "/.local/bin/drawer-helper"

  // State
  property var rawDrawerItemIds: []
  property var discoveredPlugins: []
  property var discoveredMap: ({})
  property var activeDrawerItems: DrawerModel.getActiveItemList(rawDrawerItemIds, discoveredMap)
  property var barWidgetsList: []
  property int currentTab: 0 // 0: Hidden Plugins (Drawer), 1: Active Bar Widgets

  function isItemInDrawer(id) {
    return rawDrawerItemIds.indexOf(id) !== -1
  }

  function reloadAllData() {
    loadDrawerConfigProc.running = false
    loadDrawerConfigProc.running = true
    listBarProc.running = false
    listBarProc.running = true
  }

  function launchPlugin(targetId) {
    if (!targetId) return
    var meta = (discoveredMap && discoveredMap[targetId]) ? discoveredMap[targetId] : DrawerModel.resolveItemMetadata(targetId, null)
    var target = meta.ipcTarget || targetId
    triggerProc.command = ["omarchy-shell", target, "toggle"]
    triggerProc.running = true
    root.close()
  }

  function hideFromBar(pluginId) {
    if (!pluginId) return
    barActionProc.command = [root.helperBin, "hide-from-bar", pluginId]
    barActionProc.running = true
  }

  function restoreToBar(pluginId) {
    if (!pluginId) return
    barActionProc.command = [root.helperBin, "restore-to-bar", pluginId]
    barActionProc.running = true
  }

  // CLI / Subprocess actions
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

  // Load bar widgets from shell.json
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

  // Load drawer items from ~/.config/omarchy/drawer.json
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
          root.rawDrawerItemIds = [
            "io.github.nobledoodle.omarchroma",
            "tiertek.tekscan",
            "io.github.rsd.omavnc",
            "io.github.brukb.omarchy-zerotier",
            "io.github.ricky.whatsapp"
          ]
        }
        root.activeDrawerItems = DrawerModel.getActiveItemList(root.rawDrawerItemIds, root.discoveredMap)
      }
    }
  }

  // Scan installed plugin manifests
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
    function add(pluginId: string): void { root.hideFromBar(pluginId) }
    function remove(pluginId: string): void { root.restoreToBar(pluginId) }
    function manage(): void { root.open(); root.currentTab = 1 }
  }

  onOpenedChanged: {
    if (opened) {
      root.reloadAllData()
    }
  }

  // Bar Widget Icon Button
  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: "\uf187"
    active: root.opened
    tooltipText: root.opened ? "Close Drawer" : "Omarchy Drawer (" + root.activeDrawerItems.length + " plugins)"
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
    contentWidth: panel.fittedContentWidth(Style.space(400))
    contentHeight: panel.fittedContentHeight(mainColumn.implicitHeight, Style.space(540))

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onCloseRequested: root.close()

      Keys.onPressed: function(event) {
        if (event.key >= Qt.Key_1 && event.key <= Qt.Key_9 && root.currentTab === 0) {
          var index = event.key - Qt.Key_1
          if (index >= 0 && index < root.activeDrawerItems.length) {
            root.launchPlugin(root.activeDrawerItems[index].id)
            event.accepted = true
          }
        }
      }

      ColumnLayout {
        id: mainColumn
        anchors.fill: parent
        spacing: Style.space(10)

        // Header
        RowLayout {
          Layout.fillWidth: true
          spacing: Style.space(8)

          Text {
            text: "\uf187"
            color: Color.accent
            font.family: Style.font.family
            font.pixelSize: Style.font.title
          }

          Text {
            text: "Omarchy Drawer"
            color: Color.foreground
            font.family: Style.font.family
            font.pixelSize: Style.font.title
            font.bold: true
            Layout.fillWidth: true
          }

          Button {
            iconText: "\uf021"
            tooltipText: "Refresh"
            onClicked: root.reloadAllData()
          }

          Button {
            iconText: "\uf00d"
            tooltipText: "Close (Esc)"
            onClicked: root.close()
          }
        }

        // Tabs
        RowLayout {
          Layout.fillWidth: true
          spacing: Style.space(6)

          Button {
            Layout.fillWidth: true
            text: "Drawer (" + root.activeDrawerItems.length + ")"
            iconText: "\uf07b"
            selected: root.currentTab === 0
            onClicked: root.currentTab = 0
          }

          Button {
            Layout.fillWidth: true
            text: "Bar Widgets (" + root.barWidgetsList.length + ")"
            iconText: "\uf0c9"
            selected: root.currentTab === 1
            onClicked: root.currentTab = 1
          }
        }

        PanelSeparator {
          Layout.fillWidth: true
        }

        // TAB 0: DRAWER ITEMS (Click to Launch, Quick 1..9, or Put back on bar)
        ColumnLayout {
          Layout.fillWidth: true
          visible: root.currentTab === 0
          spacing: Style.space(6)

          Text {
            text: root.activeDrawerItems.length > 0 ? "Click any plugin to open it, or press numbers 1..9:" : "No plugins in Drawer. Go to 'Bar Widgets' tab to hide widgets here."
            color: Color.subtext
            font.family: Style.font.family
            font.pixelSize: Style.font.caption
            wrapMode: Text.WordWrap
            Layout.fillWidth: true
          }

          Flickable {
            Layout.fillWidth: true
            Layout.preferredHeight: Math.min(Style.space(300), drawerCol.implicitHeight)
            contentHeight: drawerCol.implicitHeight
            clip: true

            ColumnLayout {
              id: drawerCol
              width: parent.width
              spacing: Style.space(6)

              Repeater {
                model: root.activeDrawerItems

                delegate: BorderSurface {
                  required property var modelData
                  required property int index

                  Layout.fillWidth: true
                  implicitHeight: Style.space(48)
                  radius: Style.cornerRadius
                  color: itemMouseArea.containsMouse ? Style.spaceFill : "transparent"

                  MouseArea {
                    id: itemMouseArea
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.launchPlugin(modelData.id)
                  }

                  RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: Style.space(8)
                    anchors.rightMargin: Style.space(8)
                    spacing: Style.space(8)

                    // Quick key badge
                    BorderSurface {
                      Layout.preferredWidth: Style.space(22)
                      Layout.preferredHeight: Style.space(22)
                      radius: 4
                      color: Color.subtextBackground

                      Text {
                        anchors.centerIn: parent
                        text: String(index + 1)
                        color: Color.accent
                        font.family: Style.font.family
                        font.pixelSize: Style.font.caption
                        font.bold: true
                      }
                    }

                    // Plugin Icon
                    Text {
                      text: modelData.icon || "\uf013"
                      color: itemMouseArea.containsMouse ? Color.accent : Color.foreground
                      font.family: Style.font.family
                      font.pixelSize: Style.font.title
                      Layout.preferredWidth: Style.space(24)
                    }

                    // Name & Description
                    ColumnLayout {
                      Layout.fillWidth: true
                      spacing: 1

                      Text {
                        text: modelData.name || modelData.id
                        color: Color.foreground
                        font.family: Style.font.family
                        font.pixelSize: Style.font.body
                        font.bold: true
                        elide: Text.ElideRight
                      }

                      Text {
                        text: modelData.description || modelData.id
                        color: Color.subtext
                        font.family: Style.font.family
                        font.pixelSize: Style.font.caption
                        elide: Text.ElideRight
                        visible: modelData.description !== ""
                      }
                    }

                    // Restore to bar button
                    Button {
                      iconText: "\uf06e"
                      tooltipText: "Restore directly back onto the top bar"
                      onClicked: root.restoreToBar(modelData.id)
                    }
                  }
                }
              }
            }
          }
        }

        // TAB 1: BAR WIDGETS (HIDE FROM BAR -> MOVE TO DRAWER)
        ColumnLayout {
          Layout.fillWidth: true
          visible: root.currentTab === 1
          spacing: Style.space(6)

          Text {
            text: "Click 'Hide from Bar' to remove an icon from the top bar and access it via Drawer:"
            color: Color.subtext
            font.family: Style.font.family
            font.pixelSize: Style.font.caption
            wrapMode: Text.WordWrap
            Layout.fillWidth: true
          }

          Flickable {
            Layout.fillWidth: true
            Layout.preferredHeight: Math.min(Style.space(300), barCol.implicitHeight)
            contentHeight: barCol.implicitHeight
            clip: true

            ColumnLayout {
              id: barCol
              width: parent.width
              spacing: Style.space(6)

              Repeater {
                model: root.barWidgetsList

                delegate: BorderSurface {
                  required property var modelData
                  required property int index

                  readonly property var meta: (root.discoveredMap && root.discoveredMap[modelData.id]) ? root.discoveredMap[modelData.id] : DrawerModel.resolveItemMetadata(modelData.id, null)
                  readonly property bool inDrawer: root.isItemInDrawer(modelData.id)

                  Layout.fillWidth: true
                  implicitHeight: Style.space(46)
                  radius: Style.cornerRadius
                  color: inDrawer ? Style.spaceFill : "transparent"

                  RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: Style.space(8)
                    anchors.rightMargin: Style.space(8)
                    spacing: Style.space(8)

                    Text {
                      text: meta.icon || "\uf013"
                      color: inDrawer ? Color.accent : Color.foreground
                      font.family: Style.font.family
                      font.pixelSize: Style.font.body
                      Layout.preferredWidth: Style.space(24)
                    }

                    ColumnLayout {
                      Layout.fillWidth: true
                      spacing: 1

                      Text {
                        text: meta.name || modelData.id
                        color: Color.foreground
                        font.family: Style.font.family
                        font.pixelSize: Style.font.body
                        font.bold: true
                        elide: Text.ElideRight
                      }

                      Text {
                        text: "Bar (" + (modelData.section || "right") + ")" + (meta.description ? " — " + meta.description : "")
                        color: Color.subtext
                        font.family: Style.font.family
                        font.pixelSize: Style.font.caption
                        elide: Text.ElideRight
                      }
                    }

                    Button {
                      text: "Hide from Bar"
                      iconText: "\uf070"
                      tooltipText: "Hide from top bar and place in Drawer"
                      onClicked: root.hideFromBar(modelData.id)
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
