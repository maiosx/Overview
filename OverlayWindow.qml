import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.Commons
import qs.Ui
import "js/Format.js" as Format

PanelWindow {
  id: win
  property var host: null

  visible: host && host.opened
  anchors { top: true; bottom: true; left: true; right: true }
  color: "transparent"
  WlrLayershell.namespace: "overview"
  WlrLayershell.layer: WlrLayer.Overlay
  WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
  exclusionMode: ExclusionMode.Ignore

  Rectangle {
    anchors.fill: parent
    color: host ? Qt.rgba(host.background.r, host.background.g, host.background.b, 0.94) : "#101014"
    visible: host && !host.pinned
  }

  Item {
    id: stage
    anchors.fill: parent
    visible: host && !host.pinned
    focus: host && host.cinema
    Keys.onPressed: function(event) {
      if (host && host.cinema) {
        host.exitCinema()
        event.accepted = true
      }
    }

    HeroPane {
      id: hero
      anchors.top: parent.top
      anchors.left: parent.left
      anchors.right: parent.right
      cinema: host ? host.cinema : false
      shownThumb: host ? host.shownThumb : ""
      pendingThumb: host ? host.pendingThumb : ""
      heroKind: host ? host.heroKind : ""
      previewResult: host ? host.previewResult : ({})
      previewLoading: host ? host.previewLoading : false
      opened: host ? host.opened : false
      pinned: host ? host.pinned : false
      foreground: host ? host.foreground : "white"
      accent: host ? host.accent : "#8ab4f8"
      background: host ? host.background : "#101014"
      heroTitle: host ? host.heroTitle : ""
      locationLabel: host ? host.locationLabel : ""
      locFlash: host ? host.locFlash : ""
      onCommitRequested: function(path) { if (host) host.commitHero(path) }
      onCopyLocation: { if (host) host.copyLocation() }
    }

    Rectangle {
      id: searchBar
      anchors.top: parent.top
      anchors.horizontalCenter: parent.horizontalCenter
      anchors.topMargin: 22
      width: Math.min(parent.width - 72, 720)
      height: 44
      radius: 22
      color: Qt.rgba(0, 0, 0, 0.55)
      border.width: 1
      border.color: (host && searchField.activeFocus) ? host.accent : Qt.rgba(1, 1, 1, 0.16)
      visible: host && !host.cinema
      z: 4

      Text {
        anchors.fill: parent
        leftPadding: 20
        rightPadding: 20
        text: "Search files"
        visible: searchField.text.length === 0
        color: Qt.rgba(1, 1, 1, 0.38)
        font.pixelSize: 15
        verticalAlignment: Text.AlignVCenter
        elide: Text.ElideRight
        textFormat: Text.PlainText
      }
      TextInput {
        id: searchField
        anchors.fill: parent
        leftPadding: 20
        rightPadding: 20
        topPadding: 0
        bottomPadding: 0
        verticalAlignment: TextInput.AlignVCenter
        color: "white"
        font.pixelSize: 15
        clip: true
        selectByMouse: true
        focus: true
        Keys.priority: Keys.BeforeItem
        Keys.onPressed: function(event) {
          if (!host) return
          if (host.cinema) {
            host.exitCinema()
            event.accepted = true
            return
          }
          host.bumpIdle()
          if (event.key === Qt.Key_Escape) {
            if (host.pinned) host.pinned = false
            else host.close()
            event.accepted = true
          } else if (event.key === Qt.Key_Down) { host.moveSelection(0, 1); event.accepted = true }
          else if (event.key === Qt.Key_Up) { host.moveSelection(0, -1); event.accepted = true }
          else if (event.key === Qt.Key_Right && cursorPosition === text.length && selectedText.length === 0) { host.moveSelection(1, 0); event.accepted = true }
          else if (event.key === Qt.Key_Left && cursorPosition === 0 && selectedText.length === 0) { host.moveSelection(-1, 0); event.accepted = true }
          else if (event.key === Qt.Key_Space) { host.pinToggle(); event.accepted = true }
          else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) { host.openCurrent(); event.accepted = true }
        }
        onTextChanged: {
          if (!host) return
          host.bumpIdle()
          host.queryText = text
          host.kickDebounce()
        }
      }
    }

    GridView {
      id: grid
      anchors.top: hero.bottom
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.bottom: parent.bottom
      anchors.leftMargin: 28
      anchors.rightMargin: 28
      anchors.topMargin: 8
      anchors.bottomMargin: 28
      visible: host && !host.cinema
      clip: true
      cellWidth: Math.floor(width / 3)
      cellHeight: Math.round(cellWidth * 0.78)
      model: host ? host.results : []
      currentIndex: host ? host.selectedIndex : 0
      boundsBehavior: Flickable.StopAtBounds
      delegate: Item {
        required property int index
        required property var modelData
        width: grid.cellWidth
        height: grid.cellHeight
        FileCard {
          anchors.fill: parent
          anchors.margins: 10
          hit: modelData
          selected: host && index === host.selectedIndex
          foreground: host ? host.foreground : "white"
          accent: host ? host.accent : "#8ab4f8"
          homePrefix: host ? host.homePrefix : ""
          onActivated: { host.bumpIdle(); host.selectIndex(index) }
          onOpened: { host.bumpIdle(); host.selectIndex(index); host.openCurrent() }
        }
      }
    }

    Text {
      anchors.centerIn: grid
      visible: host && host.results.length === 0 && host.queryText.length > 0 && !host.cinema
      text: "no matches"
      textFormat: Text.PlainText
      color: host ? host.foreground : "white"
      opacity: 0.45
      font.pixelSize: Style.font.title
      z: 2
    }

    Text {
      anchors.bottom: parent.bottom
      anchors.horizontalCenter: parent.horizontalCenter
      anchors.bottomMargin: 10
      text: host ? Format.displayText(host.diskLabel) : ""
      visible: host && host.diskLabel.length > 0 && !host.cinema
      color: host ? host.foreground : "white"
      opacity: 0.4
      font.pixelSize: Style.font.caption
      textFormat: Text.PlainText
    }

    MouseArea {
      anchors.fill: parent
      visible: host && host.cinema
      z: 20
      hoverEnabled: true
      property bool armed: false
      property real lx: -1
      property real ly: -1
      onVisibleChanged: {
        armed = false
        lx = -1
        ly = -1
        if (visible) armTimer.restart()
      }
      Timer {
        id: armTimer
        interval: 600
        repeat: false
        onTriggered: parent.armed = true
      }
      onClicked: { if (host) host.exitCinema() }
      onPositionChanged: function(mouse) {
        if (!armed || !host) return
        if (lx < 0) { lx = mouse.x; ly = mouse.y; return }
        if (Math.abs(mouse.x - lx) < 18 && Math.abs(mouse.y - ly) < 18) return
        host.exitCinema()
      }
    }
  }

  Rectangle {
    id: pinnedPane
    anchors.fill: parent
    visible: host && host.pinned
    color: host ? Qt.rgba(host.background.r, host.background.g, host.background.b, 1) : "#101014"
    focus: host && host.pinned
    Keys.onPressed: function(event) {
      if (!host) return
      if (event.key === Qt.Key_Escape || event.key === Qt.Key_Space) { host.pinToggle(); event.accepted = true }
      else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) { host.revealCurrent(); event.accepted = true }
    }
    PreviewPane {
      anchors.fill: parent
      anchors.margins: 36
      preview: host ? host.previewResult : ({})
      loading: host ? host.previewLoading : false
      foreground: host ? host.foreground : "white"
      accent: host ? host.accent : "#8ab4f8"
      selectable: true
      autoplay: host && host.pinned
    }
    Text {
      anchors.bottom: parent.bottom
      anchors.horizontalCenter: parent.horizontalCenter
      anchors.bottomMargin: 16
      width: parent.width * 0.8
      text: host ? Format.displayText(host.locFlash.length ? host.locFlash : host.locationLabel) : ""
      color: host && host.locFlash.length ? host.accent : (host ? host.foreground : "white")
      opacity: host && host.locFlash.length ? 1 : 0.55
      font.pixelSize: Style.font.caption
      elide: Text.ElideMiddle
      horizontalAlignment: Text.AlignHCenter
      textFormat: Text.PlainText
      MouseArea {
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: { if (host) host.copyLocation() }
      }
    }
  }

  function focusSearch() { searchField.forceActiveFocus() }
  function clearSearch() { searchField.text = "" }
  function focusPinned() { pinnedPane.forceActiveFocus() }
  function focusStage() { stage.forceActiveFocus() }
  function stopPan() { hero.stopPan() }
  function startPanSoon() { hero.startPanSoon() }
}
