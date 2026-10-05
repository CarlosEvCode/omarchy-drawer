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
  property bool manageMode: false

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
    function manage(): void { root.open(); root.manageMode = true }
  }

  onOpenedChanged: {
    if (opened) {
      root.reloadAllData()
    } else {
      root.manageMode = false
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
      if (buttonCode === Qt.RightButton) {
        root.open()
        root.manageMode = true
      } else {
        root.toggle()
      }
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
    contentWidth: panel.fittedContentWidth(root.manageMode ? Style.space(380) : Math.max(Style.space(220), (Math.min(5, Math.max(3, root.activeDrawerItems.length)) * Style.space(56)) + Style.space(32)))
    contentHeight: panel.fittedContentHeight(mainColumn.implicitHeight, Style.space(520))

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onCloseRequested: root.close()

      ColumnLayout {
        id: mainColumn
        anchors.fill: parent
        spacing: Style.space(8)

        // Header Bar
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
            text: root.manageMode ? "Gestionar Barra" : "Drawer"
            color: Color.foreground
            font.family: Style.font.family
            font.pixelSize: Style.font.title
            font.bold: true
            Layout.fillWidth: true
          }

          // Manage Toggle Button (Gear)
          Button {
            iconText: root.manageMode ? "\uf00a" : "\uf013"
            tooltipText: root.manageMode ? "Ver Cuadrícula de Iconos" : "Ocultar / Mostrar Widgets de la Barra"
            selected: root.manageMode
            onClicked: root.manageMode = !root.manageMode
          }

          Button {
            iconText: "\uf00d"
            tooltipText: "Cerrar (Esc)"
            onClicked: root.close()
          }
        }

        PanelSeparator {
          Layout.fillWidth: true
        }

        // VIEW 1: CLEAN ICON GRID (NO NAMES, NO NUMBERS)
        ColumnLayout {
          Layout.fillWidth: true
          visible: !root.manageMode
          spacing: Style.space(8)

          // Empty state if no plugins are hidden
          BorderSurface {
            visible: root.activeDrawerItems.length === 0
            Layout.fillWidth: true
            implicitHeight: Style.space(80)
            radius: Style.cornerRadius
            color: Style.spaceFill

            ColumnLayout {
              anchors.centerIn: parent
              spacing: Style.space(4)

              Text {
                text: "No hay plugins en el Drawer"
                color: Color.foreground
                font.family: Style.font.family
                font.pixelSize: Style.font.body
                font.bold: true
                Layout.alignment: Qt.AlignHCenter
              }

              Button {
                text: "Ocultar widgets de la barra"
                iconText: "\uf013"
                Layout.alignment: Qt.AlignHCenter
                onClicked: root.manageMode = true
              }
            }
          }

          // The Grid of Icon Tiles
          Item {
            visible: root.activeDrawerItems.length > 0
            Layout.alignment: Qt.AlignHCenter
            implicitWidth: iconGrid.implicitWidth
            implicitHeight: iconGrid.implicitHeight

            Grid {
              id: iconGrid
              columns: Math.min(5, Math.max(3, root.activeDrawerItems.length))
              spacing: Style.space(8)

              Repeater {
                model: root.activeDrawerItems

                delegate: BorderSurface {
                  required property var modelData
                  required property int index

                  width: Style.space(52)
                  height: Style.space(52)
                  radius: Style.cornerRadius
                  color: tileHover.containsMouse ? Style.spaceFill : Color.subtextBackground

                  borderSpec: tileHover.containsMouse
                    ? Border.controlSpec("hover", Color.accent, Color.accent)
                    : Border.controlSpec("normal", Color.foreground, Color.accent)

                  Behavior on color {
                    ColorAnimation { duration: 140 }
                  }

                  Text {
                    anchors.centerIn: parent
                    text: modelData.icon || "\uf013"
                    color: tileHover.containsMouse ? Color.accent : Color.foreground
                    font.family: Style.font.family
                    font.pixelSize: Style.font.displayMedium
                    scale: tileHover.containsMouse ? 1.12 : 1.0

                    Behavior on scale {
                      NumberAnimation { duration: 140; easing.type: Easing.OutCubic }
                    }
                  }

                  MouseArea {
                    id: tileHover
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    acceptedButtons: Qt.LeftButton | Qt.RightButton

                    onEntered: {
                      if (root.bar) {
                        root.bar.showTooltip(tileHover, modelData.name || modelData.id)
                      }
                    }

                    onExited: {
                      if (root.bar) {
                        root.bar.hideTooltip(tileHover)
                      }
                    }

                    onClicked: function(mouse) {
                      if (root.bar) root.bar.hideTooltip(tileHover)
                      if (mouse.button === Qt.RightButton) {
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
        }

        // VIEW 2: MANAGE VIEW (HIDE / RESTORE PLUGINS)
        ColumnLayout {
          Layout.fillWidth: true
          visible: root.manageMode
          spacing: Style.space(6)

          Text {
            text: "Oculta iconos de tu barra para que aparezcan en la cuadrícula del Drawer:"
            color: Color.subtext
            font.family: Style.font.family
            font.pixelSize: Style.font.caption
            wrapMode: Text.WordWrap
            Layout.fillWidth: true
          }

          Flickable {
            Layout.fillWidth: true
            Layout.preferredHeight: Math.min(Style.space(320), barListCol.implicitHeight)
            contentHeight: barListCol.implicitHeight
            clip: true

            ColumnLayout {
              id: barListCol
              width: parent.width
              spacing: Style.space(4)

              // Plugins currently on the bar
              Repeater {
                model: root.barWidgetsList

                delegate: BorderSurface {
                  required property var modelData
                  required property int index

                  readonly property var meta: (root.discoveredMap && root.discoveredMap[modelData.id]) ? root.discoveredMap[modelData.id] : DrawerModel.resolveItemMetadata(modelData.id, null)

                  Layout.fillWidth: true
                  implicitHeight: Style.space(40)
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
                      tooltipText: "Ocultar de la barra y pasar a la cuadrícula del Drawer"
                      onClicked: root.hideFromBar(modelData.id)
                    }
                  }
                }
              }

              // Plugins in Drawer (to restore)
              Repeater {
                model: root.activeDrawerItems

                delegate: BorderSurface {
                  required property var modelData
                  required property int index

                  Layout.fillWidth: true
                  implicitHeight: Style.space(40)
                  radius: Style.cornerRadius
                  color: Style.spaceFill

                  RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: Style.space(8)
                    anchors.rightMargin: Style.space(8)
                    spacing: Style.space(8)

                    Text {
                      text: modelData.icon || "\uf013"
                      color: Color.accent
                      font.family: Style.font.family
                      font.pixelSize: Style.font.icon
                      Layout.preferredWidth: Style.space(24)
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

                    Button {
                      text: "Mostrar"
                      iconText: "\uf06e"
                      tooltipText: "Restaurar a la barra fija"
                      onClicked: root.restoreToBar(modelData.id)
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
