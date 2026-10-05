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

  // Scan installed plugin manifests for accurate icons and names
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
    tooltipText: root.opened ? "Cerrar Drawer" : "Omarchy Drawer (" + root.activeDrawerItems.length + " ocultos)"
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
    contentWidth: panel.fittedContentWidth(Style.space(380))
    contentHeight: panel.fittedContentHeight(mainColumn.implicitHeight, Style.space(520))

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
            tooltipText: "Actualizar"
            onClicked: root.reloadAllData()
          }

          Button {
            iconText: "\uf00d"
            tooltipText: "Cerrar (Esc)"
            onClicked: root.close()
          }
        }

        // Tabs
        RowLayout {
          Layout.fillWidth: true
          spacing: Style.space(6)

          Button {
            Layout.fillWidth: true
            text: "Ocultos (" + root.activeDrawerItems.length + ")"
            iconText: "\uf07b"
            selected: root.currentTab === 0
            onClicked: root.currentTab = 0
          }

          Button {
            Layout.fillWidth: true
            text: "En Barra (" + root.barWidgetsList.length + ")"
            iconText: "\uf0c9"
            selected: root.currentTab === 1
            onClicked: root.currentTab = 1
          }
        }

        PanelSeparator {
          Layout.fillWidth: true
        }

        // TAB 0: PLUGINS OCULTOS (DRAWER)
        ColumnLayout {
          Layout.fillWidth: true
          visible: root.currentTab === 0
          spacing: Style.space(6)

          // Empty state if no plugins are hidden
          BorderSurface {
            visible: root.activeDrawerItems.length === 0
            Layout.fillWidth: true
            implicitHeight: Style.space(70)
            radius: Style.cornerRadius
            color: Style.spaceFill

            ColumnLayout {
              anchors.centerIn: parent
              spacing: Style.space(4)

              Text {
                text: "No hay plugins ocultos"
                color: Color.foreground
                font.family: Style.font.family
                font.pixelSize: Style.font.body
                font.bold: true
                Layout.alignment: Qt.AlignHCenter
              }

              Text {
                text: "Ve a la pestaña 'En Barra' para ocultar plugins aquí."
                color: Color.subtext
                font.family: Style.font.family
                font.pixelSize: Style.font.caption
                Layout.alignment: Qt.AlignHCenter
              }
            }
          }

          Flickable {
            visible: root.activeDrawerItems.length > 0
            Layout.fillWidth: true
            Layout.preferredHeight: Math.min(Style.space(320), drawerCol.implicitHeight)
            contentHeight: drawerCol.implicitHeight
            clip: true

            ColumnLayout {
              id: drawerCol
              width: parent.width
              spacing: Style.space(4)

              Repeater {
                model: root.activeDrawerItems

                delegate: BorderSurface {
                  required property var modelData
                  required property int index

                  Layout.fillWidth: true
                  implicitHeight: Style.space(42)
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

                    // Quick key badge (1..9)
                    BorderSurface {
                      Layout.preferredWidth: Style.space(20)
                      Layout.preferredHeight: Style.space(20)
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
                      font.pixelSize: Style.font.icon
                      Layout.preferredWidth: Style.space(24)
                    }

                    // Name ONLY (Clean, no description)
                    Text {
                      text: modelData.name || modelData.id
                      color: Color.foreground
                      font.family: Style.font.family
                      font.pixelSize: Style.font.body
                      font.bold: true
                      elide: Text.ElideRight
                      Layout.fillWidth: true
                    }

                    // Restore to bar button
                    Button {
                      iconText: "\uf06e"
                      text: "Mostrar"
                      tooltipText: "Restaurar a la barra fija"
                      onClicked: root.restoreToBar(modelData.id)
                    }
                  }
                }
              }
            }
          }
        }

        // TAB 1: PLUGINS EN LA BARRA (SOLO LOS QUE ESTÁN EN LA BARRA ACTUALMENTE)
        ColumnLayout {
          Layout.fillWidth: true
          visible: root.currentTab === 1
          spacing: Style.space(6)

          Flickable {
            Layout.fillWidth: true
            Layout.preferredHeight: Math.min(Style.space(320), barCol.implicitHeight)
            contentHeight: barCol.implicitHeight
            clip: true

            ColumnLayout {
              id: barCol
              width: parent.width
              spacing: Style.space(4)

              Repeater {
                model: root.barWidgetsList

                delegate: BorderSurface {
                  required property var modelData
                  required property int index

                  readonly property var meta: (root.discoveredMap && root.discoveredMap[modelData.id]) ? root.discoveredMap[modelData.id] : DrawerModel.resolveItemMetadata(modelData.id, null)

                  Layout.fillWidth: true
                  implicitHeight: Style.space(42)
                  radius: Style.cornerRadius
                  color: "transparent"

                  RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: Style.space(8)
                    anchors.rightMargin: Style.space(8)
                    spacing: Style.space(8)

                    Text {
                      text: meta.icon || "\uf013"
                      color: Color.foreground
                      font.family: Style.font.family
                      font.pixelSize: Style.font.icon
                      Layout.preferredWidth: Style.space(24)
                    }

                    // Name ONLY (Clean, no description)
                    Text {
                      text: meta.name || modelData.id
                      color: Color.foreground
                      font.family: Style.font.family
                      font.pixelSize: Style.font.body
                      font.bold: true
                      elide: Text.ElideRight
                      Layout.fillWidth: true
                    }

                    Button {
                      text: "Ocultar"
                      iconText: "\uf070"
                      tooltipText: "Ocultar de la barra y pasar al Drawer"
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
