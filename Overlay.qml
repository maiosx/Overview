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
  property bool panArmed: false
  property string shownThumb: ""
  property string pendingThumb: ""
  property bool cinema: false
  property int cinemaSavedIndex: 0
  property int cinemaLastPick: -1
  function open(payloadJson) {
    root.opened = true
    root.pinned = false
    root.cinema = false
    root.queryText = ""
    if (typeof searchField !== 'undefined') searchField.text = ""
    root.results = []
    root.lastQueryRev = -1
    root.previewResult = ({})
    root.activePath = ""
    root.shownThumb = ""
    root.pendingThumb = ""
    root.enableLayerBlur()
    root.requestQuery("")
    idleTimer.restart()
    Qt.callLater(function() { if (typeof searchField !== 'undefined') searchField.forceActiveFocus() })
  }
  function close() { root.opened = false; root.pinned = false; root.cinema = false; idleTimer.stop(); slideTimer.stop() }
  function toggle() { if (root.opened) root.close(); else root.open("{}") }
  function query(arg) { return root.callIpc("query", arg) }
  function snapshot(arg) { return root.callIpc("snapshot", arg) }
  function preview(arg) { return root.callIpc("preview", arg) }
  function enableLayerBlur() {
    Quickshell.execDetached(["hyprctl", "keyword", "layerrule", "blur,overview"])
    Quickshell.execDetached(["hyprctl", "keyword", "layerrule", "ignorealpha 0,overview"])
    Quickshell.execDetached(["hyprctl", "keyword", "layerrule", "xray 0,overview"])
  }
  function currentHit() {
    if (!root.results || root.selectedIndex < 0 || root.selectedIndex >= root.results.length) return null
    return root.results[root.selectedIndex]
  }
  function currentPath() {
    if (root.activePath.length) return root.activePath
    var hit = root.currentHit()
    return hit && hit.path ? String(hit.path) : ""
  }
  function callIpc(method, arg) {
    var job = { method: String(method || ""), arg: arg === undefined || arg === null ? "" : String(arg) }
    var svc = null
    try {
      if (root.pluginRegistry && typeof root.pluginRegistry.serviceFor === "function") {
        svc = root.pluginRegistry.serviceFor(root.pluginId)
        if (svc === root) svc = null
      }
    } catch (e) { svc = null }
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
      var p = hit && hit.path ? String(hit.path) : ""
      root.activePath = p
      if (p.length) root.requestPreview(p, 1)
    } else {
      root.previewResult = ({})
      root.activePath = ""
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
  }
  function requestQuery(q) { root.callIpc("query", q) }
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
    var hit = root.results[i]
    var p = hit && hit.path ? String(hit.path) : ""
    root.activePath = p
    if (p.length) root.requestPreview(p, 1)
  }
  function moveSelection(dx, dy) {
    if (!root.results.length) return
    var i = root.selectedIndex
    if (dx !== 0) i += dx
    if (dy !== 0) i += dy * root.columns
    root.selectIndex(i)
  }
  function launchFile(path) {
    var p = String(path || "")
    if (!p.length) return
    var quoted = "'" + p.replace(/'/g, "'\\''") + "'"
    Quickshell.execDetached(["hyprctl", "dispatch", "exec", "xdg-open " + quoted])
  }
  function openCurrent() {
    var p = root.currentPath()
    if (!p.length) return
    root.launchFile(p)
    Qt.callLater(root.close)
  }
  function bumpIdle() { idleTimer.restart() }

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
  Timer { interval: 100; running: root.opened; repeat: true; onTriggered: root.callIpc("snapshot", "") }
  Timer { id: idleTimer; interval: 60000; repeat: false; running: false; onTriggered: {} }
  Timer { id: slideTimer; interval: 14000; repeat: true; running: false; onTriggered: {} }
  Timer { id: debounce; interval: 80; repeat: false; onTriggered: { root.selectedIndex = 0; root.lastQueryRev = -1; root.requestQuery(root.queryText) } }

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
    }

    Item {
      id: stage
      anchors.fill: parent

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
          textFormat: Text.PlainText
        }
        TextInput {
          id: searchField
          anchors.fill: parent
          leftPadding: 20
          rightPadding: 20
          verticalAlignment: TextInput.AlignVCenter
          color: "white"
          font.pixelSize: 15
          clip: true
          selectByMouse: true
          focus: true
          Keys.priority: Keys.BeforeItem
          Keys.onPressed: function(event) {
            root.bumpIdle()
            if (event.key === Qt.Key_Escape) { root.close(); event.accepted = true }
            else if (event.key === Qt.Key_Down) { root.moveSelection(0, 1); event.accepted = true }
            else if (event.key === Qt.Key_Up) { root.moveSelection(0, -1); event.accepted = true }
            else if (event.key === Qt.Key_Right && cursorPosition === text.length && selectedText.length === 0) { root.moveSelection(1, 0); event.accepted = true }
            else if (event.key === Qt.Key_Left && cursorPosition === 0 && selectedText.length === 0) { root.moveSelection(-1, 0); event.accepted = true }
            else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) { root.openCurrent(); event.accepted = true }
          }
          onTextChanged: { root.bumpIdle(); root.queryText = text; debounce.restart() }
        }
      }

      GridView {
        id: grid
        anchors.top: searchBar.bottom
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.margins: 28
        anchors.topMargin: 16
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
    }
  }
}
