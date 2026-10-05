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
    function add(pluginId: string): void { root.hideFromBar(pluginId) }
    function remove(pluginId: string): void { root.restoreToBar(pluginId) }
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
    contentWidth: panel.fittedContentWidth(Style.space(360))
    contentHeight: panel.fittedContentHeight(mainColumn.implicitHeight, Style.space(500))

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onCloseRequested: root.close()

      ColumnLayout {
        id: mainColumn
        anchors.fill: parent
        spacing: Style.space(12)

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

        PanelSeparator {
          Layout.fillWidth: true
        }

        // SECCIÓN 1: EN DRAWER (OCULTOS)
        ColumnLayout {
          Layout.fillWidth: true
          spacing: Style.space(6)

          RowLayout {
            Layout.fillWidth: true
            spacing: Style.space(6)

            Text {
              text: "En Drawer (" + root.activeDrawerItems.length + ")"
              color: Color.accent
              font.family: Style.font.family
              font.pixelSize: Style.font.body
              font.bold: true
              Layout.fillWidth: true
            }

            Text {
              text: "Clic para devolver a la barra"
              color: Color.subtext
              font.family: Style.font.family
              font.pixelSize: Style.font.caption
            }
          }

          // Empty state when no items are hidden
          BorderSurface {
            visible: root.activeDrawerItems.length === 0
            Layout.fillWidth: true
            implicitHeight: Style.space(48)
            radius: Style.cornerRadius
            color: Style.spaceFill

            Text {
              anchors.centerIn: parent
              text: "Ningún plugin oculto. Haz clic abajo para mover aquí."
              color: Color.subtext
              font.family: Style.font.family
              font.pixelSize: Style.font.caption
            }
          }

          // Grid of Drawer Icons
          Flow {
            visible: root.activeDrawerItems.length > 0
            Layout.fillWidth: true
            spacing: Style.space(6)

            Repeater {
              model: root.activeDrawerItems

              delegate: BorderSurface {
                required property var modelData
                required property int index

                width: Style.space(46)
                height: Style.space(46)
                radius: Style.cornerRadius
                color: drawerHover.containsMouse ? Color.subtextBackground : Style.spaceFill

                borderSpec: drawerHover.containsMouse
                  ? Border.controlSpec("hover", Color.accent, Color.accent)
                  : Border.controlSpec("normal", Color.foreground, Color.accent)

                Behavior on color {
                  ColorAnimation { duration: 120 }
                }

                Text {
                  anchors.centerIn: parent
                  text: modelData.icon || "\uf013"
                  color: Color.accent
                  font.family: Style.font.family
                  font.pixelSize: Style.font.displayMedium
                  scale: drawerHover.containsMouse ? 1.15 : 1.0

                  Behavior on scale {
                    NumberAnimation { duration: 120; easing.type: Easing.OutCubic }
                  }
                }

                MouseArea {
                  id: drawerHover
                  anchors.fill: parent
                  hoverEnabled: true
                  cursorShape: Qt.PointingHandCursor
                  acceptedButtons: Qt.LeftButton | Qt.RightButton

                  onEntered: {
                    if (root.bar) {
                      root.bar.showTooltip(drawerHover, (modelData.name || modelData.id) + " — Clic: mover a barra | Clic der: abrir")
                    }
                  }

                  onExited: {
                    if (root.bar) {
                      root.bar.hideTooltip(drawerHover)
                    }
                  }

                  onClicked: function(mouse) {
                    if (root.bar) root.bar.hideTooltip(drawerHover)
                    if (mouse.button === Qt.RightButton) {
                      root.launchPlugin(modelData.id)
                    } else {
                      root.restoreToBar(modelData.id)
                    }
                  }
                }
              }
            }
          }
        }

        PanelSeparator {
          Layout.fillWidth: true
        }

        // SECCIÓN 2: EN BARRA (ACTIVOS EN LA BARRA SUPERIOR)
        ColumnLayout {
          Layout.fillWidth: true
          spacing: Style.space(6)

          RowLayout {
            Layout.fillWidth: true
            spacing: Style.space(6)

            Text {
              text: "En Barra (" + root.barWidgetsList.length + ")"
              color: Color.foreground
              font.family: Style.font.family
              font.pixelSize: Style.font.body
              font.bold: true
              Layout.fillWidth: true
            }

            Text {
              text: "Clic para ocultar y mover al Drawer"
              color: Color.subtext
              font.family: Style.font.family
              font.pixelSize: Style.font.caption
            }
          }

          Flow {
            Layout.fillWidth: true
            spacing: Style.space(6)

            Repeater {
              model: root.barWidgetsList

              delegate: BorderSurface {
                required property var modelData
                required property int index

                readonly property var meta: (root.discoveredMap && root.discoveredMap[modelData.id]) ? root.discoveredMap[modelData.id] : DrawerModel.resolveItemMetadata(modelData.id, null)

                width: Style.space(46)
                height: Style.space(46)
                radius: Style.cornerRadius
                color: barItemHover.containsMouse ? Style.spaceFill : "transparent"

                borderSpec: barItemHover.containsMouse
                  ? Border.controlSpec("hover", Color.accent, Color.accent)
                  : Border.controlSpec("normal", Color.foreground, Color.accent)

                Behavior on color {
                  ColorAnimation { duration: 120 }
                }

                Text {
                  anchors.centerIn: parent
                  text: meta.icon || "\uf013"
                  color: barItemHover.containsMouse ? Color.accent : Color.foreground
                  font.family: Style.font.family
                  font.pixelSize: Style.font.icon
                  scale: barItemHover.containsMouse ? 1.15 : 1.0

                  Behavior on scale {
                    NumberAnimation { duration: 120; easing.type: Easing.OutCubic }
                  }
                }

                MouseArea {
                  id: barItemHover
                  anchors.fill: parent
                  hoverEnabled: true
                  cursorShape: Qt.PointingHandCursor

                  onEntered: {
                    if (root.bar) {
                      root.bar.showTooltip(barItemHover, (meta.name || modelData.id) + " — Clic para ocultar en Drawer")
                    }
                  }

                  onExited: {
                    if (root.bar) {
                      root.bar.hideTooltip(barItemHover)
                    }
                  }

                  onClicked: {
                    if (root.bar) root.bar.hideTooltip(barItemHover)
                    root.hideFromBar(modelData.id)
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
