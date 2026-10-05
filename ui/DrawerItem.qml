import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

WidgetButton {
  id: root

  property var itemData: null
  property bool dimInactive: true
  readonly property string itemId: itemData ? itemData.id : ""
  readonly property string itemIcon: itemData ? (itemData.icon || "\uf013") : "\uf013"
  readonly property string itemName: itemData ? itemData.name : ""
  readonly property string itemDesc: itemData ? itemData.description : ""
  readonly property string ipcTarget: itemData ? (itemData.ipcTarget || itemData.id) : ""

  text: root.itemIcon
  tooltipText: itemName + (itemDesc ? " — " + itemDesc : "")
  hasVisualContent: true
  labelVisible: true
  fontSize: Style.bar.iconFont
  fixedWidth: Style.bar.iconSlot
  fixedHeight: Style.bar.iconSlot

  Process {
    id: triggerProc
    running: false
  }

  function activatePlugin(action) {
    var target = ipcTarget || itemId
    if (!target) return
    triggerProc.command = ["omarchy-shell", target, action || "toggle"]
    triggerProc.running = true
  }

  onPressed: function(btn) {
    if (btn === Qt.RightButton) {
      root.activatePlugin("open")
    } else {
      root.activatePlugin("toggle")
    }
  }
}
