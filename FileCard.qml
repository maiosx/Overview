import QtQuick
import qs.Commons
import "js/Format.js" as Format

Item {
  id: root
  property var hit: ({})
  property bool selected: false
  property color foreground: "#c0caf5"
  property color accent: "#7aa2f7"
  property color cardFill: Qt.rgba(0, 0, 0, 0.38)
  property string homePrefix: ""
  signal activated()
  signal opened()

  readonly property string path: hit && hit.path ? String(hit.path) : ""
  readonly property string kind: hit && hit.kind ? String(hit.kind) : Format.kindOf(path, false)
  readonly property string title: hit && hit.name ? String(hit.name) : Format.basename(path)
  readonly property bool isImage: kind === "image"
  readonly property bool isVideo: kind === "video"
  readonly property string thumbCache: isVideo ? Format.videoThumbPath(path, homePrefix) : Format.imageThumbPath(path, homePrefix)
  readonly property string folder: Format.homeRelative(Format.dirname(path), homePrefix)

  Rectangle {
    anchors.fill: parent
    radius: 18
    color: root.cardFill
    border.width: root.selected ? 2 : 1
    border.color: root.selected ? root.accent : Qt.rgba(1, 1, 1, 0.10)
    clip: true

    Column {
      anchors.fill: parent
      spacing: 0

      Item {
        width: parent.width
        height: Math.round(parent.width * 0.56)

        Rectangle {
          anchors.fill: parent
          color: Format.kindTint(root.kind)
        }

        Image {
          id: thumb
          anchors.fill: parent
          visible: (root.isImage || root.isVideo) && root.path.length
          source: {
            if ((root.isImage || root.isVideo) && root.thumbCache.length)
              return Format.fileUrl(root.thumbCache)
            return ""
          }
          fillMode: Image.PreserveAspectCrop
          asynchronous: true
          cache: true
          smooth: true
          sourceSize.width: 640
          sourceSize.height: 360
          onStatusChanged: {
            if ((root.isVideo || root.isImage) && status === Image.Error)
              thumbRetry.restart()
          }
        }

        Timer {
          id: thumbRetry
          interval: 900
          repeat: false
          property int tries: 0
          onTriggered: {
            if (thumb.status === Image.Ready || (!root.isVideo && !root.isImage)) { tries = 0; return }
            if (tries > 8) { tries = 0; return }
            tries += 1
            var s = Format.fileUrl(root.thumbCache) + "#" + tries
            thumb.source = ""
            thumb.source = s
          }
        }

        Text {
          anchors.centerIn: parent
          visible: !(thumb.status === Image.Ready && (root.isImage || root.isVideo))
          text: Format.glyphFor(root.kind)
          color: root.foreground
          opacity: 0.7
          font.pixelSize: 36
          textFormat: Text.PlainText
        }

        Rectangle {
          anchors.left: parent.left
          anchors.bottom: parent.bottom
          anchors.margins: 10
          height: 22
          width: kindLabel.implicitWidth + 14
          radius: 11
          color: Qt.rgba(0, 0, 0, 0.55)
          Text {
            id: kindLabel
            anchors.centerIn: parent
            text: Format.kindLabel(root.kind)
            color: "white"
            font.pixelSize: 11
            textFormat: Text.PlainText
          }
        }
      }

      Item {
        width: parent.width
        height: parent.height - Math.round(parent.width * 0.56)

        Column {
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.verticalCenter: parent.verticalCenter
          anchors.leftMargin: 14
          anchors.rightMargin: 14
          spacing: 4

          Text {
            width: parent.width
            text: Format.displayText(root.title)
            color: root.foreground
            elide: Text.ElideMiddle
            font.pixelSize: Style.font.body
            font.weight: Font.DemiBold
            textFormat: Text.PlainText
          }
          Text {
            width: parent.width
            text: Format.displayText(root.folder)
            color: root.foreground
            opacity: 0.5
            elide: Text.ElideMiddle
            font.pixelSize: Style.font.caption
            textFormat: Text.PlainText
          }
        }
      }
    }

    MouseArea {
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onClicked: root.activated()
      onDoubleClicked: root.opened()
    }
  }
}
