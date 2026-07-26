import AppKit

// MARK: - Main menu

/// Builds the application's main menu.
///
/// Eaves is an `LSUIElement` app, so this menu is never *drawn* anywhere —
/// there is no menu bar to draw it in. It is installed purely because the main
/// menu is the table AppKit consults to resolve key equivalents: `NSApplication`
/// offers every ⌘-chord to `mainMenu.performKeyEquivalent(with:)` before the
/// event ever reaches the key window. With no main menu there is nothing to
/// consult, which is why ⌘Z, ⌘A, ⌘C and ⌘V did nothing at all — the shortcuts
/// were never missing from the text fields, they were missing from the app.
///
/// Every item targets `nil`, so each one is dispatched down the responder chain
/// and lands on whatever field editor currently has focus. That is what makes
/// one static menu work for the tab-rename field, the checklist rows and the
/// add-todo field without any of them knowing about it.
enum MainMenu {
    static func install(appDelegate: AppDelegate) {
        let main = NSMenu()
        main.addItem(appItem(target: appDelegate))
        main.addItem(editItem())
        NSApp.mainMenu = main
    }

    private static func appItem(target: AppDelegate) -> NSMenuItem {
        let item = NSMenuItem()
        let menu = NSMenu(title: "Eaves")

        let new = NSMenuItem(title: L("menu.newList"), action: #selector(AppDelegate.newNote),
                             keyEquivalent: "n")
        new.target = target
        menu.addItem(new)

        menu.addItem(.separator())

        let hide = NSMenuItem(title: L("menu.toggleWindow"),
                              action: #selector(AppDelegate.toggleHideAll), keyEquivalent: "h")
        hide.keyEquivalentModifierMask = [.command, .shift]
        hide.target = target
        menu.addItem(hide)

        menu.addItem(.separator())

        let quit = NSMenuItem(title: L("menu.quit"), action: #selector(AppDelegate.quit),
                              keyEquivalent: "q")
        quit.target = target
        menu.addItem(quit)

        item.submenu = menu
        return item
    }

    /// The standard editing chords. `nil` targets on purpose — see the type doc.
    private static func editItem() -> NSMenuItem {
        let item = NSMenuItem()
        let menu = NSMenu(title: L("menu.edit"))

        add(menu, L("menu.undo"), #selector(UndoManager.undo), "z")
        add(menu, L("menu.redo"), #selector(UndoManager.redo), "Z", [.command, .shift])
        menu.addItem(.separator())
        add(menu, L("menu.cut"), #selector(NSText.cut(_:)), "x")
        add(menu, L("menu.copy"), #selector(NSText.copy(_:)), "c")
        add(menu, L("menu.paste"), #selector(NSText.paste(_:)), "v")
        // Paste-and-match-style matters here: the rows are plain strings, so a
        // styled paste would silently drop its styling anyway. Better to have
        // the chord land somewhere predictable.
        add(menu, L("menu.pastePlain"),
            #selector(NSTextView.pasteAsPlainText(_:)), "V", [.command, .shift, .option])
        add(menu, L("menu.delete"), #selector(NSText.delete(_:)), "")
        add(menu, L("menu.selectAll"), #selector(NSText.selectAll(_:)), "a")

        item.submenu = menu
        return item
    }

    @discardableResult
    private static func add(_ menu: NSMenu, _ title: String, _ action: Selector,
                            _ key: String,
                            _ mask: NSEvent.ModifierFlags = .command) -> NSMenuItem {
        let mi = NSMenuItem(title: title, action: action, keyEquivalent: key)
        if !key.isEmpty { mi.keyEquivalentModifierMask = mask }
        menu.addItem(mi)
        return mi
    }
}
