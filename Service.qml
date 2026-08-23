import QtQuick
import Quickshell
import Quickshell.Io
import "js/Format.js" as Format

Item {
  id: root
  property var shell: null
  property var manifest: null
  property var pluginRegistry: null
  readonly property string pluginId: "io.github.overview"
  readonly property string home: Quickshell.env("HOME") || "/tmp"
  property var lastResults: []
  property var lastPreview: ({})
  property int resultsRevision: 0
  property int previewRevision: 0
  property string backend: "search"
  property string lastStatus: "ready"
  property string searchNeedle: ""
  property bool searchRunning: false
  property string previewPath: ""
  property string diskLabel: ""
  property real diskUsedFrac: 0
  property double diskTotal: 0
  property var lastImages: []
  property var videoQueue: []

  readonly property int previewBytes: 200000

  readonly property string searchBody: "q=\"$1\"; start=\"$2\"; " +
    "home=$(cd \"$start\" 2>/dev/null && pwd -P || printf '%s' \"$start\"); " +
    "case \"$home\" in /home/*|/root) ;; *) exit 0 ;; esac; " +
    "if [ -z \"$q\" ] || [ ! -d \"$home\" ]; then exit 0; fi; " +
    "ulimit -t 4 2>/dev/null; ulimit -v 262144 2>/dev/null; " +
    "inside() { n=0; while IFS= read -r p; do " +
    "  [ -z \"$p\" ] && continue; " +
    "  d=$(dirname \"$p\"); b=$(basename \"$p\"); " +
    "  rp=$(cd \"$d\" 2>/dev/null && printf '%s/%s\\n' \"$(pwd -P)\" \"$b\" || printf '%s\\n' \"$p\"); " +
    "  case \"$rp\" in \"$home\"|\"$home\"/*) printf '%s\\n' \"$rp\"; n=$((n+1)); [ \"$n\" -ge 24 ] && break ;; esac; " +
    "done; }; " +
    "wrap() { if command -v timeout >/dev/null 2>&1; then timeout -k 1 3 \"$@\"; else \"$@\"; fi; }; " +
    "fd_bin=$(command -v fd || command -v fdfind || true); " +
    "if [ -n \"$fd_bin\" ]; then " +
    "  wrap \"$fd_bin\" -a -i -F -t f --one-file-system --max-results 24 --max-depth 8 " +
    "    -E node_modules -E .git -E dist -E target -E __pycache__ -E .venv -E venv " +
    "    -E .cache -E .local -E .npm -E .cargo -E .flatpak " +
    "    -- \"$q\" \"$home\" 2>/dev/null | inside; " +
    "  exit 0; " +
    "fi; " +
    "wrap find -P \"$home\" -xdev -maxdepth 8 " +
    "  \\( -name node_modules -o -name .git -o -name dist -o -name target -o -name .venv -o -name .cache -o -name .local \\) -prune " +
    "  -o -type f -iname \"*$q*\" -print 2>/dev/null | " +
    "awk 'BEGIN{n=0} { print; n++; if (n>=24) exit }' | inside"

  readonly property string recentBody: "start=\"$1\"; " +
    "home=$(cd \"$start\" 2>/dev/null && pwd -P || printf '%s' \"$start\"); " +
    "case \"$home\" in /home/*|/root) ;; *) exit 0 ;; esac; " +
    "ulimit -t 4 2>/dev/null; ulimit -v 262144 2>/dev/null; " +
    "inside() { while IFS= read -r p; do " +
    "  [ -z \"$p\" ] && continue; " +
    "  d=$(dirname \"$p\"); b=$(basename \"$p\"); " +
    "  rp=$(cd \"$d\" 2>/dev/null && printf '%s/%s\\n' \"$(pwd -P)\" \"$b\" || printf '%s\\n' \"$p\"); " +
    "  case \"$rp\" in \"$home\"|\"$home\"/*) printf '%s\\n' \"$rp\" ;; esac; " +
    "done; }; " +
    "wrap() { if command -v timeout >/dev/null 2>&1; then timeout -k 1 3 \"$@\"; else \"$@\"; fi; }; " +
    "fd_bin=$(command -v fd || command -v fdfind || true); " +
    "if [ -n \"$fd_bin\" ]; then " +
    "  wrap \"$fd_bin\" -a -t f --one-file-system --changed-within 30d --max-results 24 --max-depth 6 " +
    "    -E node_modules -E .git -E dist -E target -E __pycache__ -E .venv -E venv " +
    "    -E .cache -E .local -E .npm -E .cargo -E .flatpak " +
    "    . \"$home\" 2>/dev/null | inside; " +
    "  exit 0; " +
    "fi; " +
    "set --; " +
    "for d in Downloads Pictures Documents Desktop Videos Music; do " +
    "  [ -d \"$home/$d\" ] && set -- \"$@\" \"$home/$d\"; " +
    "done; " +
    "if [ $# -eq 0 ]; then set -- \"$home\"; depth=1; else depth=2; fi; " +
    "wrap find -P \"$@\" -xdev -maxdepth \"$depth\" " +
    "  \\( -name node_modules -o -name .git -o -name dist -o -name target -o -name .venv -o -name .cache -o -name .local \\) -prune " +
    "  -o -type f -printf '%T@ %p\\n' 2>/dev/null | " +
    "awk 'BEGIN{n=0; seen=0} { " +
    "  seen++; t=$1+0; sub(/^[^ ]+[ ]/,\"\"); " +
    "  if (n<24) { n++; ts[n]=t; ps[n]=$0 } " +
    "  else { mi=1; for (i=2;i<=24;i++) if (ts[i]<ts[mi]) mi=i; if (t>ts[mi]) { ts[mi]=t; ps[mi]=$0 } } " +
    "  if (seen>=400) exit } " +
    "END { for (i=1;i<=n;i++) printf \"%.6f %s\\n\", ts[i], ps[i] }' | " +
    "sort -nr | head -n 24 | cut -d' ' -f2- | inside"

  readonly property string imageSearchBody: "start=\"$1\"; " +
    "home=$(cd \"$start\" 2>/dev/null && pwd -P || printf '%s' \"$start\"); " +
    "case \"$home\" in /home/*|/root) ;; *) exit 0 ;; esac; " +
    "ulimit -t 6 2>/dev/null; ulimit -v 262144 2>/dev/null; " +
    "inside() { n=0; while IFS= read -r p; do " +
    "  [ -z \"$p\" ] && continue; " +
    "  d=$(dirname \"$p\"); b=$(basename \"$p\"); " +
    "  rp=$(cd \"$d\" 2>/dev/null && printf '%s/%s\\n' \"$(pwd -P)\" \"$b\" || printf '%s\\n' \"$p\"); " +
    "  case \"$rp\" in \"$home\"|\"$home\"/*) printf '%s\\n' \"$rp\"; n=$((n+1)); [ \"$n\" -ge 36 ] && break ;; esac; " +
    "done; }; " +
    "wrap() { if command -v timeout >/dev/null 2>&1; then timeout -k 1 5 \"$@\"; else \"$@\"; fi; }; " +
    "fd_bin=$(command -v fd || command -v fdfind || true); " +
    "if [ -n \"$fd_bin\" ]; then " +
    "  wrap \"$fd_bin\" -a -t f --one-file-system --changed-within 180d --max-results 36 --max-depth 8 " +
    "    -e jpg -e jpeg -e png -e webp -e gif -e bmp " +
    "    -E node_modules -E .git -E dist -E target -E __pycache__ -E .venv -E venv " +
    "    -E .cache -E .local -E .npm -E .cargo -E .flatpak " +
    "    . \"$home\" 2>/dev/null | inside; " +
    "  exit 0; " +
    "fi; " +
    "set --; " +
    "for d in Pictures Downloads Desktop Documents; do " +
    "  [ -d \"$home/$d\" ] && set -- \"$@\" \"$home/$d\"; " +
    "done; " +
    "if [ $# -eq 0 ]; then set -- \"$home\"; depth=2; else depth=3; fi; " +
    "wrap find -P \"$@\" -xdev -maxdepth \"$depth\" " +
    "  \\( -name node_modules -o -name .git -o -name .cache -o -name .local \\) -prune " +
    "  -o -type f \\( -iname '*.jpg' -o -iname '*.jpeg' -o -iname '*.png' -o -iname '*.webp' -o -iname '*.gif' \\) -print 2>/dev/null | " +
    "awk 'BEGIN{n=0} { print; n++; if (n>=36) exit }' | inside"

  readonly property string readBody: "head -c 200000 \"$1\""

  readonly property string pdfBody: "src=\"$1\"; out=\"$2\"; " +
    "if ! command -v pdftoppm >/dev/null 2>&1; then printf '%s\\n' POPPLER_MISSING; exit 0; fi; " +
    "ulimit -t 8 2>/dev/null; ulimit -v 1048576 2>/dev/null; ulimit -f 16384 2>/dev/null; " +
    "mkdir -p \"$out\" || exit 0; " +
    "rm -f \"$out\"/page*.png; " +
    "n=12; " +
    "if command -v pdfinfo >/dev/null 2>&1; then " +
    "  p=$(pdfinfo \"$src\" 2>/dev/null | awk '/^Pages:/{print $2}'); " +
    "  case \"$p\" in ''|*[!0-9]*) p=12 ;; esac; " +
    "  if [ \"$p\" -gt 0 ] && [ \"$p\" -lt 12 ]; then n=$p; fi; " +
    "fi; " +
    "if command -v timeout >/dev/null 2>&1; then timeout -k 1 8 pdftoppm -png -r 110 -f 1 -l \"$n\" \"$src\" \"$out/page\" >/dev/null 2>&1; " +
    "else pdftoppm -png -r 110 -f 1 -l \"$n\" \"$src\" \"$out/page\" >/dev/null 2>&1; fi; " +
    "ls -1 \"$out\"/page*.png 2>/dev/null"

  readonly property string imageBody: "src=\"$1\"; out=\"$2\"; edge=\"${3:-2048}\"; force=\"${4:-0}\"; " +
    "case \"$edge\" in ''|*[!0-9]*) edge=2048 ;; esac; " +
    "MAXPX=20000000; MAXSIDE=8192; " +
    "ident=$(command -v identify || true); " +
    "conv=$(command -v magick || command -v convert || true); " +
    "ff=$(command -v ffmpeg || true); " +
    "mkdir -p \"$(dirname \"$out\")\" || { printf '%s' TOO_LARGE; exit 0; }; " +
    "ulimit -t 8 2>/dev/null; ulimit -v 524288 2>/dev/null; ulimit -f 8192 2>/dev/null; " +
    "px=0; w=0; h=0; " +
    "if [ -n \"$ident\" ]; then " +
    "  w=$(\"$ident\" -ping -format '%w' \"$src\" 2>/dev/null || printf '0'); " +
    "  h=$(\"$ident\" -ping -format '%h' \"$src\" 2>/dev/null || printf '0'); " +
    "  case \"$w\" in ''|*[!0-9]*) w=0 ;; esac; " +
    "  case \"$h\" in ''|*[!0-9]*) h=0 ;; esac; " +
    "  px=$((w*h)); " +
    "fi; " +
    "if [ \"$px\" -gt \"$MAXPX\" ]; then printf '%s' TOO_LARGE; exit 0; fi; " +
    "if [ \"$force\" != 1 ] && [ \"$w\" -gt 0 ] && [ \"$h\" -gt 0 ] && [ \"$w\" -le \"$edge\" ] && [ \"$h\" -le \"$edge\" ]; then printf '%s' \"$src\"; exit 0; fi; " +
    "ok=0; " +
    "if [ -n \"$conv\" ]; then " +
    "  \"$conv\" \"$src\" -limit memory 256MiB -limit map 256MiB -resize \"${edge}x${edge}>\" \"$out\" >/dev/null 2>&1 && [ -s \"$out\" ] && ok=1; " +
    "fi; " +
    "if [ \"$ok\" != 1 ] && [ -n \"$ff\" ]; then " +
    "  vf=\"scale=w='min(iw,$edge)':h='min(ih,$edge)':force_original_aspect_ratio=decrease\"; " +
    "  if command -v timeout >/dev/null 2>&1; then timeout -k 1 8 \"$ff\" -hide_banner -loglevel error -nostdin -y -i \"$src\" -frames:v 1 -vf \"$vf\" -q:v 3 \"$out\" >/dev/null 2>&1; " +
    "  else \"$ff\" -hide_banner -loglevel error -nostdin -y -i \"$src\" -frames:v 1 -vf \"$vf\" -q:v 3 \"$out\" >/dev/null 2>&1; fi; " +
    "  [ -s \"$out\" ] && ok=1; " +
    "fi; " +
    "if [ \"$ok\" = 1 ]; then printf '%s' \"$out\"; exit 0; fi; " +
    "printf '%s' TOO_LARGE"

  readonly property string videoBody: "src=\"$1\"; out=\"$2\"; " +
    "ff=$(command -v ffmpeg || true); " +
    "if [ -z \"$ff\" ]; then exit 0; fi; " +
    "ulimit -t 8 2>/dev/null; ulimit -v 1048576 2>/dev/null; ulimit -f 8192 2>/dev/null; " +
    "mkdir -p \"$(dirname \"$out\")\" || exit 0; " +
    "grab() { if command -v timeout >/dev/null 2>&1; then timeout -k 1 7 \"$ff\" -hide_banner -loglevel error -nostdin -y -ss \"$1\" -i \"$src\" -frames:v 1 -vf 'scale=640:-2' -q:v 3 \"$out\" >/dev/null 2>&1; " +
    "else \"$ff\" -hide_banner -loglevel error -nostdin -y -ss \"$1\" -i \"$src\" -frames:v 1 -vf 'scale=640:-2' -q:v 3 \"$out\" >/dev/null 2>&1; fi; }; " +
    "grab 1; " +
    "if [ ! -s \"$out\" ]; then grab 0; fi; " +
    "if [ -s \"$out\" ]; then printf '%s' \"$out\"; fi"

  readonly property string audioCoverBody: "src=\"$1\"; out=\"$2\"; " +
    "ff=$(command -v ffmpeg || true); " +
    "if [ -z \"$ff\" ]; then exit 0; fi; " +
    "ulimit -t 6 2>/dev/null; ulimit -v 262144 2>/dev/null; ulimit -f 4096 2>/dev/null; " +
    "mkdir -p \"$(dirname \"$out\")\" || exit 0; " +
    "if [ -s \"$out\" ]; then printf '%s' \"$out\"; exit 0; fi; " +
    "grab() { if command -v timeout >/dev/null 2>&1; then timeout -k 1 5 \"$ff\" -hide_banner -loglevel error -nostdin -y -i \"$src\" -an -frames:v 1 -vf 'scale=640:640:force_original_aspect_ratio=decrease' -q:v 3 \"$out\" >/dev/null 2>&1; " +
    "else \"$ff\" -hide_banner -loglevel error -nostdin -y -i \"$src\" -an -frames:v 1 -vf 'scale=640:640:force_original_aspect_ratio=decrease' -q:v 3 \"$out\" >/dev/null 2>&1; fi; }; " +
    "grab; " +
    "if [ -s \"$out\" ]; then printf '%s' \"$out\"; fi"

  readonly property string zipBody: "src=\"$1\"; " +
    "ulimit -t 4 2>/dev/null; ulimit -v 262144 2>/dev/null; " +
    "{ listed=0; " +
    "  case \"$src\" in " +
    "    *.zip|*.ZIP|*.jar|*.apk|*.whl|*.egg|*.crx|*.xpi) " +
    "      if command -v zipinfo >/dev/null 2>&1; then zipinfo -1 \"$src\" 2>/dev/null; listed=1; " +
    "      elif command -v unzip >/dev/null 2>&1; then unzip -Z1 \"$src\" 2>/dev/null; listed=1; " +
    "      elif command -v bsdtar >/dev/null 2>&1; then bsdtar -tf \"$src\" 2>/dev/null; listed=1; fi ;; " +
    "    *) " +
    "      if command -v bsdtar >/dev/null 2>&1; then bsdtar -tf \"$src\" 2>/dev/null; listed=1; " +
    "      elif command -v tar >/dev/null 2>&1; then tar -tf \"$src\" 2>/dev/null; listed=1; fi ;; " +
    "  esac; " +
    "  if [ \"$listed\" = 0 ]; then printf '%s\\n' ZIP_TOOL_MISSING; fi; " +
    "} | head -n 400 | head -c 200000"

  function underHome(p) {
    var home = String(root.home || "")
    if (home.length < 6 || home === "/" || home === "/home") return false
    while (home.length > 1 && home.charAt(home.length - 1) === "/") home = home.slice(0, home.length - 1)
    if (p === home) return true
    if (p.indexOf(home + "/") !== 0) return false
    if (p.indexOf("/../") >= 0) return false
    return true
  }
  function escapeHtml(s) {
    return String(s || "").replace(/&/g, "&" + "amp;").replace(/</g, "&" + "lt;").replace(/>/g, "&" + "gt;")
  }
  function applyPathList(text, usedBackend) {
    var lines = String(text || "").split(/\r?\n/)
    var hits = []
    var seen = ({})
    for (var i = 0; i < lines.length && hits.length < 24; i++) {
      var p = String(lines[i] || "").replace(/^\s+|\s+$/g, "").replace(/^'+|'+$/g, "")
      if (!p.length || p.charAt(0) !== "/") continue
      if (!root.underHome(p)) continue
      if (seen[p]) continue
      seen[p] = true
      var slash = p.lastIndexOf("/")
      var name = slash >= 0 ? p.slice(slash + 1) : p
      if (!name.length) continue
      var lower = name.toLowerCase()
      if (lower.indexOf(".pyc") === lower.length - 4 || lower.indexOf(".pyo") === lower.length - 4) continue
      if (lower.indexOf(".trashinfo") >= 0) continue
      hits.push({ path: p, name: name, kind: Format.kindOf(p, false), score: 100, mtime: 0, size: 0 })
    }
    root.lastResults = hits
    root.backend = usedBackend || "search"
    root.resultsRevision += 1
    root.lastStatus = "hits:" + hits.length
    root.enqueueThumbs(hits)
  }
  function applyImageList(text) {
    var lines = String(text || "").split(/\r?\n/)
    var hits = []
    var seen = ({})
    for (var i = 0; i < lines.length && hits.length < 36; i++) {
      var p = String(lines[i] || "").replace(/^\s+|\s+$/g, "").replace(/^'+|'+$/g, "")
      if (!p.length || p.charAt(0) !== "/") continue
      if (!root.underHome(p)) continue
      if (seen[p]) continue
      if (Format.kindOf(p, false) !== "image") continue
      seen[p] = true
      var slash = p.lastIndexOf("/")
      var name = slash >= 0 ? p.slice(slash + 1) : p
      if (!name.length) continue
      hits.push({ path: p, name: name, kind: "image", score: 100, mtime: 0, size: 0 })
    }
    if (hits.length)
      root.lastImages = hits
  }
  function diskHuman(n) {
    var v = Number(n) || 0
    var tb = 1024 * 1024 * 1024 * 1024
    var gb = 1024 * 1024 * 1024
    if (v >= tb) return (v / tb).toFixed(1) + " TB"
    if (v >= gb) {
      var g = v / gb
      return (g >= 10 ? g.toFixed(0) : g.toFixed(1)) + " GB"
    }
    return Format.humanSize(v)
  }
  function applyDf(text) {
    var lines = String(text || "").split(/\r?\n/)
    var row = ""
    for (var i = 0; i < lines.length; i++) {
      var t = String(lines[i] || "").replace(/^\s+|\s+$/g, "")
      if (t.length && t.indexOf("Size") < 0 && t.indexOf("Avail") < 0) row = t
    }
    if (!row.length) return
    var parts = row.split(/\s+/)
    var size = Number(parts[0])
    var avail = Number(parts[1])
    if (!(size > 0)) return
    root.diskTotal = size
    root.diskUsedFrac = Math.max(0, Math.min(1, (size - avail) / size))
    root.diskLabel = root.diskHuman(avail) + " free of " + root.diskHuman(size)
  }
  function sanitize(q) { return String(q || "").replace(/[*?[\]\\'"]/g, "") }
  function query(q) {
    root.searchNeedle = root.sanitize(q)
    Qt.callLater(root.startSearch)
    return String(root.resultsRevision + 1)
  }
  function startSearch() {
    if (searchProc.running) { searchProc.running = false; Qt.callLater(root.startSearch); return }
    if (!root.searchNeedle.length) {
      searchProc.command = ["sh", "-c", root.recentBody, "overview-recent", root.home]
      root.backend = "recent"
    } else {
      searchProc.command = ["sh", "-c", root.searchBody, "overview-search", root.searchNeedle, root.home]
      root.backend = "search"
    }
    searchProc.running = true
    root.searchRunning = true
    root.lastStatus = "searching"
    searchKill.restart()
  }
  function applyTextPreview(raw) {
    var s = String(raw || "")
    if (s.length > root.previewBytes) s = s.slice(0, root.previewBytes)
    var binary = s.indexOf("\0") >= 0
    var large = s.length >= root.previewBytes
    if (binary) {
      var hex = ""
      var n = Math.min(s.length, 256)
      for (var i = 0; i < n; i++) {
        var c = s.charCodeAt(i) & 255
        hex += (c < 16 ? "0" : "") + c.toString(16) + ((i + 1) % 16 === 0 ? "\n" : " ")
      }
      root.lastPreview = { kind: "hex", path: root.previewPath, label: Format.basename(root.previewPath), hex: hex, text: hex }
    } else {
      root.lastPreview = {
        kind: "code",
        path: root.previewPath,
        html: "<pre>" + root.escapeHtml(s) + "</pre>",
        text: s,
        large: large,
        label: Format.basename(root.previewPath)
      }
    }
    root.previewRevision += 1
  }
  function requestPreview(path, page) {
    var p = String(path || "")
    root.previewPath = p
    if (!p.length) { root.lastPreview = ({}); root.previewRevision += 1; return "0" }
    if (!root.underHome(p)) { root.lastPreview = ({}); root.previewRevision += 1; return "0" }
    var kind = Format.kindOf(p, false)
    if (kind === "image") {
      if (imageProc.running) imageProc.running = false
      imageKill.restart()
      var cache = Format.imageThumbPath(p, root.home)
      imageProc.command = ["sh", "-c", root.imageBody, "overview-image", p, cache, "2048", "0"]
      imageProc.running = true
      root.lastPreview = { kind: "image", path: "", blocked: false, label: Format.basename(p) }
      return String(root.previewRevision + 1)
    }
    if (kind === "pdf") {
      if (pdfProc.running) pdfProc.running = false
      pdfKill.restart()
      var dir = root.home + "/.cache/overview/pdf/" + Format.basename(p).replace(/[^A-Za-z0-9._-]/g, "_")
      pdfProc.command = ["sh", "-c", root.pdfBody, "overview-pdf", p, dir]
      pdfProc.running = true
      root.lastPreview = { kind: "pdf", path: p, pages: [], label: Format.basename(p) }
      return String(root.previewRevision + 1)
    }
    if (kind === "video") {
      if (videoProc.running) videoProc.running = false
      videoKill.restart()
      var vout = Format.videoThumbPath(p, root.home)
      videoProc.command = ["sh", "-c", root.videoBody, "overview-video", p, vout]
      videoProc.running = true
      root.lastPreview = { kind: "video", path: p, thumb: vout, label: Format.basename(p) }
      return String(root.previewRevision + 1)
    }
    if (kind === "audio") {
      if (audioProc.running) audioProc.running = false
      audioKill.restart()
      var aout = Format.audioCoverPath(p, root.home)
      audioProc.command = ["sh", "-c", root.audioCoverBody, "overview-cover", p, aout]
      audioProc.running = true
      root.lastPreview = { kind: "audio", path: p, cover: "", label: Format.basename(p) }
      return String(root.previewRevision + 1)
    }
    if (kind === "zip") {
      if (zipProc.running) zipProc.running = false
      zipKill.restart()
      zipProc.command = ["sh", "-c", root.zipBody, "overview-zip", p]
      zipProc.running = true
      root.lastPreview = { kind: "zip", path: p, text: "", label: Format.basename(p) }
      return String(root.previewRevision + 1)
    }
    if (textProc.running) textProc.running = false
    readKill.restart()
    textProc.command = ["sh", "-c", root.readBody, "overview-read", p]
    textProc.running = true
    return String(root.previewRevision + 1)
  }
  function preview(arg) {
    var path = String(arg || "")
    if (path.length && path.charAt(0) === "{") {
      try { path = String(JSON.parse(path).path || "") } catch (e) {}
    }
    return root.requestPreview(path, 1)
  }
  function prefetch(path) { return root.requestPreview(path, 1) }
  function openPath(path) {
    var p = String(path || "")
    if (!p.length || !root.underHome(p)) return "empty"
    var quoted = "'" + p.replace(/'/g, "'\\''") + "'"
    Quickshell.execDetached(["hyprctl", "dispatch", "exec", "xdg-open " + quoted])
    return "ok"
  }
  function reveal(path) {
    if (!path || !root.underHome(String(path))) return "empty"
    var quoted = "'" + String(path).replace(/'/g, "'\\''") + "'"
    Quickshell.execDetached(["hyprctl", "dispatch", "exec", "xdg-open " + quoted])
    return "ok"
  }
  function snapshotJson() {
    return JSON.stringify({
      resultsRevision: root.resultsRevision,
      previewRevision: root.previewRevision,
      results: root.lastResults,
      preview: root.lastPreview,
      indexing: root.searchRunning,
      backend: root.backend,
      lastStatus: root.lastStatus,
      home: root.home,
      diskLabel: root.diskLabel,
      diskUsedFrac: root.diskUsedFrac,
      diskTotal: root.diskTotal,
      images: root.lastImages
    })
  }
  function queryImages() {
    if (imageSearchProc.running) return "ok"
    imageSearchProc.command = ["sh", "-c", root.imageSearchBody, "overview-images", root.home]
    imageSearchProc.running = true
    return "ok"
  }
  function enqueueThumbs(hits) {
    var q = []
    for (var i = 0; i < hits.length; i++) {
      var hit = hits[i]
      if (!hit || !hit.path) continue
      if (hit.kind === "video") {
        var vout = Format.videoThumbPath(hit.path, root.home)
        if (vout.length) q.push({ kind: "video", src: String(hit.path), out: vout })
      } else if (hit.kind === "image") {
        var iout = Format.imageThumbPath(hit.path, root.home)
        if (iout.length) q.push({ kind: "image", src: String(hit.path), out: iout })
      } else if (hit.kind === "audio") {
        var aout = Format.audioCoverPath(hit.path, root.home)
        if (aout.length) q.push({ kind: "audio", src: String(hit.path), out: aout })
      }
    }
    root.videoQueue = q
    Qt.callLater(root.runThumbQueue)
  }
  function runThumbQueue() {
    if (thumbProc.running) return
    if (!root.videoQueue.length) return
    var job = root.videoQueue[0]
    root.videoQueue = root.videoQueue.slice(1)
    if (!job || !root.underHome(job.src)) { Qt.callLater(root.runThumbQueue); return }
    if (job.kind === "image")
      thumbProc.command = ["sh", "-c", root.imageBody, "overview-ithumb", job.src, job.out, "640", "1"]
    else if (job.kind === "audio")
      thumbProc.command = ["sh", "-c", root.audioCoverBody, "overview-athumb", job.src, job.out]
    else
      thumbProc.command = ["sh", "-c", root.videoBody, "overview-vthumb", job.src, job.out]
    thumbProc.running = true
  }
  Process {
    id: imageProc
    running: false
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        imageKill.stop()
        var out = String(text || "").replace(/^\s+|\s+$/g, "")
        var cachePrefix = root.home + "/.cache/overview/"
        var blocked = !out.length || out === "TOO_LARGE"
        var safe = !blocked && (out.indexOf(cachePrefix) === 0 || (out === root.previewPath && root.underHome(out)))
        if (!safe) {
          root.lastPreview = { kind: "image", path: "", blocked: true, label: Format.basename(root.previewPath) }
        } else {
          root.lastPreview = { kind: "image", path: out, blocked: false, label: Format.basename(root.previewPath) }
        }
        root.previewRevision += 1
      }
    }
    onExited: imageKill.stop()
  }
  Timer {
    id: imageKill
    interval: 8000
    repeat: false
    onTriggered: { if (imageProc.running) imageProc.running = false }
  }
  Process {
    id: textProc
    running: false
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        readKill.stop()
        root.applyTextPreview(text)
      }
    }
    onExited: readKill.stop()
  }
  Process {
    id: pdfProc
    running: false
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        pdfKill.stop()
        var t = String(text || "")
        if (t.indexOf("POPPLER_MISSING") === 0) {
          root.lastPreview = { kind: "pdf", path: root.previewPath, need_poppler: true, pages: [], label: "PDF" }
          root.previewRevision += 1
          return
        }
        var pages = []
        var prefix = root.home + "/.cache/overview/"
        var lines = t.split(/\r?\n/)
        for (var i = 0; i < lines.length && pages.length < 12; i++) {
          var pg = String(lines[i] || "").replace(/^\s+|\s+$/g, "")
          if (!pg.length || pg.charAt(0) !== "/") continue
          if (pg.indexOf(prefix) !== 0) continue
          if (pg.indexOf("..") >= 0) continue
          var lower = pg.toLowerCase()
          if (lower.length < 4 || lower.indexOf(".png") !== lower.length - 4) continue
          pages.push(pg)
        }
        root.lastPreview = {
          kind: "pdf",
          path: root.previewPath,
          pages: pages,
          label: Format.basename(root.previewPath),
          need_poppler: false
        }
        root.previewRevision += 1
      }
    }
    onExited: pdfKill.stop()
  }
  Timer {
    id: readKill
    interval: 4000
    repeat: false
    onTriggered: { if (textProc.running) textProc.running = false }
  }
  Timer {
    id: pdfKill
    interval: 10000
    repeat: false
    onTriggered: { if (pdfProc.running) pdfProc.running = false }
  }
  Process {
    id: videoProc
    running: false
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        videoKill.stop()
        var out = String(text || "").replace(/^\s+|\s+$/g, "")
        if (!out.length || out.indexOf(root.home + "/.cache/overview/") !== 0)
          out = Format.videoThumbPath(root.previewPath, root.home)
        root.lastPreview = {
          kind: "video",
          path: root.previewPath,
          thumb: out,
          stamp: Date.now(),
          label: Format.basename(root.previewPath)
        }
        root.previewRevision += 1
      }
    }
    onExited: videoKill.stop()
  }
  Timer {
    id: videoKill
    interval: 8000
    repeat: false
    onTriggered: { if (videoProc.running) videoProc.running = false }
  }
  Process {
    id: audioProc
    running: false
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        audioKill.stop()
        var out = String(text || "").replace(/^\s+|\s+$/g, "")
        if (!out.length || out.indexOf(root.home + "/.cache/overview/") !== 0)
          out = ""
        root.lastPreview = {
          kind: "audio",
          path: root.previewPath,
          cover: out,
          label: Format.basename(root.previewPath)
        }
        root.previewRevision += 1
      }
    }
    onExited: audioKill.stop()
  }
  Timer {
    id: audioKill
    interval: 6000
    repeat: false
    onTriggered: { if (audioProc.running) audioProc.running = false }
  }
  Process {
    id: zipProc
    running: false
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        zipKill.stop()
        var t = String(text || "")
        if (t.indexOf("ZIP_TOOL_MISSING") === 0) {
          root.lastPreview = {
            kind: "zip",
            path: root.previewPath,
            need_tool: true,
            text: "install unzip or libarchive (bsdtar) to list archives",
            label: Format.basename(root.previewPath)
          }
        } else {
          root.lastPreview = {
            kind: "zip",
            path: root.previewPath,
            text: t,
            label: Format.basename(root.previewPath)
          }
        }
        root.previewRevision += 1
      }
    }
    onExited: zipKill.stop()
  }
  Timer {
    id: zipKill
    interval: 5000
    repeat: false
    onTriggered: { if (zipProc.running) zipProc.running = false }
  }
  Process {
    id: thumbProc
    running: false
    stdout: StdioCollector { waitForEnd: true }
    onExited: Qt.callLater(root.runThumbQueue)
  }
  Process {
    id: searchProc
    running: false
    stdout: StdioCollector {
      id: searchOut
      waitForEnd: true
      onStreamFinished: {
        searchKill.stop()
        root.searchRunning = false
        root.applyPathList(text, root.backend || "search")
      }
    }
    onExited: function(code) {
      searchKill.stop()
      root.searchRunning = false
      var collected = String(searchOut.text || "")
      if (root.lastStatus === "searching")
        root.applyPathList(collected, root.backend || "search")
    }
  }
  Timer {
    id: searchKill
    interval: 4000
    repeat: false
    onTriggered: {
      if (searchProc.running)
        searchProc.running = false
    }
  }
  Process {
    id: dfProc
    running: false
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.applyDf(text)
    }
  }
  Timer {
    interval: 20000
    running: true
    repeat: true
    triggeredOnStart: true
    onTriggered: {
      dfProc.command = ["df", "-B1", "--output=size,avail", root.home]
      dfProc.running = true
    }
  }
  Process {
    id: imageSearchProc
    running: false
    stdout: StdioCollector {
      id: imageSearchOut
      waitForEnd: true
      onStreamFinished: root.applyImageList(text)
    }
    onExited: function() {
      root.applyImageList(String(imageSearchOut.text || ""))
    }
  }
  IpcHandler {
    target: "io.github.overview"
    function ping(arg: string): string { return "ok" }
    function status(arg: string): string { return root.snapshotJson() }
    function snapshot(arg: string): string { return root.snapshotJson() }
    function query(q: string): string { return String(root.query(q)) }
    function queryImages(arg: string): string { return root.queryImages() }
    function preview(path: string): string { return root.preview(path) }
    function prefetch(path: string): string { return root.prefetch(path) }
    function open(path: string): string { return root.openPath(path) }
    function reveal(path: string): string { return root.reveal(path) }
    function warmup(arg: string): string { return "ok" }
    function toggle(arg: string): string {
      Quickshell.execDetached(["omarchy-shell", "shell", "toggle", root.pluginId, arg && arg.length ? arg : "{}"])
      return "ok"
    }
  }
  Component.onCompleted: {
    root.lastResults = []
    root.backend = "idle"
    root.resultsRevision += 1
  }
}
