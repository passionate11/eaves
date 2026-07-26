<div align="center">

<img src="docs/icon-512.png" width="128" alt="Eaves">

# Eaves · 檐

**A checklist that hangs at the edge of your screen, then tucks itself out of sight.**

[中文说明](README.zh-CN.md)

![macOS 13+](https://img.shields.io/badge/macOS-13%2B-black)
![Universal](https://img.shields.io/badge/binary-Intel%20%2B%20Apple%20Silicon-black)
![MIT](https://img.shields.io/badge/license-MIT-black)

<img src="docs/screenshot-sand.png" width="380" alt="Eaves in the sand theme">

</div>

---

## What it is

A small always-on-top window holding tabbed checklists. Tabs down the left, one
list per tab, each row a todo you can tick off. It floats above everything
including full-screen apps, and when you drag it to a screen edge it tucks
itself away into a thin sliver — brush the sliver with the cursor and it slides
back out.

No account, no sync, no cloud. Everything is two JSON files in
`~/Library/Application Support/Eaves/`.

## Why it exists

Every todo app I tried was either a whole workspace I had to visit, or a
menu-bar dropdown that vanished the moment I clicked away. What I wanted was
the paper sticky note I used to keep on the monitor bezel: always visible while
I work, never in the way when I don't need it, and gone in one gesture.

So this is deliberately small. There is no project hierarchy, no due dates, no
recurring tasks, no notifications. Three lists and a checkbox.

The name is the overhang at the edge of a roof — the thing that sits right on
the border of the building, that you stop noticing once you live under it.

## Features

- **Tabbed lists** — colour-coded, renameable, taggable.
- **Edge docking** — drag near a screen edge and the window snaps into it,
  leaving a hover sliver. Left, right, top or bottom.
- **Auto-hide** — once docked, it retracts on its own after you stop typing and
  move the cursor away. Three speeds.
- **Float on top** — stays above other windows, including full-screen ones.
- **Six themes** — follow-system, paper, sand, graphite, midnight ink, and a
  translucent glass.
- **Two-line rows** — `Tab` from a todo opens a smaller second line under it for
  the detail you don't want in the title.
- **Tag filtering** — hide whole lists from the menu-bar icon by tag.
- **Menu-bar only** — no Dock icon, no window in ⌘Tab. `LSUIElement`.
- **Launch at login**, from the menu-bar menu.
- **Plain-text export** — right-click a tab → copy as text.

<div align="center">
<img src="docs/screenshot-ink.png" width="330" alt="Midnight ink theme">
&nbsp;&nbsp;
<img src="docs/screenshot-glass.png" width="330" alt="Glass theme">
</div>

## Install

There is no signed release build. Eaves is not notarized by Apple, which
means a downloaded `.app` would be blocked by Gatekeeper anyway — building it
yourself is both the honest option and the easy one. It takes about a minute
and needs no Xcode, only the Command Line Tools.

```sh
xcode-select --install        # if you don't already have them
git clone https://github.com/passionate11/eaves.git
cd eaves
./build.sh release
open Eaves.app
```

`./build.sh release` produces a universal binary (`arm64` + `x86_64`),
ad-hoc signed. Drag `Eaves.app` into `/Applications` if you want to keep it.
`./build.sh` with no argument builds an unoptimized binary for your own
architecture, which is faster to iterate on.

Requires macOS 13 or later.

## Using it

The app has no window chrome and no menu bar. Everything lives in two places:
**the menu-bar icon** (☑︎) and **right-clicking the note itself**.

| | |
|---|---|
| `⌘N` | New list |
| `⌘⇧H` | Show / hide the note window |
| `⌘Q` | Quit |
| `Return` | New todo below the current one |
| `Tab` | Jump to the second line of a row, and back |
| `Esc` | Finish editing (or discard an empty second line) |
| `↑` `↓` | Move between rows while typing |
| `⌘Z` `⌘⇧Z` | Undo / redo |

The ⌘-chords need the note window focused — with no Dock icon there is nothing
else to give the app focus. Settings live under the menu-bar icon.

Right-clicking a tab gives you colour, rename, tags, clear-completed, copy as
text, and delete.

**Docking:** drag the window until it touches an edge and let go. It snaps in
and leaves a sliver. To undock, drag it back out, or right-click → 放回桌面.

## Data

```
~/Library/Application Support/Eaves/
├── notes.json      your lists
└── settings.json   window position, theme, dock edge
```

Both are readable JSON, saved on every change. Menu-bar icon → 打开数据文件夹
opens the folder. Back them up however you back up anything else; there is no
sync and there never will be.

## Known limitations

- **The UI is Chinese-only.** All 97 strings are hardcoded. The code is
  otherwise ready for it — pulling them into a `Localizable.strings` is a
  well-scoped first contribution, and [issues are open](https://github.com/passionate11/eaves/issues).
- **One window.** Multiple lists live as tabs in a single window; you can't
  have two notes on screen at once.
- **No sync, no mobile app, no reminders.** By design.

## Building on it

The whole thing is about 3,000 lines of AppKit across seven files, no
dependencies and no package manager:

| File | |
|---|---|
| `Sources/Models.swift` | Note / item models, `Store`, themes, palettes |
| `Sources/BoardController.swift` | The window: docking, auto-hide, menus |
| `Sources/NoteViews.swift` | Tab strip, checklist rows, field editing |
| `Sources/NoteWindow.swift` | Borderless window, drag, no frame constraint |
| `Sources/AppDelegate.swift` | Status item, hover timer, login item |
| `Sources/MainMenu.swift` | The invisible menu that makes ⌘-chords resolve |
| `Tools/` | Icon generation, screenshots, display probing |

Pull requests welcome. The code is commented at the level of *why*, not *what* —
if something looks strange, the comment above it probably explains which bug it
came from.

## Helping out

No donations, no sponsor button, no paid tier — Eaves is MIT and stays that
way. Three things that actually help:

- **Star the repo.** Visibility is the whole game for a tool this small.
- **File a bug** with your macOS version and what you were doing when it broke.
- **Tell me what's missing.** Feature requests shape this more than anything
  else does.

## License

[MIT](LICENSE) © 2026 passionate11
