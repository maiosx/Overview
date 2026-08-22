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
  property string shownThumb: ""
  property string pendingThumb: ""
  property bool cinema: false
  property int cinemaSavedIndex: 0
  property int cinemaLastPick: -1
  property var cinemaPool: []
  property int cinemaTries: 0
  readonly property string heroPath: {
    var hit = root.currentHit()
    if (hit && hit.path) return String(hit.path)
    return String(root.activePath || "")
  }
  readonly property string heroKind: {
    if (root.cinema && root.previewResult && root.previewResult.kind)
      return String(root.previewResult.kind)
    var hit = root.currentHit()
    if (hit && hit.kind) return String(hit.kind)
    if (hit && hit.path) return Format.kindOf(hit.path, false)
    return String(root.previewResult && root.previewResult.kind ? root.previewResult.kind : "")
  }
  readonly property string heroThumb: {
    if (root.heroKind === "image") {
      if (root.previewResult && root.previewResult.blocked) return ""
      return String(root.previewResult && root.previewResult.path ? root.previewResult.path : "")
    }
    if (root.heroKind === "video") {
      var t = String(root.previewResult && root.previewResult.thumb ? root.previewResult.thumb : "")
      if (t.length) return t
      return Format.videoThumbPath(root.heroPath, root.homePrefix || Quickshell.env("HOME") || "")
    }
    return ""
  }
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
    overlayWin.clearSearch()
    root.results = []
    root.lastQueryRev = -1
    root.previewResult = ({})
    root.activePath = ""
    root.shownThumb = ""
    root.pendingThumb = ""
    root.cinema = false
    root.cinemaPool = []
    root.cinemaTries = 0
    root.enableLayerBlur()
    root.requestQuery("")
    imageIndex.refresh()
    idleTimer.restart()
    Qt.callLater(function() { overlayWin.focusSearch() })
  }
  function close() {
    root.opened = false
    root.pinned = false
    root.cinema = false
    idleTimer.stop()
    slideTimer.stop()
  }
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
      var p = hit && hit.path ? String(hit.path) : ""
      root.activePath = p
      if (hit && hit.path)
        root.requestPreview(p, 1)
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
      var pv = snap.preview || {}
      if (root.previewMatches(pv)) {
        root.lastPreviewRev = prev
        root.previewResult = pv
        root.previewLoading = false
        root.queueHero(root.heroThumb)
      } else {
        root.lastPreviewRev = prev
      }
    }
    if (snap.home) root.homePrefix = String(snap.home)
    if (snap.diskLabel !== undefined) root.diskLabel = String(snap.diskLabel || "")
    if (snap.diskUsedFrac !== undefined) root.diskUsedFrac = Number(snap.diskUsedFrac) || 0
    if (snap.images && snap.images.length)
      root.cinemaPool = snap.images
  }
  function previewMatches(pv) {
    if (root.cinema) return true
    var want = String(root.activePath || "")
    if (!want.length || !pv) return true
    var pp = String(pv.path || "")
    if (pp === want) return true
    var lab = String(pv.label || "")
    if (lab.length && lab === Format.basename(want)) return true
    return false
  }
  function requestQuery(q) { root.callIpc("query", q) }
  function requestPreview(path, page) {
    root.activePath = String(path || "")
    root.previewLoading = true
    root.callIpc("preview", JSON.stringify({ path: path, page: page || 1 }))
  }
  function queueHero(path) {
    var p = String(path || "")
    if (!p.length) {
      if (root.heroKind !== "image" && root.heroKind !== "video") {
        root.shownThumb = ""
        root.pendingThumb = ""
        if (typeof overlayWin !== "undefined") overlayWin.stopPan()
      }
      return
    }
    if (p === root.shownThumb) {
      root.pendingThumb = ""
      return
    }
    root.pendingThumb = p
  }
  function commitHero(path) {
    var p = String(path || "")
    if (!p.length) return
    if (p !== root.pendingThumb && p !== root.heroThumb) return
    if (typeof overlayWin !== "undefined") overlayWin.stopPan()
    root.shownThumb = p
    root.pendingThumb = ""
    if (typeof overlayWin !== "undefined") overlayWin.startPanSoon()
  }
  function bumpIdle() {
    if (root.cinema) {
      root.exitCinema()
      return
    }
    idleTimer.restart()
  }
  function imageHits() {
    var out = []
    var list = (root.cinemaPool && root.cinemaPool.length) ? root.cinemaPool : (root.results || [])
    for (var i = 0; i < list.length; i++) {
      var hit = list[i]
      var kind = hit && hit.kind ? String(hit.kind) : Format.kindOf(hit && hit.path ? hit.path : "", false)
      if (kind === "image" && hit && hit.path)
        out.push(hit)
    }
    return out
  }
  function enterCinema() {
    if (!root.opened || root.pinned || root.cinema) return
    var hits = root.imageHits()
    if (!hits.length) {
      imageIndex.refresh()
      if (root.cinemaTries < 5) {
        root.cinemaTries += 1
        cinemaRetry.restart()
      }
      return
    }
    root.cinemaTries = 0
    root.cinemaSavedIndex = root.selectedIndex
    root.cinema = true
    idleTimer.stop()
    root.slideNext()
    slideTimer.restart()
    Qt.callLater(function() { overlayWin.focusStage() })
  }
  function exitCinema() {
    if (!root.cinema) return
    root.cinema = false
    slideTimer.stop()
    root.pendingThumb = ""
    root.lastPreviewRev = -1
    if (typeof overlayWin !== "undefined") overlayWin.stopPan()
    if (root.results && root.cinemaSavedIndex >= 0 && root.cinemaSavedIndex < root.results.length)
      root.selectIndex(root.cinemaSavedIndex)
    root.reloadHero()
    idleTimer.restart()
    Qt.callLater(function() { overlayWin.focusSearch() })
  }
  function reloadHero() {
    if (typeof overlayWin !== "undefined") overlayWin.stopPan()
    var t = root.heroThumb
    if (!t.length) {
      if (root.heroKind !== "image" && root.heroKind !== "video") {
        root.shownThumb = ""
        root.pendingThumb = ""
      }
      return
    }
    if (t === root.shownThumb) {
      if (typeof overlayWin !== "undefined") overlayWin.startPanSoon()
      return
    }
    root.queueHero(t)
  }
  function slideNext() {
    var hits = root.imageHits()
    if (!hits.length) return
    var i = Math.floor(Math.random() * hits.length)
    if (hits.length > 1 && i === root.cinemaLastPick)
      i = (i + 1) % hits.length
    root.cinemaLastPick = i
    var p = String(hits[i].path || "")
    if (!p.length) return
    root.requestPreview(p, 1)
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
    if (root.cinema) root.exitCinema()
    root.pinned = !root.pinned
    if (root.pinned) {
      root.enableLayerBlur()
      Qt.callLater(function() { overlayWin.focusPinned() })
    } else {
      Qt.callLater(function() { overlayWin.focusSearch() })
    }
  }
  function kickDebounce() { debounce.restart() }

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
    id: idleTimer
    interval: 60000
    repeat: false
    running: false
    onTriggered: root.enterCinema()
  }
  Timer {
    id: cinemaRetry
    interval: 1200
    repeat: false
    onTriggered: {
      if (root.opened && !root.pinned && !root.cinema)
        root.enterCinema()
    }
  }
  Timer {
    id: slideTimer
    interval: 14000
    repeat: true
    running: false
    onTriggered: { if (root.cinema) root.slideNext() }
  }
  Timer {
    id: debounce
    interval: 80
    repeat: false
    onTriggered: { root.selectedIndex = 0; root.lastQueryRev = -1; root.requestQuery(root.queryText) }
  }

  OverlayWindow {
    id: overlayWin
    host: root
  }
  ImageIndex {
    id: imageIndex
    home: root.homePrefix.length ? root.homePrefix : (Quickshell.env("HOME") || "")
    onReady: {
      if (images && images.length)
        root.cinemaPool = images
    }
  }
}
