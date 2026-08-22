import QtQuick
import qs.Commons
import qs.Ui
import "js/Format.js" as Format

Item {
  id: hero
  property bool cinema: false
  property string shownThumb: ""
  property string pendingThumb: ""
  property string heroKind: ""
  property var previewResult: ({})
  property bool previewLoading: false
  property bool opened: false
  property bool pinned: false
  property color foreground: "white"
  property color accent: "#8ab4f8"
  property color background: "#101014"
  property string heroTitle: ""
  property string locationLabel: ""
  property string locFlash: ""
  readonly property bool heroImage: shownThumb.length > 0
  signal commitRequested(string path)
  signal copyLocation()

  function stopPan() {
    heroPan.stop()
    heroImg.y = 0
  }
  function startPanSoon() {
    panIdle.restart()
  }

  height: cinema ? parent.height : Math.round(parent.height * 0.42)
  z: cinema ? 6 : 0
  Behavior on height { NumberAnimation { duration: 480; easing.type: Easing.InOutCubic } }

  Rectangle {
    anchors.fill: parent
    color: "#101014"
  }

  Item {
    id: heroClip
    anchors.fill: parent
    clip: true
    visible: hero.heroImage
    onHeightChanged: {
      if (hero.cinema && heroImg.status === Image.Ready)
        panIdle.restart()
    }

    Image {
      id: heroPreload
      width: 1
      height: 1
      visible: false
      asynchronous: true
      cache: true
      sourceSize.width: 2048
      source: hero.pendingThumb.length ? Format.fileUrl(hero.pendingThumb) : ""
      onStatusChanged: {
        if (status === Image.Ready && hero.pendingThumb.length)
          hero.commitRequested(hero.pendingThumb)
      }
      onSourceChanged: {
        if (status === Image.Ready && hero.pendingThumb.length)
          hero.commitRequested(hero.pendingThumb)
      }
    }

    Image {
      id: heroImg
      x: Math.round((heroClip.width - width) / 2)
      y: 0
      width: {
        var sw = implicitWidth
        var sh = implicitHeight
        if (sw <= 0 || sh <= 0) return heroClip.width
        var cover = Math.max(heroClip.width / sw, heroClip.height / sh)
        var minH = heroClip.height * 1.28
        if (sh * cover < minH)
          cover = minH / sh
        return sw * cover
      }
      height: {
        var sw = implicitWidth
        var sh = implicitHeight
        if (sw <= 0 || sh <= 0) return heroClip.height
        return width * sh / sw
      }
      source: hero.shownThumb.length ? Format.fileUrl(hero.shownThumb) : ""
      fillMode: Image.PreserveAspectFit
      asynchronous: true
      cache: true
      opacity: hero.cinema ? 1 : 0.92
      sourceSize.width: 2048
      onSourceChanged: {
        heroPan.stop()
        y = 0
      }
      onStatusChanged: {
        if (status === Image.Ready) {
          y = 0
          if (hero.opened && !hero.pinned)
            panIdle.restart()
        }
      }
    }

    SequentialAnimation {
      id: heroPan
      running: false
      loops: Animation.Infinite
      PauseAnimation { duration: 1000 }
      NumberAnimation {
        target: heroImg
        property: "y"
        from: 0
        to: Math.min(0, heroClip.height - heroImg.height)
        duration: 8000
        easing.type: Easing.InOutSine
      }
      PauseAnimation { duration: 500 }
      NumberAnimation {
        target: heroImg
        property: "y"
        to: 0
        duration: 8000
        easing.type: Easing.InOutSine
      }
      PauseAnimation { duration: 700 }
    }
  }

  PreviewPane {
    anchors.fill: parent
    visible: !hero.heroImage && hero.heroKind.length > 0 && hero.heroKind !== "image"
    preview: hero.previewResult
    loading: hero.previewLoading
    foreground: hero.foreground
    accent: hero.accent
    selectable: false
  }

  Rectangle {
    anchors.fill: parent
    visible: !hero.cinema
    gradient: Gradient {
      GradientStop { position: 0.0; color: Qt.rgba(0, 0, 0, 0.35) }
      GradientStop { position: 0.45; color: Qt.rgba(0, 0, 0, 0.05) }
      GradientStop { position: 1.0; color: Qt.rgba(hero.background.r, hero.background.g, hero.background.b, 0.96) }
    }
  }

  Column {
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.bottom: parent.bottom
    anchors.leftMargin: 36
    anchors.rightMargin: 36
    anchors.bottomMargin: 18
    spacing: 6
    visible: !hero.cinema

    Text {
      width: parent.width
      text: Format.displayText(hero.heroTitle)
      visible: hero.heroTitle.length > 0
      color: "white"
      font.pixelSize: Style.font.title
      font.weight: Font.DemiBold
      elide: Text.ElideMiddle
      textFormat: Text.PlainText
    }
    Text {
      width: parent.width
      text: Format.displayText(hero.locFlash.length ? hero.locFlash : hero.locationLabel)
      visible: hero.locationLabel.length > 0
      color: hero.locFlash.length ? hero.accent : Qt.rgba(1, 1, 1, 0.65)
      font.pixelSize: Style.font.caption
      elide: Text.ElideMiddle
      textFormat: Text.PlainText
      MouseArea {
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        onClicked: hero.copyLocation()
      }
    }
  }

  Timer {
    id: panIdle
    interval: 280
    repeat: false
    onTriggered: {
      if (!hero.opened || hero.pinned || !hero.heroImage) return
      if (heroImg.status !== Image.Ready) return
      if (heroImg.height <= heroClip.height + 4) return
      heroPan.stop()
      heroImg.y = 0
      heroPan.restart()
    }
  }
}
