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
          anchors.fill: parent
          visible: root.isImage && root.path.length
          source: root.isImage ? Format.fileUrl(root.path) : ""
          fillMode: Image.PreserveAspectCrop
          asynchronous: true
          cache: true
          smooth: true
        }

        Text {
          anchors.centerIn: parent
          visible: !root.isImage
          text: Format.glyphFor(root.kind)
          color: root.foreground
          opacity: 0.7
          font.pixelSize: 36
        }

        Rectangle {
          width: 54
          height: 54
          radius: 27
          anchors.centerIn: parent
          color: Qt.rgba(0.85, 0.08, 0.12, 0.92)
          border.width: 0
          Text {
            anchors.centerIn: parent
            text: "▶"
            color: "white"
            font.pixelSize: 20
            leftPadding: 3
          }
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
            text: root.title
            color: root.foreground
            elide: Text.ElideMiddle
            font.pixelSize: Style.font.body
            font.weight: Font.DemiBold
          }
          Text {
            width: parent.width
            text: root.folder
            color: root.foreground
            opacity: 0.5
            elide: Text.ElideMiddle
            font.pixelSize: Style.font.caption
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
