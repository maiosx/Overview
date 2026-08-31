import QtQuick
import QtQuick.Controls
import QtMultimedia
import qs.Commons
import "js/Format.js" as Format

Item {
  id: root
  property var preview: ({})
  property bool autoplay: false
  property color foreground: "white"
  property color accent: "#8ab4f8"

  readonly property string cover: String(preview && preview.cover ? preview.cover : "")
  readonly property string path: String(preview && preview.path ? preview.path : "")
  readonly property bool playing: audioPlayer.playbackState === MediaPlayer.PlayingState
  property string playPath: ""

  function toggle() {
    if (!path.length) return
    if (root.playing) audioPlayer.pause()
    else audioPlayer.play()
  }
  function syncAudio() {
    var p = root.autoplay ? String(root.path || "") : ""
    if (p === root.playPath) return
    root.playPath = p
    if (!p.length) {
      audioPlayer.stop()
      audioPlayer.source = ""
      return
    }
    audioPlayer.source = Format.fileUrl(p)
    audioPlayer.play()
  }
  onAutoplayChanged: Qt.callLater(syncAudio)
  onPathChanged: Qt.callLater(syncAudio)
  Component.onCompleted: Qt.callLater(syncAudio)
  function fmtTime(ms) {
    var s = Math.floor((Number(ms) || 0) / 1000)
    if (s < 0) s = 0
    var m = Math.floor(s / 60)
    s = s % 60
    return m + ":" + (s < 10 ? "0" : "") + s
  }

  MediaPlayer {
    id: audioPlayer
    audioOutput: AudioOutput { volume: 1.0 }
  }

  Column {
    anchors.centerIn: parent
    spacing: root.autoplay ? 22 : 14
    width: album.width

    Item {
      id: album
      width: {
        var cap = root.autoplay ? Math.min(root.width * 0.42, root.height * 0.52) : Math.min(root.width * 0.28, root.height * 0.62)
        return Math.max(120, Math.round(cap))
      }
      height: width

      Rectangle {
        anchors.fill: parent
        radius: 18
        color: "#161018"
        border.width: 1
        border.color: Qt.rgba(1, 1, 1, 0.08)
        clip: true

        Rectangle {
          visible: coverImg.status !== Image.Ready
          anchors.centerIn: parent
          width: parent.width * 0.7
          height: width
          radius: width / 2
          color: "#2a2030"
          Rectangle {
            anchors.centerIn: parent
            width: parent.width * 0.78
            height: width
            radius: width / 2
            color: "transparent"
            border.width: Math.max(6, Math.round(parent.width * 0.06))
            border.color: "#3d3148"
          }
          Rectangle {
            anchors.centerIn: parent
            width: parent.width * 0.2
            height: width
            radius: width / 2
            color: root.accent
            opacity: 0.85
          }
        }

        Text {
          visible: coverImg.status !== Image.Ready
          anchors.horizontalCenter: parent.horizontalCenter
          anchors.bottom: parent.bottom
          anchors.bottomMargin: parent.height * 0.12
          text: "♫"
          color: root.foreground
          opacity: 0.7
          font.pixelSize: Math.round(album.width * 0.16)
          textFormat: Text.PlainText
        }

        Image {
          id: coverImg
          anchors.fill: parent
          visible: root.cover.length > 0
          source: root.cover.length ? Format.fileUrl(root.cover) : ""
          fillMode: Image.PreserveAspectCrop
          asynchronous: true
          cache: true
          sourceSize.width: 640
          sourceSize.height: 640
        }

        Rectangle {
          visible: root.autoplay
          anchors.fill: parent
          color: Qt.rgba(0, 0, 0, root.playing ? 0.12 : 0.28)
        }

        Rectangle {
          visible: root.autoplay
          anchors.centerIn: parent
          width: 72
          height: 72
          radius: 36
          color: Qt.rgba(0, 0, 0, 0.58)
          border.width: 1
          border.color: Qt.rgba(1, 1, 1, 0.18)

          Text {
            anchors.centerIn: parent
            text: root.playing ? "❚❚" : "▶"
            color: "white"
            font.pixelSize: root.playing ? 22 : 28
            font.weight: Font.DemiBold
            textFormat: Text.PlainText
          }
        }

        MouseArea {
          anchors.fill: parent
          enabled: root.autoplay
          cursorShape: Qt.PointingHandCursor
          onClicked: root.toggle()
        }
      }
    }

    Row {
      visible: root.autoplay
      width: parent.width
      spacing: 10

      Text {
        text: root.fmtTime(audioPlayer.position)
        color: root.foreground
        opacity: 0.65
        font.pixelSize: Style.font.caption
        width: 40
        textFormat: Text.PlainText
      }

      Slider {
        id: seek
        width: parent.width - 90
        from: 0
        to: Math.max(1, audioPlayer.duration)
        value: audioPlayer.position
        live: true
        onMoved: audioPlayer.position = value
        background: Rectangle {
          x: seek.leftPadding
          y: seek.topPadding + seek.availableHeight / 2 - height / 2
          implicitWidth: 200
          implicitHeight: 4
          width: seek.availableWidth
          height: 4
          radius: 2
          color: Qt.rgba(1, 1, 1, 0.16)
          Rectangle {
            width: seek.visualPosition * parent.width
            height: parent.height
            radius: 2
            color: root.accent
          }
        }
        handle: Rectangle {
          x: seek.leftPadding + seek.visualPosition * (seek.availableWidth - width)
          y: seek.topPadding + seek.availableHeight / 2 - height / 2
          implicitWidth: 12
          implicitHeight: 12
          radius: 6
          color: "white"
        }
      }

      Text {
        text: root.fmtTime(audioPlayer.duration)
        color: root.foreground
        opacity: 0.65
        font.pixelSize: Style.font.caption
        width: 40
        horizontalAlignment: Text.AlignRight
        textFormat: Text.PlainText
      }
    }
  }
}
