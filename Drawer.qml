import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Wayland
import Quickshell.Widgets
import qs.Commons

// Stage Manager-style drawer. Touching the left screen edge slides in a
// panel with previews of every other open window (all workspaces, including
// windows hidden by show-desktop). Clicking one switches to it and makes it
// full width (or fullscreen, if you were already fullscreen). A "Back to
// tiles" button restores the tiled layout. Works over full-width and
// fullscreen windows too.
//
// Kept cheap for older hardware: the edge is an event-driven hover strip (no
// polling), and each preview is a single captured frame taken when the drawer
// opens (live: false). Previews are destroyed when the drawer closes.
Item {
  id: root

  // Injected by omarchy-shell.
  property var shell: null

  // The helper ships alongside this file, so the plugin works wherever it is
  // installed from. Qt.resolvedUrl gives a file:// URL; exec needs a path.
  readonly property string switchScript: {
    var u = Qt.resolvedUrl("stage-switch").toString()
    return u.indexOf("file://") === 0 ? u.substring(7) : u
  }
  readonly property int drawerWidth: 240
  readonly property int edgeWidth: 2
  // Leave the bottom of the edge free for the bottom-left hot corner.
  readonly property int edgeBottomGap: 80
  readonly property int openDelayMs: 120
  readonly property int closeDelayMs: 300

  function windowAddress(t) {
    var a = t && t.address ? String(t.address) : ""
    if (!a) return ""
    return a.indexOf("0x") === 0 ? a : "0x" + a
  }

  function switchTo(t) {
    var addr = root.windowAddress(t)
    if (addr) Quickshell.execDetached([root.switchScript, "window", addr])
  }

  function backToTiles() {
    Quickshell.execDetached([root.switchScript, "tiles"])
  }

  Variants {
    model: Quickshell.screens

    Scope {
      id: screenScope
      required property var modelData

      property bool opened: false
      // The tiles must outlive `opened`: it flips to false one step before the
      // slide-out animation starts, and binding the tiles to it empties the
      // card in that gap, so it collapses to a small box before it moves.
      // Set on open, cleared only once the slide has finished.
      property bool showTiles: false
      property var windows: []
      readonly property bool workspaceHasFullscreen: !!(Hyprland.focusedWorkspace && Hyprland.focusedWorkspace.hasFullscreen)

      function monitorName() {
        return screenScope.modelData ? screenScope.modelData.name : ""
      }

      function refreshWindows() {
        var current = Hyprland.focusedWorkspace
        var active = Hyprland.activeToplevel
        var activeAddr = root.windowAddress(active)
        var here = []
        var elsewhere = []
        var values = Hyprland.toplevels.values || []
        for (var i = 0; i < values.length; i++) {
          var t = values[i]
          if (!t || !t.wayland) continue
          // The window you're already in: clicking it would go nowhere.
          // Object identity alone proved unreliable, so accept any signal.
          if (t.activated) continue
          if (activeAddr && root.windowAddress(t) === activeAddr) continue
          if (ToplevelManager.activeToplevel && t.wayland === ToplevelManager.activeToplevel) continue
          if (current && t.workspace && t.workspace.id === current.id) here.push(t)
          else elsewhere.push(t)
        }
        screenScope.windows = here.concat(elsewhere)
      }

      function open() {
        if (Hyprland.focusedMonitor && Hyprland.focusedMonitor.name !== screenScope.monitorName()) return
        Hyprland.refreshToplevels()
        Hyprland.refreshWorkspaces()
        screenScope.refreshWindows()
        // Nothing to switch to and no layout to restore: don't show an empty drawer.
        if (screenScope.windows.length === 0 && !screenScope.workspaceHasFullscreen) return
        closeTimer.stop()
        screenScope.showTiles = true
        screenScope.opened = true
      }

      function close() {
        openTimer.stop()
        closeTimer.stop()
        screenScope.opened = false
      }

      Timer {
        id: openTimer
        interval: root.openDelayMs
        onTriggered: screenScope.open()
      }

      Timer {
        id: closeTimer
        interval: root.closeDelayMs
        onTriggered: {
          if (!edgeHover.hovered && !cardHover.hovered) screenScope.opened = false
        }
      }

      // ---- Invisible hover strip on the left edge.
      PanelWindow {
        id: edge
        screen: screenScope.modelData
        color: "transparent"
        anchors { left: true; top: true; bottom: true }
        margins.bottom: root.edgeBottomGap
        implicitWidth: root.edgeWidth
        exclusionMode: ExclusionMode.Ignore
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.namespace: "suzanne-stage-edge"
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

        Item {
          anchors.fill: parent

          HoverHandler {
            id: edgeHover
            onHoveredChanged: {
              if (hovered) {
                openTimer.restart()
              } else {
                openTimer.stop()
                if (screenScope.opened) closeTimer.restart()
              }
            }
          }
        }
      }

      // ---- The drawer itself.
      PanelWindow {
        id: drawer
        screen: screenScope.modelData
        // Stays mapped until the slide-out animation has finished, so the card
        // keeps its tiles (and its size) all the way off screen.
        visible: screenScope.opened || screenScope.showTiles
        color: "transparent"
        anchors { left: true; top: true; bottom: true }
        implicitWidth: root.drawerWidth + Style.gapsOut * 2
        exclusionMode: ExclusionMode.Ignore
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.namespace: "suzanne-stage-drawer"
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

        // Only the card takes input; the rest of the strip passes clicks through.
        mask: Region { item: card }

        Rectangle {
          id: card
          width: root.drawerWidth
          height: Math.min(parent.height - Style.gapsOut * 2, list.implicitHeight + Style.spacing.panelPadding * 2)
          anchors.verticalCenter: parent.verticalCenter
          x: screenScope.opened ? Style.gapsOut : -width - 4
          radius: Style.cornerRadius
          color: Color.menu.background
          border.color: Color.menu.border
          border.width: Math.max(1, Style.space(2))
          clip: true

          Behavior on x {
            NumberAnimation {
              duration: 180
              easing.type: Easing.OutCubic
              onRunningChanged: if (!running && !screenScope.opened) screenScope.showTiles = false
            }
          }

          HoverHandler {
            id: cardHover
            onHoveredChanged: {
              if (hovered) closeTimer.stop()
              else closeTimer.restart()
            }
          }

          Flickable {
            anchors.fill: parent
            anchors.margins: Style.spacing.panelPadding
            contentHeight: list.implicitHeight
            interactive: contentHeight > height
            clip: true

            Column {
              id: list
              width: parent.width
              spacing: Style.spacing.md

              // ---- Back to tiles: only when something here is full width/fullscreen.
              Rectangle {
                id: tilesButton
                visible: screenScope.workspaceHasFullscreen
                width: list.width
                height: tilesLabel.implicitHeight + Style.space(16)
                radius: Style.cornerRadius
                color: tilesMouse.containsMouse ? Color.menu.selectedBackground : "transparent"
                border.color: Color.menu.border
                border.width: 1

                Text {
                  id: tilesLabel
                  anchors.centerIn: parent
                  // U+F0615 (collapse arrows): "shrink back into tiles".
                  text: "\u{F0615}  Back to tiles"
                  color: tilesMouse.containsMouse ? Color.menu.selectedText : Color.menu.text
                  font.family: Style.font.menuFamily
                  font.pixelSize: Style.font.body
                  font.bold: true
                }

                MouseArea {
                  id: tilesMouse
                  anchors.fill: parent
                  hoverEnabled: true
                  cursorShape: Qt.PointingHandCursor
                  onClicked: {
                    root.backToTiles()
                    screenScope.close()
                  }
                }
              }

              Repeater {
                // Keep the tiles for the whole slide-out (drawer.visible stays
                // true until the card is off screen), or the card would shrink
                // to an empty box mid-animation. Previews are freed once the
                // window hides.
                model: screenScope.showTiles ? screenScope.windows : []

                delegate: Rectangle {
                  id: tile
                  required property var modelData

                  width: list.width
                  height: tileColumn.implicitHeight + Style.space(12)
                  radius: Style.cornerRadius
                  color: tileMouse.containsMouse ? Color.menu.selectedBackground : "transparent"

                  Column {
                    id: tileColumn
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.top: parent.top
                    anchors.margins: Style.space(6)
                    spacing: Style.space(6)

                    Rectangle {
                      width: parent.width
                      height: preview.hasContent && preview.sourceSize.width > 0
                        ? Math.min(width * preview.sourceSize.height / preview.sourceSize.width, width * 1.2)
                        : width * 0.6
                      radius: Math.max(0, Style.cornerRadius - 2)
                      color: Qt.rgba(0, 0, 0, 0.25)
                      clip: true

                      ScreencopyView {
                        id: preview
                        anchors.fill: parent
                        captureSource: tile.modelData.wayland
                        live: false
                        paintCursor: false
                        constraintSize: Qt.size(root.drawerWidth * 2, root.drawerWidth * 2)
                      }
                    }

                    Row {
                      width: parent.width
                      spacing: Style.space(6)

                      IconImage {
                        id: appIcon
                        implicitSize: 16
                        anchors.verticalCenter: parent.verticalCenter
                        source: {
                          var id = tile.modelData.wayland ? tile.modelData.wayland.appId : ""
                          var entry = id ? DesktopEntries.heuristicLookup(id) : null
                          return Quickshell.iconPath(entry && entry.icon ? entry.icon : id, "application-x-executable")
                        }
                      }

                      Text {
                        width: parent.width - appIcon.width - parent.spacing
                        anchors.verticalCenter: parent.verticalCenter
                        text: tile.modelData.title || (tile.modelData.wayland ? tile.modelData.wayland.appId : "")
                        elide: Text.ElideRight
                        color: tileMouse.containsMouse ? Color.menu.selectedText : Color.menu.text
                        font.family: Style.font.menuFamily
                        font.pixelSize: Style.font.body
                      }
                    }
                  }

                  MouseArea {
                    id: tileMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                      root.switchTo(tile.modelData)
                      screenScope.close()
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
