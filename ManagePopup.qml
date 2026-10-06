import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "DrawerModel.js" as DrawerModel

PopupCard {
  id: root

  property var hostWidget: null
  property var discoveredPlugins: []
  property var activeItemIds: []
  property var barItems: []
  property string triggerModeSetting: "hover"
  property string displayModeSetting: "inline-drawer"
  property bool dimInactiveSetting: true
  property int currentTab: 0 // 0: Bar Widgets, 1: Drawer Content, 2: Settings

  readonly property string helperPath: Quickshell.env("HOME") + "/.config/omarchy/plugins/evcode.drawer/bin/drawer-helper"

  signal settingsChanged()

  contentWidth: fittedContentWidth(Style.space(420))
  contentHeight: fittedContentHeight(mainColumn.implicitHeight, Style.space(560))

  function isItemActive(id) {
    return activeItemIds.indexOf(id) !== -1
  }

  function isItemOnBar(id) {
    for (var i = 0; i < barItems.length; i++) {
      if (barItems[i].id === id) return true
    }
    return false
  }

  function refreshBarItems() {
    listBarProc.running = true
  }

  function toggleItem(id) {
    var list = activeItemIds.slice(0)
    var idx = list.indexOf(id)
    if (idx !== -1) {
      list.splice(idx, 1)
    } else {
      list.push(id)
    }
    activeItemIds = list
    root.saveConfiguration()
  }

  function hideFromBar(id) {
    barActionProc.command = [root.helperPath, "hide-from-bar", id]
    barActionProc.running = true
  }

  function restoreToBar(id) {
    barActionProc.command = [root.helperPath, "restore-to-bar", id]
    barActionProc.running = true
  }

  function moveItem(id, delta) {
    var list = activeItemIds.slice(0)
    var idx = list.indexOf(id)
    if (idx === -1) return
    var targetIdx = idx + delta
    if (targetIdx < 0 || targetIdx >= list.length) return
    var item = list.splice(idx, 1)[0]
    list.splice(targetIdx, 0, item)
    activeItemIds = list
    root.saveConfiguration()
  }

  function saveConfiguration() {
    if (hostWidget && typeof hostWidget.updateConfig === "function") {
      hostWidget.updateConfig({
        trigger: triggerModeSetting,
        mode: displayModeSetting,
        dimInactive: dimInactiveSetting,
        items: activeItemIds
      })
    }
    root.settingsChanged()
  }

  onOpenChanged: {
    if (open) {
      root.refreshBarItems()
    }
  }

  Process {
    id: listBarProc
    running: false
    command: [root.helperPath, "list-bar-items"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var items = DrawerModel.parseJsonSafe(text, [])
        root.barItems = items
      }
    }
  }

  Process {
    id: barActionProc
    running: false
    onRunningChanged: {
      if (!running) {
        root.refreshBarItems()
        if (hostWidget && typeof hostWidget.reloadFromDisk === "function") {
          hostWidget.reloadFromDisk()
        }
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
        text: "❖"
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
        iconText: "\uf00d"
        tooltipText: "Close"
        onClicked: root.close()
      }
    }

    // Tabs Selector
    RowLayout {
      Layout.fillWidth: true
      spacing: Style.space(6)

      Button {
        Layout.fillWidth: true
        text: "Bar Widgets"
        iconText: "\uf0c9"
        selected: root.currentTab === 0
        onClicked: root.currentTab = 0
      }

      Button {
        Layout.fillWidth: true
        text: "Drawer (" + root.activeItemIds.length + ")"
        iconText: "\uf07b"
        selected: root.currentTab === 1
        onClicked: root.currentTab = 1
      }

      Button {
        Layout.fillWidth: true
        text: "Settings"
        iconText: "\uf013"
        selected: root.currentTab === 2
        onClicked: root.currentTab = 2
      }
    }

    PanelSeparator {
      Layout.fillWidth: true
    }

    // TAB 0: BAR WIDGETS (HIDE FROM BAR -> MOVE TO DRAWER)
    ColumnLayout {
      Layout.fillWidth: true
      visible: root.currentTab === 0
      spacing: Style.space(8)

      Text {
        text: "Select any widget on your top bar to hide it and show it inside the Drawer:"
        color: Color.muted
        font.family: Style.font.family
        font.pixelSize: Style.font.caption
        wrapMode: Text.WordWrap
        Layout.fillWidth: true
      }

      Flickable {
        Layout.fillWidth: true
        Layout.preferredHeight: Math.min(Style.space(260), barWidgetsCol.implicitHeight)
        contentHeight: barWidgetsCol.implicitHeight
        clip: true

        ColumnLayout {
          id: barWidgetsCol
          width: parent.width
          spacing: Style.space(6)

          Repeater {
            model: root.barItems

            delegate: BorderSurface {
              required property var modelData
              required property int index

              readonly property var meta: DrawerModel.resolveItemMetadata(modelData.id, null)
              readonly property bool inDrawer: root.isItemActive(modelData.id)

              Layout.fillWidth: true
              implicitHeight: Style.space(44)
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
                    text: "Section: " + (modelData.section || "bar") + (meta.description ? " — " + meta.description : "")
                    color: Color.muted
                    font.family: Style.font.family
                    font.pixelSize: Style.font.caption
                    elide: Text.ElideRight
                  }
                }

                // Action Button: Hide from Bar & Move to Drawer
                Button {
                  text: "Hide from Bar"
                  iconText: "\uf070"
                  tooltipText: "Hide this icon from the top bar and access it via Drawer"
                  onClicked: root.hideFromBar(modelData.id)
                }
              }
            }
          }
        }
      }
    }

    // TAB 1: DRAWER ITEMS (REORDER & RESTORE TO BAR)
    ColumnLayout {
      Layout.fillWidth: true
      visible: root.currentTab === 1
      spacing: Style.space(8)

      Text {
        text: "Plugins currently inside your Drawer. You can reorder them or restore them to the top bar:"
        color: Color.muted
        font.family: Style.font.family
        font.pixelSize: Style.font.caption
        wrapMode: Text.WordWrap
        Layout.fillWidth: true
      }

      Flickable {
        Layout.fillWidth: true
        Layout.preferredHeight: Math.min(Style.space(260), drawerListCol.implicitHeight)
        contentHeight: drawerListCol.implicitHeight
        clip: true

        ColumnLayout {
          id: drawerListCol
          width: parent.width
          spacing: Style.space(6)

          Repeater {
            model: root.activeItemIds

            delegate: BorderSurface {
              required property var modelData
              required property int index

              readonly property var meta: DrawerModel.resolveItemMetadata(modelData, null)

              Layout.fillWidth: true
              implicitHeight: Style.space(44)
              radius: Style.cornerRadius
              color: Style.spaceFill

              RowLayout {
                anchors.fill: parent
                anchors.leftMargin: Style.space(8)
                anchors.rightMargin: Style.space(8)
                spacing: Style.space(8)

                Text {
                  text: meta.icon || "\uf013"
                  color: Color.accent
                  font.family: Style.font.family
                  font.pixelSize: Style.font.body
                  Layout.preferredWidth: Style.space(24)
                }

                ColumnLayout {
                  Layout.fillWidth: true
                  spacing: 1

                  Text {
                    text: meta.name || modelData
                    color: Color.foreground
                    font.family: Style.font.family
                    font.pixelSize: Style.font.body
                    font.bold: true
                    elide: Text.ElideRight
                  }

                  Text {
                    text: meta.description || modelData
                    color: Color.muted
                    font.family: Style.font.family
                    font.pixelSize: Style.font.caption
                    elide: Text.ElideRight
                    visible: meta.description !== ""
                  }
                }

                // Reorder buttons
                Row {
                  spacing: Style.space(2)

                  Button {
                    iconText: "\uf077"
                    tooltipText: "Move Up"
                    onClicked: root.moveItem(modelData, -1)
                  }

                  Button {
                    iconText: "\uf078"
                    tooltipText: "Move Down"
                    onClicked: root.moveItem(modelData, 1)
                  }
                }

                // Restore to Bar button
                Button {
                  text: "Put on Bar"
                  iconText: "\uf06e"
                  tooltipText: "Restore this widget directly onto the top bar"
                  onClicked: root.restoreToBar(modelData)
                }
              }
            }
          }
        }
      }
    }

    // TAB 2: PREFERENCES
    ColumnLayout {
      Layout.fillWidth: true
      visible: root.currentTab === 2
      spacing: Style.space(8)

      Toggle {
        Layout.fillWidth: true
        label: "Trigger on Hover"
        description: "Slide open automatically when mouse is over the drawer"
        checked: root.triggerModeSetting === "hover"
        onClicked: {
          root.triggerModeSetting = (root.triggerModeSetting === "hover" ? "click" : "hover")
          root.saveConfiguration()
        }
      }

      Toggle {
        Layout.fillWidth: true
        label: "Floating Mini-Dock Style"
        description: "Display as a floating panel popup with 1..9 keyboard numbers"
        checked: root.displayModeSetting === "popover-dock"
        onClicked: {
          root.displayModeSetting = (root.displayModeSetting === "popover-dock" ? "inline-drawer" : "popover-dock")
          root.saveConfiguration()
        }
      }

      Toggle {
        Layout.fillWidth: true
        label: "Dim Inactive Icons"
        description: "Slightly fade icons in drawer until hovered"
        checked: root.dimInactiveSetting
        onClicked: {
          root.dimInactiveSetting = !root.dimInactiveSetting
          root.saveConfiguration()
        }
      }
    }
  }
}
