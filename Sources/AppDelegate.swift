import AppKit
import ServiceManagement

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var board: BoardController!
    /// Polled instead of using a global mouse monitor: a timer needs no
    /// Accessibility grant and fires reliably regardless of which app is front.
    ///
    /// Only alive while the window is actually docked — see `syncHoverTimer`.
    private var hoverTimer: Timer?
    /// Ticked items are swept a day after they were ticked. On a timer as well
    /// as at launch because this app is meant to be left running for weeks —
    /// a launch-only sweep would almost never fire for the people it is for.
    ///
    /// Six-hourly rather than often. The threshold is a day, so a coarse timer
    /// only means a row leaves somewhere in the six hours after it is due,
    /// which nobody is watching for — and a sweep that ran every few minutes
    /// would spend the whole day waking up to find nothing to do.
    private var sweepTimer: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Before anything else: this is what makes ⌘Z / ⌘A / ⌘C / ⌘V work at
        // all. An LSUIElement app draws no menu bar, but AppKit still resolves
        // every ⌘-chord through the main menu.
        MainMenu.install(appDelegate: self)

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let btn = statusItem.button {
            let cfg = NSImage.SymbolConfiguration(pointSize: 14, weight: .regular)
            btn.image = NSImage(systemSymbolName: "checklist", accessibilityDescription: "Eaves")?
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

        syncHoverTimer()
        Store.shared.onDockChange = { [weak self] in self?.syncHoverTimer() }

        sweep()
        sweepTimer = Timer.scheduledTimer(withTimeInterval: 6 * 3600, repeats: true) { [weak self] _ in
            self?.sweep()
        }
    }

    /// Never while something is being typed into: the sweep rebuilds the list,
    /// and a rebuild takes the field editor with it. Nothing is lost by waiting
    /// — the next pass will find the same rows, and one that has already sat
    /// there a day is in no hurry.
    private func sweep() {
        guard let board = board, !board.isEditing else { return }
        if Store.shared.sweepDone() { board.reload() }
    }

    func applicationWillTerminate(_ notification: Notification) {
        Store.shared.saveNow()
    }

    // MARK: First run

    /// One list with two rows, both of which teach a gesture that is otherwise
    /// invisible: the window docks by being dragged to an edge, and every setting
    /// lives behind a right-click. Seeding more than this would only give the
    /// first-time user someone else's to-dos to delete.
    private func seedFirstRun() {
        var n = Note()
        n.title = L("seed.title")
        n.color = .yellow
        n.items = [ChecklistItem(text: L("seed.item1")),
                   ChecklistItem(text: L("seed.item2"))]
        Store.shared.add(n)
    }

    // MARK: Dock hover

    /// Starts the hover poll while the window is docked and stops it otherwise.
    ///
    /// Undocked, `checkDockHover` has nothing it can do — both halves of it are
    /// behind the same `dock != .none` guard — so leaving the timer running
    /// would be eight wake-ups a second, seven hundred thousand a day, to reach
    /// a `return`. Cheap each time and free never.
    private func syncHoverTimer() {
        let wanted = Store.shared.dock != .none
        guard wanted != (hoverTimer != nil) else { return }
        hoverTimer?.invalidate()
        hoverTimer = wanted
            ? Timer.scheduledTimer(withTimeInterval: 0.12, repeats: true) { [weak self] _ in
                  self?.checkDockHover()
              }
            : nil
    }

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
            a.messageText = L("alert.loginItem.title")
            a.informativeText = L("alert.loginItem.body", error.localizedDescription)
            a.runModal()
        }
    }

    @objc private func revealData() {
        let url = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Eaves")
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

        add(menu, L("menu.newList"), #selector(newNote), key: "n")
        menu.addItem(.separator())

        let notes = Store.shared.notes
        if notes.isEmpty {
            let mi = NSMenuItem(title: L("menu.noLists"), action: nil, keyEquivalent: "")
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
            let filter = NSMenuItem(title: L("menu.filterByTag"), action: nil, keyEquivalent: "")
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

        add(menu, L(Store.shared.allHidden ? "menu.showWindow" : "menu.hideWindow"),
            #selector(toggleHideAll), key: "h")

        menu.addItem(.separator())

        // The same menu the note's own right-click offers. People look for
        // settings under the menu-bar icon, so it has to be here too — and
        // sharing one builder keeps the two from disagreeing.
        let setItem = NSMenuItem(title: L("menu.settings"), action: nil, keyEquivalent: ",")
        setItem.submenu = board.settingsMenu()
        menu.addItem(setItem)

        menu.addItem(.separator())
        let login = add(menu, L("menu.launchAtLogin"), #selector(toggleLoginItem))
        login.state = (SMAppService.mainApp.status == .enabled) ? .on : .off
        add(menu, L("menu.revealData"), #selector(revealData))
        menu.addItem(.separator())
        add(menu, L("menu.quit"), #selector(quit), key: "q")
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
