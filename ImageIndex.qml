import QtQuick
import Quickshell
import Quickshell.Io
import "js/Format.js" as Format

Item {
  id: root
  property string home: ""
  property var images: []
  signal ready()

  function refresh() {
    var h = String(root.home || "")
    if (!h.length) return
    if (proc.running) proc.running = false
    proc.command = ["sh", "-c", root.body, "overview-images", h]
    proc.running = true
  }

  readonly property string body: "start=\"$1\"; " +
    "home=$(cd \"$start\" 2>/dev/null && pwd -P || printf '%s' \"$start\"); " +
    "case \"$home\" in /home/*|/root) ;; *) exit 0 ;; esac; " +
    "ulimit -t 6 2>/dev/null; ulimit -v 262144 2>/dev/null; " +
    "inside() { n=0; ident=$(command -v identify || true); while IFS= read -r p; do " +
    "  [ -z \"$p\" ] && continue; " +
    "  d=$(dirname \"$p\"); b=$(basename \"$p\"); " +
    "  rp=$(cd \"$d\" 2>/dev/null && printf '%s/%s\\n' \"$(pwd -P)\" \"$b\" || printf '%s\\n' \"$p\"); " +
    "  case \"$rp\" in \"$home\"|\"$home\"/*) ;; *) continue ;; esac; " +
    "  if [ -n \"$ident\" ]; then " +
    "    w=$(\"$ident\" -ping -format '%w' \"$rp\" 2>/dev/null || printf '0'); " +
    "    h=$(\"$ident\" -ping -format '%h' \"$rp\" 2>/dev/null || printf '0'); " +
    "    case \"$w\" in ''|*[!0-9]*) continue ;; esac; " +
    "    case \"$h\" in ''|*[!0-9]*) continue ;; esac; " +
    "    [ \"$w\" -gt 0 ] && [ \"$h\" -gt 0 ] || continue; " +
    "    [ \"$w\" -le 8192 ] && [ \"$h\" -le 8192 ] || continue; " +
    "    [ $((w*h)) -le 20000000 ] || continue; " +
    "  fi; " +
    "  printf '%s\\n' \"$rp\"; n=$((n+1)); [ \"$n\" -ge 36 ] && break; " +
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

  function apply(text) {
    var lines = String(text || "").split(/\r?\n/)
    var hits = []
    var seen = ({})
    for (var i = 0; i < lines.length && hits.length < 36; i++) {
      var p = String(lines[i] || "").replace(/^\s+|\s+$/g, "")
      if (!p.length || p.charAt(0) !== "/") continue
      if (seen[p]) continue
      if (Format.kindOf(p, false) !== "image") continue
      seen[p] = true
      var slash = p.lastIndexOf("/")
      var name = slash >= 0 ? p.slice(slash + 1) : p
      if (!name.length) continue
      hits.push({ path: p, name: name, kind: "image" })
    }
    if (hits.length) {
      root.images = hits
      root.ready()
    }
  }

  Process {
    id: proc
    running: false
    stdout: StdioCollector {
      id: out
      waitForEnd: true
    }
    onExited: root.apply(String(out.text || ""))
  }
}
