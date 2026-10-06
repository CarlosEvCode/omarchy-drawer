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

  property bool focusPrimed: false

  Timer {
    id: focusPrimeTimer
    interval: 50
    onTriggered: shelf.focusPrimed = true
  }

  function beginFocusPrime() {
    focusPrimed = false
    if (open && backingWindowVisible) focusPrimeTimer.restart()
  }

  onOpenChanged: {
    if (open) beginFocusPrime()
    else focusPrimed = false
  }

  onBackingWindowVisibleChanged: beginFocusPrime()

  WlrLayershell.namespace: "evcode-drawer"
  WlrLayershell.layer: WlrLayer.Top
  WlrLayershell.keyboardFocus: open
    ? (focusPrimed ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.Exclusive)
    : WlrKeyboardFocus.None

  anchors {
    top: barPos === "top" || vertical
    bottom: barPos === "bottom" || vertical
    left: barPos === "left" || !vertical
    right: barPos === "right" || !vertical
  }

  implicitWidth: vertical ? Math.max(1, barExtent + gap + cardWidth) : 0
  implicitHeight: vertical ? 0 : Math.max(1, barExtent + gap + cardHeight)

  mask: Region { item: card }

  property var tileDropTarget: null
  property int tileDragIndex: -1
  property point tileDragPoint: Qt.point(0, 0)
  property var tileDragItem: null

  function ownsTarget(target) {
    return !!target && Model.isDescendant(target, contentHolder)
  }

  HyprlandFocusGrab {
    active: shelf.open && shelf.clickDismiss && !shelf.suspendDismiss && shelf.tileDragIndex < 0
    windows: shelf.barWindow ? [shelf, shelf.barWindow] : [shelf]
    onCleared: if (!shelf.suspendDismiss && shelf.tileDragIndex < 0) shelf.dismissed()
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

  // Insertion marker drawn over the bar while a tile is dragged onto it
  Rectangle {
    readonly property var target: shelf.tileDropTarget
    readonly property point at: target && target.kind === "bar"
      ? shelf.mapFromItem(null, target.x, target.y) : Qt.point(0, 0)
    visible: shelf.tileDragIndex >= 0 && !!target && target.kind === "bar"
    z: 10000
    color: Color.accent
    width: target && target.vertical ? target.length : Math.max(2, Style.space(2))
    height: target && target.vertical ? Math.max(2, Style.space(2)) : (target ? target.length : 0)
    x: target && target.vertical ? at.x : at.x - width / 2
    y: target && target.vertical ? at.y - height / 2 : at.y
    radius: 1
  }

  // Drag ghost floating under cursor
  Rectangle {
    readonly property point at: shelf.tileDragPoint
    readonly property var item: shelf.tileDragItem
    readonly property bool leaving: !!shelf.tileDropTarget && shelf.tileDropTarget.kind !== "compactTile" && shelf.tileDropTarget.kind !== "wideTile"
    visible: shelf.tileDragIndex >= 0 && !!item
    z: 10001
    x: at.x + Style.space(14)
    y: at.y + Style.space(18)
    width: ghostRow.implicitWidth + Style.space(16)
    height: Style.space(34)
    radius: Style.cornerRadius
    color: Color.popups.background
    border.width: Math.max(1, Style.space(1))
    border.color: Color.accent
    opacity: 0.95

    Row {
      id: ghostRow
      anchors.centerIn: parent
      spacing: Style.space(8)

      Text {
        anchors.verticalCenter: parent.verticalCenter
        text: {
          if (!item) return "\udb81\udc31"
          if (item.glyph) return item.glyph
          if (item.icon && item.icon !== "\uf013") return item.icon
          var meta = Model.resolveItemMetadata(item.id || item, null)
          return (meta && meta.icon) ? meta.icon : "\udb81\udc31"
        }
        textFormat: Text.PlainText
        color: Color.accent
        font.family: shelf.host ? shelf.host.fontFamily : Style.font.family
        font.pixelSize: Style.font.iconLarge
      }

      Text {
        anchors.verticalCenter: parent.verticalCenter
        text: {
          if (!item) return ""
          var name = item.name || item.id
          if (!leaving) return name
          return shelf.tileDropTarget && shelf.tileDropTarget.kind === "bar" ? (name + "  →  bar") : (name + "  →  restore")
        }
        textFormat: Text.PlainText
        color: Color.popups.text || Color.foreground
        font.family: shelf.host ? shelf.host.fontFamily : Style.font.family
        font.pixelSize: Style.font.bodySmall
        font.bold: true
      }
    }
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
