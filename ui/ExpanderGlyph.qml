import QtQuick
import Quickshell
import qs.Commons
import qs.Ui

WidgetButton {
  id: root

  property bool expanded: false
  property bool isHoverTrigger: true

  // Standard bar button properties
  labelVisible: true
  text: root.expanded ? "\uf054" : "\uf053"
  hasVisualContent: true
  fontSize: Style.bar.iconFont
  fixedWidth: Style.bar.iconSlot
  fixedHeight: Style.bar.iconSlot
  active: root.expanded
  tooltipText: root.expanded ? "Drawer (Collapse, Right-click to manage)" : "Drawer (Expand, Right-click to manage)"

  signal toggleRequested()
  signal manageRequested()

  onPressed: function(buttonCode) {
    if (buttonCode === Qt.RightButton) {
      root.manageRequested()
    } else {
      root.toggleRequested()
    }
  }
}
