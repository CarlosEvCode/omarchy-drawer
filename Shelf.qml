import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Wayland
import qs.Commons
import qs.Ui
import "DrawerModel.js" as Model

// Layer-shell window that shows a drawer's widgets as a second strip beside
// the bar.
//
// The window deliberately spans from the screen edge across the bar. Most
// widget panels are KeyboardPanels, which place themselves using the height
// (or width) of their anchor's window as "the bar", so a child's panel then
// opens beyond this strip instead of on top of it. Everything but the card is
// masked out, so the bar underneath stays clickable.
PanelWindow {
  id: shelf

  property var host: null
  property Item anchorItem: null
  property bool open: false
  // True while one of the drawer's children has its own panel open; that
  // panel takes pointer focus, which must not read as an outside click.
  property bool suspendDismiss: false
  property bool clickDismiss: true
  property real contentWidth: 0
  property real contentHeight: 0
  property int gap: Style.gapsOut
  property int margin: Style.gapsOut
  property int padding: Style.spacing.sm
  property var borderSpec: Border.surfaceSpec("popups", "border", Color.popups.border, Math.max(1, Style.space(2)))

  readonly property bool containsMouse: cardHover.hovered
  readonly property var barWindow: anchorItem ? anchorItem.QsWindow.window : null
  readonly property string barPos: host ? String(host.position || "top") : "top"
  readonly property bool vertical: barPos === "left" || barPos === "right"
  readonly property real barExtent: barWindow ? (vertical ? barWindow.width : barWindow.height) : 0
  readonly property real cardWidth: Math.ceil(contentWidth + card.contentLeftInset + card.contentRightInset)
  readonly property real cardHeight: Math.ceil(contentHeight + card.contentTopInset + card.contentBottomInset)

  signal dismissed()

  default property alias content: contentHolder.children

  screen: barWindow ? barWindow.screen : null
  visible: open || card.opacity > 0
  color: "transparent"
  exclusionMode: ExclusionMode.Ignore

  WlrLayershell.namespace: "omarchy-bar-drawer"
  WlrLayershell.layer: WlrLayer.Top
  WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

  anchors {
    top: barPos === "top" || vertical
    bottom: barPos === "bottom" || vertical
    left: barPos === "left" || !vertical
    right: barPos === "right" || !vertical
  }

  implicitWidth: vertical ? Math.max(1, barExtent + gap + cardWidth) : 0
  implicitHeight: vertical ? 0 : Math.max(1, barExtent + gap + cardHeight)

  mask: Region { item: card }

  function ownsTarget(target) {
    return !!target && Model.isDescendant(target, contentHolder)
  }

  HyprlandFocusGrab {
    active: shelf.open && shelf.clickDismiss && !shelf.suspendDismiss
    windows: shelf.barWindow ? [shelf, shelf.barWindow] : [shelf]
    onCleared: if (!shelf.suspendDismiss) shelf.dismissed()
  }

  // mapToItem is a one-shot; the watcher makes the card follow the button
  // when neighbouring widgets resize.
  TransformWatcher {
    id: anchorWatcher
    a: shelf.barWindow ? shelf.barWindow.contentItem : null
    b: shelf.anchorItem
  }

  readonly property point anchorPos: {
    anchorWatcher.transform
    if (!anchorItem || !barWindow) return Qt.point(0, 0)
    return anchorItem.mapToItem(barWindow.contentItem, 0, 0)
  }

  BorderSurface {
    id: card

    width: shelf.cardWidth
    height: shelf.cardHeight
    x: {
      if (shelf.barPos === "left") return shelf.barExtent + shelf.gap
      if (shelf.barPos === "right") return 0
      var centred = shelf.anchorPos.x + (shelf.anchorItem ? shelf.anchorItem.width : 0) / 2 - width / 2
      return Math.round(Model.clamp(centred, shelf.margin, Math.max(shelf.margin, shelf.width - width - shelf.margin)))
    }
    y: {
      if (shelf.barPos === "top") return shelf.barExtent + shelf.gap
      if (shelf.barPos === "bottom") return 0
      var centred = shelf.anchorPos.y + (shelf.anchorItem ? shelf.anchorItem.height : 0) / 2 - height / 2
      return Math.round(Model.clamp(centred, shelf.margin, Math.max(shelf.margin, shelf.height - height - shelf.margin)))
    }
    color: Color.popups.background
    borderSpec: shelf.borderSpec
    padding: shelf.padding
    radius: Style.cornerRadius
    opacity: shelf.open ? 1 : 0

    Behavior on opacity {
      NumberAnimation { duration: 140; easing.type: Easing.OutCubic }
    }

    HoverHandler { id: cardHover }

    Item {
      id: contentHolder
      // Hidden children fail the bar's clickability check, so a closed
      // shelf can never swallow a click meant for the bar.
      visible: shelf.open || card.opacity > 0
      anchors.fill: parent
      anchors.topMargin: card.contentTopInset
      anchors.rightMargin: card.contentRightInset
      anchors.bottomMargin: card.contentBottomInset
      anchors.leftMargin: card.contentLeftInset
    }
  }

  // The bar only draws tooltips for targets in its own window, so children
  // living here get theirs from this copy of the bar's tooltip state.
  PopupWindow {
    id: tooltipWindow

    readonly property var target: shelf.host ? shelf.host.tooltipTarget : null
    readonly property string text: shelf.host ? String(shelf.host.tooltipText || "") : ""

    visible: shelf.open && !!shelf.host && shelf.host.tooltipShown === true
      && text !== "" && shelf.ownsTarget(target)
    color: "transparent"
    implicitWidth: Math.ceil(bubble.implicitWidth)
    implicitHeight: Math.ceil(bubble.implicitHeight)

    onTargetChanged: if (visible) anchor.updateAnchor()
    onVisibleChanged: if (visible) anchor.updateAnchor()

    anchor {
      window: shelf
      adjustment: PopupAdjustment.Slide
      edges: Edges.Top | Edges.Left
      gravity: Edges.Bottom | Edges.Right
      rect.width: 1
      rect.height: 1

      onAnchoring: {
        var target = tooltipWindow.target
        if (!target || !shelf.contentItem) return
        var gapPx = Style.space(4)
        var point = target.mapToItem(shelf.contentItem, 0, 0)
        var x = point.x + target.width / 2 - tooltipWindow.implicitWidth / 2
        var y = point.y + target.height + gapPx
        if (shelf.barPos === "bottom") y = point.y - tooltipWindow.implicitHeight - gapPx
        if (shelf.barPos === "left") {
          x = point.x + target.width + gapPx
          y = point.y + target.height / 2 - tooltipWindow.implicitHeight / 2
        } else if (shelf.barPos === "right") {
          x = point.x - tooltipWindow.implicitWidth - gapPx
          y = point.y + target.height / 2 - tooltipWindow.implicitHeight / 2
        }
        tooltipWindow.anchor.rect.x = Math.round(x)
        tooltipWindow.anchor.rect.y = Math.round(y)
      }
    }

    Rectangle {
      id: bubble
      anchors.fill: parent
      implicitWidth: tooltipLabel.implicitWidth + Style.spacing.lg * 2
      implicitHeight: tooltipLabel.implicitHeight + Style.spacing.sm * 2
      color: Color.tooltip.background
      border.color: Color.tooltip.border
      border.width: 1
      radius: Style.cornerRadius

      Text {
        id: tooltipLabel
        anchors.centerIn: parent
        text: tooltipWindow.text
        color: Color.tooltip.text
        font.family: shelf.host ? shelf.host.fontFamily : Style.font.family
        font.pixelSize: Style.font.body
        textFormat: Text.PlainText
      }
    }
  }
}
