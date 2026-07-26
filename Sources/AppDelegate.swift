import AppKit
import ServiceManagement

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var board: BoardController!
    /// Polled instead of using a global mouse monitor: a timer needs no
    /// Accessibility grant and fires reliably regardless of which app is front.
    private var hoverTimer: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Before anything else: this is what makes ⌘Z / ⌘A / ⌘C / ⌘V work at
        // all. An LSUIElement app draws no menu bar, but AppKit still resolves
        // every ⌘-chord through the main menu.
        MainMenu.install(appDelegate: self)

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let btn = statusItem.button {
            let cfg = NSImage.SymbolConfiguration(pointSize: 14, weight: .regular)
            btn.image = NSImage(systemSymbolName: "checklist", accessibilityDescription: "DeskNote")?
                .withSymbolConfiguration(cfg)
        }
        statusItem.menu = NSMenu()
        statusItem.menu?.delegate = self

        if Store.shared.notes.isEmpty {
            seedFirstRun()
        }

        board = BoardController()
        // Anything that changes the *set* of notes or tags rebuilds the strip.
        Store.shared.onChange = { [weak self] in self?.board.reload() }
        if Store.shared.allHidden { setAllHidden(true) }

        hoverTimer = Timer.scheduledTimer(withTimeInterval: 0.12, repeats: true) { [weak self] _ in
            self?.checkDockHover()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        Store.shared.saveNow()
    }

    // MARK: First run

    private func seedFirstRun() {
        let seeds: [(String, NoteColor, [String])] = [
            ("论文 / 实验", .red, ["画 Pareto front 图", "写 method 章节", "约导师 review"]),
            ("实习任务", .blue, ["端云调度实验", "周会对齐"]),
            ("私事", .green, ["订机票"]),
        ]
        for (title, color, items) in seeds {
            var n = Note()
            n.title = title
            n.color = color
            n.items = items.map { ChecklistItem(text: $0) }
            Store.shared.add(n)
        }
    }

    // MARK: Dock hover

    /// Drives both halves of the docked window's behaviour: the cursor touching
    /// the sliver slides it out, and the controller's own timing rules decide
    /// when it goes back. Auto-hide lives there rather than here because it has
    /// to see the focused field and the last keystroke.
    private func checkDockHover() {
        guard Store.shared.dock != .none, board != nil, board.window.isVisible else { return }
        if board.isRetracted {
            if board.dockHotZone.contains(NSEvent.mouseLocation) {
                board.expand(animated: true)
            }
        } else {
            board.tickAutoHide()
        }
    }

    // MARK: Actions

    @objc func newNote() {
        if Store.shared.allHidden { setAllHidden(false) }
        board.tabBarAddNote()
    }

    @objc private func focusNote(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? UUID else { return }
        if Store.shared.allHidden { setAllHidden(false) }
        board.select(id)
        if Store.shared.dock != .none { board.expand(animated: true) }
        board.window.orderFrontRegardless()
        board.window.makeKeyAndOrderFront(nil)
    }

    @objc func toggleHideAll() {
        setAllHidden(!Store.shared.allHidden)
    }

    private func setAllHidden(_ hidden: Bool) {
        Store.shared.allHidden = hidden
        if hidden { board.window.orderOut(nil) } else { board.window.orderFront(nil) }
    }

    @objc private func toggleTagFilter(_ sender: NSMenuItem) {
        guard let tag = sender.representedObject as? String else { return }
        Store.shared.toggleMute(tag)
    }

    @objc private func toggleLoginItem() {
        do {
            if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
            } else {
                try SMAppService.mainApp.register()
            }
        } catch {
            let a = NSAlert()
            a.messageText = "无法自动设置开机启动"
            a.informativeText = "请到「系统设置 → 通用 → 登录项」手动添加 DeskNote。\n\n（\(error.localizedDescription)）"
            a.runModal()
        }
    }

    @objc private func revealData() {
        let url = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("DeskNote")
        NSWorkspace.shared.selectFile(url.appendingPathComponent("notes.json").path,
                                      inFileViewerRootedAtPath: url.path)
    }

    @objc func quit() {
        Store.shared.saveNow()
        NSApp.terminate(nil)
    }
}

// MARK: - Status menu

extension AppDelegate: NSMenuDelegate {
    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()

        add(menu, "新建清单", #selector(newNote), key: "n")
        menu.addItem(.separator())

        let notes = Store.shared.notes
        if notes.isEmpty {
            let mi = NSMenuItem(title: "（还没有清单）", action: nil, keyEquivalent: "")
            mi.isEnabled = false
            menu.addItem(mi)
        } else {
            let selected = Store.shared.selected
            for n in notes {
                let title = n.items.isEmpty ? n.title : "\(n.title)   \(n.progressText)"
                let mi = NSMenuItem(title: title, action: #selector(focusNote(_:)), keyEquivalent: "")
                mi.target = self
                mi.representedObject = n.id
                mi.state = (n.id == selected) ? .on : .off
                mi.image = NSImage(size: NSSize(width: 10, height: 10), flipped: false) { rect in
                    n.color.accent.setFill()
                    NSBezierPath(ovalIn: rect.insetBy(dx: 1, dy: 1)).fill()
                    return true
                }
                menu.addItem(mi)
            }
        }

        menu.addItem(.separator())

        let tags = Store.shared.allTags
        if !tags.isEmpty {
            let filter = NSMenuItem(title: "按标签显示", action: nil, keyEquivalent: "")
            let sub = NSMenu()
            for t in tags {
                let mi = NSMenuItem(title: t, action: #selector(toggleTagFilter(_:)), keyEquivalent: "")
                mi.target = self
                mi.representedObject = t
                mi.state = Store.shared.mutedTags.contains(t) ? .off : .on
                sub.addItem(mi)
            }
            filter.submenu = sub
            menu.addItem(filter)
        }

        add(menu, Store.shared.allHidden ? "显示便签窗口" : "隐藏便签窗口",
            #selector(toggleHideAll), key: "h")

        menu.addItem(.separator())

        // The same menu the note's own right-click offers. People look for
        // settings under the menu-bar icon, so it has to be here too — and
        // sharing one builder keeps the two from disagreeing.
        let setItem = NSMenuItem(title: "设置", action: nil, keyEquivalent: ",")
        setItem.submenu = board.settingsMenu()
        menu.addItem(setItem)

        menu.addItem(.separator())
        let login = add(menu, "开机时启动", #selector(toggleLoginItem))
        login.state = (SMAppService.mainApp.status == .enabled) ? .on : .off
        add(menu, "打开数据文件夹", #selector(revealData))
        menu.addItem(.separator())
        add(menu, "退出 DeskNote", #selector(quit), key: "q")
    }

    @discardableResult
    private func add(_ menu: NSMenu, _ title: String, _ action: Selector,
                     key: String = "") -> NSMenuItem {
        let mi = NSMenuItem(title: title, action: action, keyEquivalent: key)
        mi.target = self
        menu.addItem(mi)
        return mi
    }
}
