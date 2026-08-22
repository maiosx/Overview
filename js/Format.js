.pragma library

var IMAGE_EXT = { png: 1, jpg: 1, jpeg: 1, webp: 1, svg: 1, gif: 1, bmp: 1 }
var PDF_EXT = { pdf: 1 }
var CSV_EXT = { csv: 1, tsv: 1 }
var CODE_EXT = { rs: 1, js: 1, ts: 1, py: 1, go: 1, md: 1, qml: 1, json: 1, sh: 1, lua: 1, txt: 1, toml: 1, yml: 1, yaml: 1, css: 1, html: 1, c: 1, h: 1, cpp: 1 }

function extOf(path) {
  var s = String(path || "")
  var slash = s.lastIndexOf("/")
  var base = (slash >= 0 ? s.slice(slash + 1) : s).toLowerCase()
  var dot = base.lastIndexOf(".")
  return dot < 0 ? "" : base.slice(dot + 1)
}
function basename(path) {
  var s = String(path || "")
  var slash = s.lastIndexOf("/")
  return slash >= 0 ? s.slice(slash + 1) : s
}
function dirname(path) {
  var s = String(path || "")
  var slash = s.lastIndexOf("/")
  if (slash <= 0) return slash === 0 ? "/" : ""
  return s.slice(0, slash)
}
function kindOf(path, isDir) {
  if (isDir) return "dir"
  var ext = extOf(path)
  if (IMAGE_EXT[ext]) return "image"
  if (PDF_EXT[ext]) return "pdf"
  if (CSV_EXT[ext]) return "csv"
  if (CODE_EXT[ext]) return "code"
  return "hex"
}
function glyphFor(kind) {
  if (kind === "image") return "▣"
  if (kind === "pdf") return "▤"
  if (kind === "csv") return "▦"
  if (kind === "code") return "⌘"
  if (kind === "dir") return "▢"
  return "⬡"
}
function kindLabel(kind) {
  if (kind === "image") return "Image"
  if (kind === "pdf") return "PDF"
  if (kind === "csv") return "Table"
  if (kind === "code") return "Code"
  if (kind === "dir") return "Folder"
  if (kind === "video") return "Video"
  return "File"
}
function kindTint(kind) {
  if (kind === "image") return "#3d2a4a"
  if (kind === "pdf") return "#3a221c"
  if (kind === "csv") return "#1c3328"
  if (kind === "code") return "#1c2a3d"
  if (kind === "dir") return "#2a2a20"
  return "#24242c"
}
function homeRelative(path, home) {
  var p = String(path || "")
  var h = String(home || "")
  if (h.length && (p === h || p.indexOf(h + "/") === 0))
    return "~" + p.slice(h.length)
  return p
}
function fileUrl(path) {
  var s = String(path || "")
  if (!s.length) return ""
  if (s.indexOf("file:") === 0) return s
  return "file://" + s.split("/").map(encodeURIComponent).join("/")
}
function isRasterPath(path) {
  var ext = extOf(path)
  return ext === "png" || ext === "jpg" || ext === "jpeg" || ext === "webp" || ext === "gif"
}
function localPreview(path) {
  var p = String(path || "")
  var kind = kindOf(p, false)
  if (kind === "image") return { kind: "image", path: p, animated: extOf(p) === "gif" }
  return { kind: kind, path: p, label: kind, hex: "" }
}
function humanSize(n) {
  var v = Number(n) || 0
  if (v < 1024) return v + " B"
  if (v < 1048576) return (v / 1024).toFixed(1) + " KB"
  return (v / 1048576).toFixed(1) + " MB"
}
