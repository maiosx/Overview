# Overview

Omarchy shell plugin: search your home folder and preview files from the bar.

![Overview](preview.png)

Fuzzy-find any file and preview it instantly: images, code, PDFs, CSVs — Space to pin, Enter to open.

## Install as an Omarchy plugin

```sh
omarchy plugin add https://github.com/maiosx/Overview.git --enable
```

That clones this repo into `~/.config/omarchy/plugins/io.github.overview/` (named from `manifest.json`), validates the manifest, and enables the overlay, service, and bar widget.

Reload if the shell was already running:

```sh
omarchy-shell shell rescanPlugins
```
Add a Hyprland binding to `~/.config/hypr/bindings.lua`:

```lua
o.bind("SUPER + A", "Overview", "omarchy-shell shell toggle io.github.overview")
```

Choose any unused chord if `SUPER + A` is already bound.


### Manual zip download

1. Download the source zip from [github.com/maiosx/Overview](https://github.com/maiosx/Overview) → **Code → Download ZIP**, or: [https://github.com/maiosx/Overview/archive/refs/heads/main.zip](https://github.com/maiosx/Overview/archive/refs/heads/main.zip)
2. Unpack so `manifest.json` is at the plugin root.
3. Copy into plugins (Omarchy rejects symlinks):

```sh
mkdir -p ~/.config/omarchy/plugins
rm -rf ~/.config/omarchy/plugins/io.github.overview
cp -a Overview-main ~/.config/omarchy/plugins/io.github.overview
omarchy plugin validate ~/.config/omarchy/plugins/io.github.overview
omarchy-shell shell rescanPlugins
omarchy plugin enable io.github.overview
```

On first summon the overlay talks to the **service-owned** helper over `omarchy-shell io.github.overview` (Python `compat/` when the Rust binary is missing). PDF pages rasterize through resource-limited `pdftoppm` when Poppler is installed; images over 20 MP are downsampled before QML sees them. No `build.sh` is required to get a working finder.

The full Rust helper (`nucleo` ranking, sqlite frecency, isolated PDF children, 20 MP downsample) is optional.

```sh
~/.config/omarchy/plugins/io.github.overview/build.sh
```

PDF previews need Poppler (`pdftotext` / `pdftoppm`):

```sh
pacman -S poppler
```

`fd` is the fast live search backend:

```sh
pacman -S fd
```

## Uninstall

```sh
omarchy plugin remove io.github.overview
omarchy-shell shell rescanPlugins
```

Optional leftovers:

```sh
rm -rf ~/.cache/overview ~/.local/state/overview
```

Older versions may have written a bind to `~/.config/hypr/bindings.lua`. Delete any marked `-- BEGIN/END io.github.overview` block if it is still there.

## Usage

Click the search icon in the bar. Overview opens **fullscreen**: a hero preview of the selected file on top, a three-column card grid below. Type to search `$HOME`. Arrow keys move across the grid, Enter opens, Space pins a full-page preview.

## What renders in 1.0

| Format | How |
|---|---|
| Images (png/jpg/webp/svg/gif) | QML `Image` / `AnimatedImage`. Helper downsamples stills over 20 MP. |
| Code / text (~40 langs) | `syntect` → `<font color>` spans only (QML rich text has no CSS classes). Files over 200 KB are truncated and labeled “large file”. |
| PDF | `pdftoppm` in a disposable subprocess with CPU/memory rlimits and a wall-clock kill. No poppler → designed empty state. Enter still opens. |
| CSV / TSV | First 500 rows as a zebra table; delimiter sniffing. |
| Directories | Entry listing + total size. |
| Anything else | Hex head + `file`-style magic. Never a blank pane. |

Video is **not** a player in 1.0. If `ffmpeg` is present the helper extracts a poster frame; otherwise the row shows metadata only.

## Settings

Settings are inline on the `shell.json` `plugins[]` entry.

```json
{
  "id": "io.github.overview",
  "roots": ["~/Documents", "~/Downloads", "~/Desktop"],
  "watchCap": 2000,
  "cacheMb": 500,
  "maxFiles": 500000
}
```

Omit `roots` to index `$HOME` (with the default exclude list).

## IPC

```sh
omarchy-shell shell toggle io.github.overview '{}'
omarchy-shell shell summon io.github.overview '{"path":"/tmp/file.pdf"}'
omarchy-shell shell hide io.github.overview
omarchy-shell io.github.overview status ''
omarchy-shell io.github.overview query invo
omarchy-shell io.github.overview preview '{"path":"/tmp/file.pdf","page":1}'
omarchy-shell io.github.overview snapshot ''
omarchy-shell io.github.overview theme '{"bg":"#1e1e2e","fg":"#cdd6f4","accent":"#89b4fa"}'
omarchy-shell io.github.overview prefetch /tmp/file.pdf
omarchy-shell io.github.overview warmup ''
```

## Plugin identity

| Field | Value |
|-------|-------|
| id | `io.github.overview` |
| name | Overview |
| kinds | overlay, service, bar-widget |
| entry points | Overlay.qml, Service.qml, BarWidget.qml |

## License

MIT — see `LICENSE`.
