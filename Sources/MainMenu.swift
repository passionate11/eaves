import AppKit

// MARK: - Main menu

/// Builds the application's main menu.
///
/// DeskNote is an `LSUIElement` app, so this menu is never *drawn* anywhere —
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
        let menu = NSMenu(title: "DeskNote")

        let new = NSMenuItem(title: "新建清单", action: #selector(AppDelegate.newNote),
                             keyEquivalent: "n")
        new.target = target
        menu.addItem(new)

        menu.addItem(.separator())

        let hide = NSMenuItem(title: "显示/隐藏便签窗口",
                              action: #selector(AppDelegate.toggleHideAll), keyEquivalent: "h")
        hide.keyEquivalentModifierMask = [.command, .shift]
        hide.target = target
        menu.addItem(hide)

        menu.addItem(.separator())

        let quit = NSMenuItem(title: "退出 DeskNote", action: #selector(AppDelegate.quit),
                              keyEquivalent: "q")
        quit.target = target
        menu.addItem(quit)

        item.submenu = menu
        return item
    }

    /// The standard editing chords. `nil` targets on purpose — see the type doc.
    private static func editItem() -> NSMenuItem {
        let item = NSMenuItem()
        let menu = NSMenu(title: "编辑")

        add(menu, "撤销", #selector(UndoManager.undo), "z")
        add(menu, "重做", #selector(UndoManager.redo), "Z", [.command, .shift])
        menu.addItem(.separator())
        add(menu, "剪切", #selector(NSText.cut(_:)), "x")
        add(menu, "拷贝", #selector(NSText.copy(_:)), "c")
        add(menu, "粘贴", #selector(NSText.paste(_:)), "v")
        // Paste-and-match-style matters here: the rows are plain strings, so a
        // styled paste would silently drop its styling anyway. Better to have
        // the chord land somewhere predictable.
        add(menu, "粘贴为纯文本",
            #selector(NSTextView.pasteAsPlainText(_:)), "V", [.command, .shift, .option])
        add(menu, "删除", #selector(NSText.delete(_:)), "")
        add(menu, "全选", #selector(NSText.selectAll(_:)), "a")

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
