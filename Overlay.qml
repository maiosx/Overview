import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.Commons
import qs.Ui
import "js/Format.js" as Format

Item {
  id: root
  property var shell: null
  property var manifest: null
  property var pluginRegistry: null
  property bool opened: false
  property bool pinned: false
  property string pluginId: "io.github.overview"
  property string queryText: ""
  property int selectedIndex: 0
  property var results: []
  property int resultsTick: 0
  property var previewResult: ({})
  property bool previewLoading: false
  property int lastQueryRev: -1
  property int lastPreviewRev: -1
  property string backend: ""
  property var ipcQueue: []
  property var ipcCurrent: null
  property color background: Color.menu.background
  property color foreground: Color.menu.text
  property color border: Color.menu.border
  property color scrim: Color.menu.scrim
  property color accent: Color.accent
  property var borderSpec: Border.surfaceSpec("menu", "border", border, Math.max(1, Style.space(2)))
  readonly property int cornerRadius: Style.cornerRadius
  property string fontFamily: Style.font.menuFamily
  property string diskLabel: ""
  property real diskUsedFrac: 0
  property string homePrefix: ""
  property string activePath: ""
  property string locFlash: ""
  readonly property int columns: 3
  readonly property string heroKind: String(root.previewResult && root.previewResult.kind ? root.previewResult.kind : "")
  readonly property bool heroImage: root.heroKind === "image" && String(root.previewResult.path || "").length > 0
  readonly property string locationLabel: {
    var p = String(root.activePath || "")
    if (!p.length) return ""
    var slash = p.lastIndexOf("/")
    var dir = slash > 0 ? p.slice(0, slash) : p
    var home = String(root.homePrefix || Quickshell.env("HOME") || "")
    if (home.length && dir.indexOf(home) === 0) dir = "~" + dir.slice(home.length)
    return dir.length ? dir : "/"
  }
  readonly property string heroTitle: {
    var hit = root.currentHit()
    if (hit && hit.name) return String(hit.name)
    return Format.basename(root.activePath)
  }

  function serviceRef() {
    try {
      if (root.pluginRegistry && typeof root.pluginRegistry.serviceFor === "function") {
        var s = root.pluginRegistry.serviceFor(root.pluginId)
        if (s && s !== root) return s
      }
    } catch (e) {}
    return null
  }

  function open(payloadJson) {
    root.opened = true
    root.pinned = false
    root.queryText = ""
    searchField.text = ""
    root.results = []
    root.lastQueryRev = -1
    root.previewResult = ({})
    root.activePath = ""
    root.enableLayerBlur()
    root.requestQuery("")
    Qt.callLater(function() { searchField.forceActiveFocus() })
  }
  function close() { root.opened = false; root.pinned = false }
  function toggle() { if (root.opened) root.close(); else root.open("{}") }
  function query(arg) { return root.callIpc("query", arg) }
  function snapshot(arg) { return root.callIpc("snapshot", arg) }
  function preview(arg) { return root.callIpc("preview", arg) }

  function currentHit() {
    if (!root.results || root.selectedIndex < 0 || root.selectedIndex >= root.results.length) return null
    return root.results[root.selectedIndex]
  }
  function currentPath() {
    if (root.activePath.length) return root.activePath
    var hit = root.currentHit()
    return hit && hit.path ? String(hit.path) : ""
  }
  function locationPath() {
    var p = String(root.activePath || "")
    if (!p.length) return ""
    var slash = p.lastIndexOf("/")
    return slash > 0 ? p.slice(0, slash) : p
  }
  function copyText(s) {
    var t = String(s || "")
    if (!t.length) return
    try { Quickshell.clipboardText = t } catch (e) {}
    Quickshell.execDetached(["wl-copy", "--", t])
  }
  function copyLocation() {
    var p = root.locationPath()
    if (!p.length) return
    root.copyText(p)
    root.locFlash = "copied"
    locFlashTimer.restart()
  }
  function enableLayerBlur() {
    Quickshell.execDetached(["hyprctl", "keyword", "layerrule", "blur,overview"])
    Quickshell.execDetached(["hyprctl", "keyword", "layerrule", "ignorealpha 0,overview"])
    Quickshell.execDetached(["hyprctl", "keyword", "layerrule", "xray 0,overview"])
  }

  function callIpc(method, arg) {
    var job = { method: String(method || ""), arg: arg === undefined || arg === null ? "" : String(arg) }
    var svc = root.serviceRef()
    if (svc && typeof svc[job.method] === "function") {
      var result = svc[job.method](job.arg)
      if (job.method === "snapshot") root.applySnapshot(result)
      else if (job.method === "query" && svc.lastResults) root.setResults(svc.lastResults)
      return result === undefined || result === null ? "ok" : String(result)
    }
    root.ipcQueue.push(job)
    root.runIpc()
  }
  function runIpc() {
    if (ipcProc.running || root.ipcCurrent || !root.ipcQueue.length) return
    root.ipcCurrent = root.ipcQueue.shift()
    ipcProc.command = ["omarchy-shell", root.pluginId, root.ipcCurrent.method, root.ipcCurrent.arg]
    ipcProc.running = true
  }
  function setResults(list) {
    var next = []
    var prefix = String(root.homePrefix || "")
    if (list && list.length) {
      for (var i = 0; i < list.length; i++) {
        var hit = list[i]
        var p = hit && hit.path ? String(hit.path) : ""
        if (!p.length) continue
        if (prefix.length && p !== prefix && p.indexOf(prefix + "/") !== 0) continue
        if (p.indexOf("/home/") !== 0 && p.indexOf("/root/") !== 0) continue
        next.push(hit)
      }
    }
    root.results = next
    root.resultsTick += 1
    if (next.length) {
      if (root.selectedIndex >= next.length) root.selectedIndex = 0
      var hit = next[root.selectedIndex]
      if (hit && hit.path) root.requestPreview(hit.path, 1)
    } else {
      root.previewResult = ({})
    }
  }
  function applySnapshot(raw) {
    var snap = null
    try { snap = JSON.parse(String(raw || "")) } catch (e) { return }
    if (!snap) return
    if (snap.backend) root.backend = String(snap.backend)
    var rev = Number(snap.resultsRevision)
    if (isNaN(rev)) rev = 0
    if (rev !== root.lastQueryRev) {
      root.lastQueryRev = rev
      root.setResults(snap.results || [])
    }
    var prev = Number(snap.previewRevision)
    if (!isNaN(prev) && prev !== root.lastPreviewRev) {
      root.lastPreviewRev = prev
      root.previewResult = snap.preview || {}
      root.previewLoading = false
    }
    if (snap.home) root.homePrefix = String(snap.home)
    if (snap.diskLabel !== undefined) root.diskLabel = String(snap.diskLabel || "")
    if (snap.diskUsedFrac !== undefined) root.diskUsedFrac = Number(snap.diskUsedFrac) || 0
  }
  function requestQuery(q) {
    root.callIpc("query", q)
  }
  function requestPreview(path, page) {
    root.activePath = String(path || "")
    root.previewLoading = true
    root.callIpc("preview", JSON.stringify({ path: path, page: page || 1 }))
  }
  function selectIndex(i) {
    if (!root.results.length) return
    if (i < 0) i = 0
    if (i >= root.results.length) i = root.results.length - 1
    root.selectedIndex = i
    root.requestPreview(root.results[i].path, 1)
  }
  function moveSelection(dx, dy) {
    if (!root.results.length) return
    var cols = root.columns
    var i = root.selectedIndex
    if (dx !== 0) i += dx
    if (dy !== 0) i += dy * cols
    root.selectIndex(i)
  }
  function launchFile(path) {
    var p = String(path || "")
    if (!p.length) return
    var quoted = "'" + p.replace(/'/g, "'\\''") + "'"
    Quickshell.execDetached(["hyprctl", "dispatch", "exec", "xdg-open " + quoted])
  }
  function launchDir(path) {
    var p = String(path || "")
    if (!p.length) return
    var slash = p.lastIndexOf("/")
    var dir = slash > 0 ? p.slice(0, slash) : p
    var quoted = "'" + dir.replace(/'/g, "'\\''") + "'"
    Quickshell.execDetached(["hyprctl", "dispatch", "exec", "xdg-open " + quoted])
  }
  function openCurrent() {
    var p = root.currentPath()
    if (!p.length) return
    root.launchFile(p)
    Qt.callLater(root.close)
  }
  function revealCurrent() {
    var p = root.currentPath()
    if (!p.length) return
    root.launchDir(p)
    Qt.callLater(root.close)
  }
  function pinToggle() {
    if (!root.currentHit() && !root.activePath.length) return
    root.pinned = !root.pinned
    if (root.pinned) {
      root.enableLayerBlur()
      Qt.callLater(function() { pinnedPane.forceActiveFocus() })
    } else {
      Qt.callLater(function() { searchField.forceActiveFocus() })
    }
  }

  Process {
    id: ipcProc
    running: false
    stdout: StdioCollector { id: ipcOut; waitForEnd: true }
    onExited: function() {
      var job = root.ipcCurrent
      var collected = String(ipcOut.text || "").trim()
      root.ipcCurrent = null
      if (job && job.method === "snapshot" && collected.length) root.applySnapshot(collected)
      root.runIpc()
    }
  }
  Timer {
    interval: 100
    running: root.opened
    repeat: true
    onTriggered: root.callIpc("snapshot", "")
  }
  Timer {
    id: locFlashTimer
    interval: 1200
    repeat: false
    onTriggered: root.locFlash = ""
  }
  Timer {
    id: debounce
    interval: 80
    repeat: false
    onTriggered: { root.selectedIndex = 0; root.lastQueryRev = -1; root.requestQuery(root.queryText) }
  }

  PanelWindow {
    visible: root.opened
    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"
    WlrLayershell.namespace: "overview"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
    exclusionMode: ExclusionMode.Ignore

    Rectangle {
      anchors.fill: parent
      color: Qt.rgba(root.background.r, root.background.g, root.background.b, 0.94)
      visible: !root.pinned
    }

    Item {
      id: stage
      anchors.fill: parent
      visible: !root.pinned

      Item {
        id: hero
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        height: Math.round(parent.height * 0.42)

        Rectangle {
          anchors.fill: parent
          color: "#101014"
        }

        Image {
          anchors.fill: parent
          visible: root.heroImage
          source: root.heroImage ? Format.fileUrl(root.previewResult.path) : ""
          fillMode: Image.PreserveAspectCrop
          asynchronous: true
          cache: true
          opacity: 0.92
        }

        PreviewPane {
          anchors.fill: parent
          visible: !root.heroImage && root.heroKind.length > 0 && root.heroKind !== "image"
          preview: root.previewResult
          loading: root.previewLoading
          foreground: root.foreground
          accent: root.accent
          selectable: false
        }

        Rectangle {
          anchors.fill: parent
          gradient: Gradient {
            GradientStop { position: 0.0; color: Qt.rgba(0, 0, 0, 0.35) }
            GradientStop { position: 0.45; color: Qt.rgba(0, 0, 0, 0.05) }
            GradientStop { position: 1.0; color: Qt.rgba(root.background.r, root.background.g, root.background.b, 0.96) }
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

          Text {
            width: parent.width
            text: root.heroTitle
            visible: root.heroTitle.length > 0
            color: "white"
            font.pixelSize: Style.font.title
            font.weight: Font.DemiBold
            elide: Text.ElideMiddle
          }
          Text {
            width: parent.width
            text: root.locFlash.length ? root.locFlash : root.locationLabel
            visible: root.locationLabel.length > 0
            color: root.locFlash.length ? root.accent : Qt.rgba(1, 1, 1, 0.65)
            font.pixelSize: Style.font.caption
            elide: Text.ElideMiddle
            MouseArea {
              anchors.fill: parent
              cursorShape: Qt.PointingHandCursor
              onClicked: root.copyLocation()
            }
          }
        }
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
        border.color: searchField.activeFocus ? root.accent : Qt.rgba(1, 1, 1, 0.16)
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
            if (event.key === Qt.Key_Escape) {
              if (root.pinned) root.pinned = false
              else root.close()
              event.accepted = true
            } else if (event.key === Qt.Key_Down) { root.moveSelection(0, 1); event.accepted = true }
            else if (event.key === Qt.Key_Up) { root.moveSelection(0, -1); event.accepted = true }
            else if (event.key === Qt.Key_Right && cursorPosition === text.length && selectedText.length === 0) { root.moveSelection(1, 0); event.accepted = true }
            else if (event.key === Qt.Key_Left && cursorPosition === 0 && selectedText.length === 0) { root.moveSelection(-1, 0); event.accepted = true }
            else if (event.key === Qt.Key_Space && text.length === 0) { root.pinToggle(); event.accepted = true }
            else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) { root.openCurrent(); event.accepted = true }
          }
          onTextChanged: { root.queryText = text; debounce.restart() }
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
        clip: true
        cellWidth: Math.floor(width / root.columns)
        cellHeight: Math.round(cellWidth * 0.78)
        model: root.results
        currentIndex: root.selectedIndex
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
            selected: index === root.selectedIndex
            foreground: root.foreground
            accent: root.accent
            homePrefix: root.homePrefix
            onActivated: root.selectIndex(index)
            onOpened: { root.selectIndex(index); root.openCurrent() }
          }
        }
      }

      Text {
        anchors.centerIn: grid
        visible: root.results.length === 0 && root.queryText.length > 0
        text: "no matches"
        color: root.foreground
        opacity: 0.45
        font.pixelSize: Style.font.title
        z: 2
      }

      Text {
        anchors.bottom: parent.bottom
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottomMargin: 10
        text: root.diskLabel
        visible: root.diskLabel.length > 0
        color: root.foreground
        opacity: 0.4
        font.pixelSize: Style.font.caption
      }
    }

    Rectangle {
      id: pinnedPane
      anchors.fill: parent
      visible: root.pinned
      color: Qt.rgba(root.background.r, root.background.g, root.background.b, 0.72)
      focus: root.pinned
      Keys.onPressed: function(event) {
        if (event.key === Qt.Key_Escape || event.key === Qt.Key_Space) { root.pinToggle(); event.accepted = true }
        else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) { root.revealCurrent(); event.accepted = true }
      }
      PreviewPane {
        anchors.fill: parent
        anchors.margins: 36
        preview: root.previewResult
        loading: root.previewLoading
        foreground: root.foreground
        accent: root.accent
        selectable: true
      }
      Text {
        anchors.bottom: parent.bottom
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottomMargin: 16
        width: parent.width * 0.8
        text: root.locFlash.length ? root.locFlash : root.locationLabel
        color: root.locFlash.length ? root.accent : root.foreground
        opacity: root.locFlash.length ? 1 : 0.55
        font.pixelSize: Style.font.caption
        elide: Text.ElideMiddle
        horizontalAlignment: Text.AlignHCenter
        MouseArea {
          anchors.fill: parent
          hoverEnabled: true
          cursorShape: Qt.PointingHandCursor
          onClicked: root.copyLocation()
        }
      }
    }
  }
}
