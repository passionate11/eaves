import AppKit

// MARK: - Tab strip

protocol TabBarDelegate: AnyObject {
    func tabBarSelect(_ id: UUID)
    func tabBarToggleCollapse()
    /// A drag that started in the strip has ended — the window may need to dock.
    /// Only called when the window actually moved.
    func tabBarDidFinishDrag()
    /// The hide button was pressed: tuck the window into the screen edge.
    func tabBarHide()
    func tabBarShowMenu(for id: UUID?, from view: NSView)
    func tabBarAddNote()
    func tabBarRename(_ id: UUID, to title: String)
}

/// Runs `body` and reports whether the window moved while it ran. A press in the
/// strip both selects and may drag, so this is what separates the two: a click
/// that never moved the window must not be read as a drag, or switching tabs
/// near a screen edge would silently dock the window.
private func movedWindow(_ view: NSView, _ body: () -> Void) -> Bool {
    let before = view.window?.frame.origin ?? .zero
    body()
    let after = view.window?.frame.origin ?? .zero
    return abs(after.x - before.x) > 2 || abs(after.y - before.y) > 2
}

/// One tab. Drawn rather than composed from controls, because a tab has to
/// shrink below the point where stacked NSTextFields would lay out sensibly.
final class TabItemView: FlippedView {
    static let titleFont = NSFont.systemFont(ofSize: 11.5, weight: .medium)
    static let activeTitleFont = NSFont.systemFont(ofSize: 11.5, weight: .semibold)
    static let progFont = NSFont.systemFont(ofSize: 10, weight: .medium)

    weak var delegate: TabBarDelegate?
    private(set) var id = UUID()

    var palette: Palette = .of(.auto, systemDark: false) { didSet { needsDisplay = true } }

    private var title = ""
    private var progress = ""
    private var color: NoteColor = .blue
    private var active = false
    private var hovered = false
    /// Cleared when the strip is too crowded to afford the `3/7` suffix.
    var showsProgress = true { didSet { needsDisplay = true } }

    private var editor: NSTextField?
    private var tracking: NSTrackingArea?

    func configure(note: Note, active: Bool) {
        id = note.id
        title = note.title
        progress = note.items.isEmpty ? "" : note.progressText
        color = note.color
        self.active = active
        needsDisplay = true
    }

    private var isDark: Bool {
        effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
    }

    // MARK: Measurement

    /// Width the tab wants: dot + title (capped) + optional progress + padding.
    static func naturalWidth(note: Note, active: Bool, withProgress: Bool) -> CGFloat {
        let font = active ? activeTitleFont : titleFont
        let t = min(M.tabTitleMax,
                    (note.title as NSString).size(withAttributes: [.font: font]).width)
        return chromeWidth(note: note, withProgress: withProgress) + ceil(t)
    }

    /// The narrowest the tab may get while still showing progress and a couple
    /// of title characters.
    static func floorWidth(note: Note, withProgress: Bool) -> CGFloat {
        chromeWidth(note: note, withProgress: withProgress) + M.tabTitleMin
    }

    /// Everything except the title: padding, dot, gaps and the progress suffix.
    private static func chromeWidth(note: Note, withProgress: Bool) -> CGFloat {
        var w: CGFloat = 9 + 6 + 6 + 9
        if withProgress, !note.items.isEmpty {
            w += ceil((note.progressText as NSString)
                .size(withAttributes: [.font: progFont]).width) + 6
        }
        return w
    }

    // MARK: Drawing

    override func draw(_ dirtyRect: NSRect) {
        let pill = bounds.insetBy(dx: 1.5, dy: 4)
        if active {
            // A raised neutral chip. The note's colour only tints it by a few
            // percent — the dot and the progress bar are where colour lives.
            let path = NSBezierPath(roundedRect: pill, xRadius: 8, yRadius: 8)
            let base = palette.activeTab
            (base.blended(withFraction: 0.06, of: color.accent) ?? base).setFill()
            path.fill()
            // A hairline rim keeps the chip legible where the fill is close to
            // the card colour behind it.
            palette.hairline.setStroke()
            path.lineWidth = 1
            path.stroke()
        } else if hovered {
            palette.hover.setFill()
            NSBezierPath(roundedRect: pill, xRadius: 8, yRadius: 8).fill()
        }

        let mid = bounds.midY
        let dotR = NSRect(x: 9, y: mid - 3, width: 6, height: 6)
        color.accent.withAlphaComponent(active ? 1.0 : 0.5).setFill()
        NSBezierPath(ovalIn: dotR).fill()

        var progW: CGFloat = 0
        if showsProgress, !progress.isEmpty {
            let attrs: [NSAttributedString.Key: Any] = [
                .font: TabItemView.progFont,
                .foregroundColor: NSColor.tertiaryLabelColor,
            ]
            let size = (progress as NSString).size(withAttributes: attrs)
            progW = ceil(size.width) + 6
            (progress as NSString).draw(
                at: NSPoint(x: bounds.maxX - 9 - ceil(size.width), y: mid - size.height / 2),
                withAttributes: attrs)
        }

        let titleX = dotR.maxX + 6
        let titleW = bounds.maxX - 9 - progW - titleX
        guard titleW > 6, editor == nil else { return }

        let para = NSMutableParagraphStyle()
        para.lineBreakMode = .byTruncatingTail
        let attrs: [NSAttributedString.Key: Any] = [
            .font: active ? TabItemView.activeTitleFont : TabItemView.titleFont,
            .foregroundColor: active ? NSColor.labelColor : NSColor.secondaryLabelColor,
            .paragraphStyle: para,
        ]
        let h = ceil((title as NSString).size(withAttributes: attrs).height)
        (title as NSString).draw(in: NSRect(x: titleX, y: mid - h / 2, width: titleW, height: h),
                                 withAttributes: attrs)
    }

    // MARK: Input

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let t = tracking { removeTrackingArea(t) }
        let t = NSTrackingArea(rect: bounds,
                               options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                               owner: self)
        addTrackingArea(t)
        tracking = t
    }

    override func mouseEntered(with event: NSEvent) { hovered = true; needsDisplay = true }
    override func mouseExited(with event: NSEvent) { hovered = false; needsDisplay = true }

    // A press both selects and may start a window drag. `performDrag` only moves
    // the window once the pointer passes AppKit's own threshold, so a plain
    // click still reads as a click — which is what makes one gesture serve both.
    override func mouseDown(with event: NSEvent) {
        if event.clickCount == 2 {
            delegate?.tabBarToggleCollapse()
            return
        }
        delegate?.tabBarSelect(id)
        let moved = movedWindow(self) { window?.performDrag(with: event) }
        if moved { delegate?.tabBarDidFinishDrag() }
    }

    override func rightMouseDown(with event: NSEvent) {
        delegate?.tabBarSelect(id)
        delegate?.tabBarShowMenu(for: id, from: self)
    }

    /// Swaps the drawn title for a field editor, in place.
    func beginRename() {
        guard editor == nil else { return }
        let f = NSTextField(frame: NSRect(x: 20, y: (bounds.height - 16) / 2,
                                          width: max(20, bounds.width - 26), height: 16))
        f.stringValue = title
        f.isBordered = false
        f.drawsBackground = true
        f.backgroundColor = .textBackgroundColor
        f.focusRingType = .none
        f.font = TabItemView.activeTitleFont
        f.delegate = self
        f.cell?.usesSingleLineMode = true
        addSubview(f)
        editor = f
        needsDisplay = true
        window?.makeKeyAndOrderFront(nil)
        window?.makeFirstResponder(f)
    }

    private func endRename(commit: Bool) {
        guard let f = editor else { return }
        let text = f.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        editor = nil
        f.removeFromSuperview()
        needsDisplay = true
        if commit, !text.isEmpty { delegate?.tabBarRename(id, to: text) }
    }
}

extension TabItemView: NSTextFieldDelegate {
    func control(_ control: NSControl, textView: NSTextView,
                 doCommandBy selector: Selector) -> Bool {
        switch selector {
        case #selector(NSResponder.insertNewline(_:)): endRename(commit: true); return true
        case #selector(NSResponder.cancelOperation(_:)): endRename(commit: false); return true
        default: return false
        }
    }

    func controlTextDidEndEditing(_ obj: Notification) { endRename(commit: true) }
}

/// The strip itself: tabs, a collapse chevron and a `＋`. When the window is
/// collapsed this view *is* the window, so it stays fully interactive.
final class TabBarView: FlippedView {
    weak var delegate: TabBarDelegate? {
        didSet { tabs.forEach { $0.delegate = delegate } }
    }

    private var tabs: [TabItemView] = []
    var palette: Palette = .of(.auto, systemDark: false) {
        didSet {
            tabs.forEach { $0.palette = palette }
            needsDisplay = true
        }
    }
    private lazy var hide = symbolButton("arrow.right.to.line", size: 10, target: self,
                                         action: #selector(hideTapped))
    private lazy var chevron = symbolButton("chevron.down", target: self,
                                            action: #selector(collapseTapped))
    private lazy var plus = symbolButton("plus", size: 10, target: self,
                                         action: #selector(addTapped))
    private var collapsed = false

    /// Room reserved on the right for the hide button, the chevron and the ＋.
    private let controlsW: CGFloat = 70

    override init(frame: NSRect) {
        super.init(frame: frame)
        chevron.toolTip = L("tabBar.collapse.tip")
        plus.toolTip = L("tabBar.newList.tip")
        addSubview(hide)
        addSubview(chevron)
        addSubview(plus)
    }

    required init?(coder: NSCoder) { fatalError() }

    func configure(notes: [Note], selected: UUID?, collapsed: Bool,
                   hideEdge: DockEdge, autoHide: Bool) {
        self.collapsed = collapsed

        if tabs.count != notes.count {
            tabs.forEach { $0.removeFromSuperview() }
            tabs = notes.map { _ in
                let t = TabItemView()
                t.delegate = delegate
                t.palette = palette
                addSubview(t)
                return t
            }
        }
        for (t, n) in zip(tabs, notes) {
            t.configure(note: n, active: n.id == selected)
        }

        let cfg = NSImage.SymbolConfiguration(pointSize: 11, weight: .semibold)
        chevron.image = NSImage(systemSymbolName: collapsed ? "chevron.right" : "chevron.down",
                                accessibilityDescription: nil)?
            .withSymbolConfiguration(cfg)
        // The arrow points at the edge the window would actually tuck into.
        let hcfg = NSImage.SymbolConfiguration(pointSize: 10, weight: .semibold)
        hide.image = NSImage(systemSymbolName: hideEdge.arrowSymbol,
                             accessibilityDescription: nil)?
            .withSymbolConfiguration(hcfg)
        let tuck = L("tuck.\(hideEdge.rawValue)")
        hide.toolTip = autoHide ? tuck + L("tuck.autoHint") : tuck
        applyColors()
        layoutTabs(notes: notes, selected: selected)
        needsDisplay = true
    }

    func tab(for id: UUID) -> TabItemView? { tabs.first { $0.id == id } }

    private func applyColors() {
        // No wash of its own: the strip sits directly on the card, and the
        // active tab's chip plus the hairline below are what separate them.
        let fg = NSColor.secondaryLabelColor
        hide.contentTintColor = fg
        chevron.contentTintColor = fg
        plus.contentTintColor = fg
    }

    /// The strip paints its own surface, a shade off the card, plus a hairline
    /// along the bottom. Giving the chrome a real surface is what lets the
    /// active tab's chip read as raised: against a bare card it had nothing to
    /// be raised *from*. The window's layer mask rounds the two top corners, so
    /// filling full bounds is safe.
    override func draw(_ dirtyRect: NSRect) {
        palette.header.setFill()
        bounds.fill()
        palette.hairline.setFill()
        NSRect(x: 0, y: bounds.maxY - 1, width: bounds.width, height: 1).fill()
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        applyColors()
        tabs.forEach { $0.needsDisplay = true }
    }

    /// Tabs take their natural width when they fit. When they don't, titles are
    /// truncated first and the `3/7` suffix is only sacrificed once even a
    /// two-character title no longer fits — the progress count is the reason the
    /// strip exists, so it outranks the letters.
    private func layoutTabs(notes: [Note], selected: UUID?) {
        let avail = max(0, bounds.width - controlsW)
        let h = bounds.height

        chevron.frame = NSRect(x: bounds.width - 44, y: (h - 16) / 2, width: 16, height: 16)
        plus.frame = NSRect(x: bounds.width - 23, y: (h - 16) / 2, width: 16, height: 16)
        hide.frame = NSRect(x: bounds.width - 65, y: (h - 16) / 2, width: 16, height: 16)

        guard !notes.isEmpty else { return }

        var withProgress = true
        var widths = fitted(notes: notes, selected: selected, avail: avail, withProgress: true)
        if widths.reduce(0, +) > avail {
            withProgress = false
            widths = fitted(notes: notes, selected: selected, avail: avail, withProgress: false)
        }

        var x: CGFloat = 4
        for (t, w) in zip(tabs, widths) {
            t.showsProgress = withProgress
            t.frame = NSRect(x: x, y: 0, width: w, height: h)
            x += w
        }
    }

    /// Natural widths scaled down toward `avail`, each clamped at its own floor.
    private func fitted(notes: [Note], selected: UUID?,
                        avail: CGFloat, withProgress: Bool) -> [CGFloat] {
        let natural = notes.map {
            TabItemView.naturalWidth(note: $0, active: $0.id == selected,
                                     withProgress: withProgress)
        }
        let total = natural.reduce(0, +)
        guard total > avail, total > 0 else { return natural }

        let floors = notes.map {
            withProgress ? TabItemView.floorWidth(note: $0, withProgress: true)
                         : M.tabMinWidth
        }
        let scale = avail / total
        return zip(natural, floors).map { max($1, $0 * scale) }
    }

    // Empty strip area behaves like a title bar: drag moves, double-click folds.
    override func mouseDown(with event: NSEvent) {
        if event.clickCount == 2 {
            delegate?.tabBarToggleCollapse()
            return
        }
        let moved = movedWindow(self) { window?.performDrag(with: event) }
        if moved { delegate?.tabBarDidFinishDrag() }
    }

    override func rightMouseDown(with event: NSEvent) {
        delegate?.tabBarShowMenu(for: nil, from: self)
    }

    @objc private func collapseTapped() { delegate?.tabBarToggleCollapse() }
    @objc private func addTapped() { delegate?.tabBarAddNote() }
    @objc private func hideTapped() { delegate?.tabBarHide() }
}

// MARK: - Checklist row

/// Which of a row's two fields is being talked about.
enum RowField {
    case main, next
}

protocol ItemRowDelegate: AnyObject {
    func rowToggle(_ id: UUID)
    func rowTextChanged(_ id: UUID, _ text: String)
    func rowDelete(_ id: UUID)
    func rowInsertAfter(_ id: UUID)
    /// Tab was pressed in the main field: open (or jump to) the next line.
    func rowBeginNext(_ id: UUID)
    func rowNextChanged(_ id: UUID, _ text: String)
    /// The next line lost focus — drop it again if nothing was typed.
    func rowEndNext(_ id: UUID)
    /// Esc in the next line: back out of it. An empty line is dropped entirely,
    /// so an accidental Tab leaves nothing behind.
    func rowCancelNext(_ id: UUID)
    /// Backspace with the caret at the start of an empty item. Removes the item
    /// and hands the caret back to the one above, so the keystroke undoes the
    /// Return that created it.
    func rowDeleteEmpty(_ id: UUID)
    /// ↑/↓ pressed with the caret already at the top/bottom line of a field:
    /// move the caret to the neighbouring row instead.
    func rowMoveFocus(from id: UUID, in field: RowField, up: Bool)
}

func measuredHeight(_ text: String, font: NSFont, width: CGFloat) -> CGFloat {
    let s = text.isEmpty ? " " : text
    let rect = (s as NSString).boundingRect(
        with: NSSize(width: max(10, width), height: .greatestFiniteMagnitude),
        options: [.usesLineFragmentOrigin, .usesFontLeading],
        attributes: [.font: font])
    return ceil(rect.height)
}

final class ItemRowView: FlippedView {
    static let font = NSFont.systemFont(ofSize: 13)
    static let nextFont = NSFont.systemFont(ofSize: 11)
    static let checkboxW: CGFloat = 25
    static let trailing: CGFloat = 20
    static let boxSide: CGFloat = 17
    /// How far the next line is inset past the item's own text.
    static let nextIndent: CGFloat = 16

    weak var delegate: ItemRowDelegate?
    private(set) var itemID: UUID = UUID()

    var palette: Palette = .of(.auto, systemDark: false) { didSet { needsDisplay = true } }

    private let check = NSButton()
    private let field = NSTextField()
    private let nextField = NSTextField()
    private lazy var del = symbolButton("xmark", size: 9, target: self,
                                        action: #selector(deleteTapped))
    private var accent: NSColor = .systemBlue
    private var done = false
    private var showsNext = false
    private var hovered = false
    private var arrowY: CGFloat = 0
    private var tracking: NSTrackingArea?

    /// Noticky-style checkbox: a rounded square, empty and hairline-thin until
    /// it is ticked, then filled solid with the note's accent. Drawn rather than
    /// taken from SF Symbols because the corner radius is the whole look.
    private static func boxImage(done: Bool, accent: NSColor) -> NSImage {
        let side = boxSide
        return NSImage(size: NSSize(width: side, height: side), flipped: false) { _ in
            let box = NSRect(x: 0.5, y: 0.5, width: side - 1, height: side - 1)
            let path = NSBezierPath(roundedRect: box, xRadius: 5.5, yRadius: 5.5)
            if done {
                accent.setFill()
                path.fill()
                let tick = NSBezierPath()
                tick.move(to: NSPoint(x: side * 0.28, y: side * 0.52))
                tick.line(to: NSPoint(x: side * 0.44, y: side * 0.34))
                tick.line(to: NSPoint(x: side * 0.74, y: side * 0.68))
                tick.lineWidth = 1.9
                tick.lineCapStyle = .round
                tick.lineJoinStyle = .round
                NSColor.white.setStroke()
                tick.stroke()
            } else {
                // A fixed mid grey rather than a dynamic colour: this closure can
                // run outside the view's appearance, where semantic colours would
                // resolve against the wrong side.
                NSColor(white: 0.62, alpha: 1).setStroke()
                path.lineWidth = 1.4
                path.stroke()
            }
            return true
        }
    }

    override init(frame: NSRect) {
        super.init(frame: frame)
        check.isBordered = false
        check.bezelStyle = .regularSquare
        check.imagePosition = .imageOnly
        check.title = ""
        check.target = self
        check.action = #selector(checkTapped)
        check.setButtonType(.momentaryChange)

        field.isBordered = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.font = ItemRowView.font
        field.delegate = self
        field.cell?.usesSingleLineMode = false
        field.cell?.wraps = true
        field.cell?.isScrollable = false
        field.maximumNumberOfLines = 0

        nextField.isBordered = false
        nextField.drawsBackground = false
        nextField.focusRingType = .none
        nextField.font = ItemRowView.nextFont
        nextField.textColor = .secondaryLabelColor
        nextField.placeholderString = L("field.nextLine")
        nextField.delegate = self
        nextField.cell?.usesSingleLineMode = false
        nextField.cell?.wraps = true
        nextField.cell?.isScrollable = false
        nextField.maximumNumberOfLines = 0
        nextField.isHidden = true

        del.isHidden = true
        [check, field, nextField, del].forEach(addSubview)
    }

    required init?(coder: NSCoder) { fatalError() }

    static func height(for item: ChecklistItem, width: CGFloat) -> CGFloat {
        let textW = max(10, width - (M.pad + checkboxW) - trailing - M.pad)
        var h = max(M.rowMin, measuredHeight(item.text, font: font, width: textW) + M.rowPad * 2)
        if item.hasNext {
            let nw = max(10, textW - nextIndent)
            h += max(15, measuredHeight(item.nextText, font: nextFont, width: nw)) + 2
        }
        return h
    }

    func configure(item: ChecklistItem, accent: NSColor) {
        itemID = item.id
        self.accent = accent
        done = item.done
        showsNext = item.hasNext

        check.image = ItemRowView.boxImage(done: item.done, accent: accent)

        if field.currentEditor() == nil {
            if item.done {
                field.attributedStringValue = NSAttributedString(
                    string: item.text,
                    attributes: [.font: ItemRowView.font,
                                 .strikethroughStyle: NSUnderlineStyle.single.rawValue,
                                 .strikethroughColor: NSColor.tertiaryLabelColor,
                                 .foregroundColor: NSColor.tertiaryLabelColor])
            } else {
                field.stringValue = item.text
                field.textColor = .labelColor
            }
        }
        if nextField.currentEditor() == nil {
            nextField.stringValue = item.nextText
            nextField.textColor = item.done ? .tertiaryLabelColor : .secondaryLabelColor
        }
        needsLayout = true
        needsDisplay = true
    }

    override func layout() {
        super.layout()
        let w = bounds.width
        let side = ItemRowView.boxSide
        let top = M.rowPad
        check.frame = NSRect(x: M.pad, y: top, width: side, height: side)
        del.frame = NSRect(x: w - M.pad - 12, y: top + 3, width: 12, height: 12)

        let x = M.pad + ItemRowView.checkboxW
        let textW = max(10, w - x - ItemRowView.trailing - M.pad)
        nextField.isHidden = !showsNext

        guard showsNext else {
            field.frame = NSRect(x: x, y: top, width: textW,
                                 height: max(14, bounds.height - top * 2))
            return
        }
        // The next line is measured from its own live text, so the row keeps
        // following along while it is being typed into.
        let nw = max(10, textW - ItemRowView.nextIndent)
        let nh = max(15, measuredHeight(nextField.stringValue, font: ItemRowView.nextFont,
                                        width: nw))
        arrowY = bounds.height - top - nh
        nextField.frame = NSRect(x: x + ItemRowView.nextIndent, y: arrowY, width: nw, height: nh)
        field.frame = NSRect(x: x, y: top, width: textW,
                             height: max(14, bounds.height - top * 2 - nh - 2))
    }

    /// Hover wash plus the little ↳ in front of the next line. The arrow is
    /// drawn rather than folded into the text so the stored string stays
    /// exactly what the user typed.
    override func draw(_ dirtyRect: NSRect) {
        if hovered {
            palette.hover.setFill()
            NSBezierPath(roundedRect: bounds.insetBy(dx: 6, dy: 1),
                         xRadius: 8, yRadius: 8).fill()
        }
        guard showsNext else { return }
        ("↳" as NSString).draw(
            at: NSPoint(x: M.pad + ItemRowView.checkboxW + 1, y: arrowY),
            withAttributes: [.font: NSFont.systemFont(ofSize: 10),
                             .foregroundColor: NSColor.tertiaryLabelColor])
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let t = tracking { removeTrackingArea(t) }
        let t = NSTrackingArea(rect: bounds,
                               options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                               owner: self)
        addTrackingArea(t)
        tracking = t
    }

    override func mouseEntered(with event: NSEvent) {
        hovered = true; del.isHidden = false; needsDisplay = true
    }

    override func mouseExited(with event: NSEvent) {
        hovered = false; del.isHidden = true; needsDisplay = true
    }

    func beginEditing(atEnd: Bool = false) {
        window?.makeKeyAndOrderFront(nil)
        window?.makeFirstResponder(field)
        if atEnd { field.currentEditor()?.moveToEndOfDocument(nil) }
    }

    func beginEditingNext(atEnd: Bool = false) {
        window?.makeKeyAndOrderFront(nil)
        window?.makeFirstResponder(nextField)
        if atEnd { nextField.currentEditor()?.moveToEndOfDocument(nil) }
    }

    @objc private func checkTapped() { delegate?.rowToggle(itemID) }
    @objc private func deleteTapped() { delegate?.rowDelete(itemID) }
}

extension ItemRowView: NSTextFieldDelegate {
    func controlTextDidChange(_ obj: Notification) {
        if (obj.object as AnyObject?) === nextField {
            delegate?.rowNextChanged(itemID, nextField.stringValue)
        } else {
            delegate?.rowTextChanged(itemID, field.stringValue)
        }
    }

    func controlTextDidEndEditing(_ obj: Notification) {
        // An untouched next line is not a line — drop it rather than leaving an
        // empty ↳ behind.
        if (obj.object as AnyObject?) === nextField,
           nextField.stringValue.trimmingCharacters(in: .whitespaces).isEmpty {
            delegate?.rowEndNext(itemID)
        }
    }

    /// True when the caret sits on the first (or last) visual line of `tv`.
    /// Long items wrap, so ↑/↓ has to walk within the text before it is allowed
    /// to jump to the neighbouring todo.
    private func caretAtEdgeLine(_ tv: NSTextView, top: Bool) -> Bool {
        guard let lm = tv.layoutManager, tv.textContainer != nil,
              lm.numberOfGlyphs > 0 else { return true }
        let loc = min(tv.selectedRange().location, lm.numberOfGlyphs - 1)
        var line = NSRange()
        _ = lm.lineFragmentRect(forGlyphAt: loc, effectiveRange: &line)
        return top ? line.location == 0
                   : line.location + line.length >= lm.numberOfGlyphs
    }

    func control(_ control: NSControl, textView: NSTextView,
                 doCommandBy selector: Selector) -> Bool {
        let inNext = control === nextField
        switch selector {
        case #selector(NSResponder.insertNewline(_:)):
            delegate?.rowInsertAfter(itemID)
            return true
        case #selector(NSResponder.insertTab(_:)):
            // Tab hops between the item and its next line, both ways, so the
            // whole pair can be typed without leaving the keyboard.
            if inNext { beginEditing() } else { delegate?.rowBeginNext(itemID) }
            return true
        case #selector(NSResponder.insertBacktab(_:)):
            if inNext { beginEditing(); return true }
            return false
        case #selector(NSResponder.cancelOperation(_:)):
            // Esc is the way out of a mis-typed Tab. From the next line it backs
            // up into the item itself (dropping the line if it is still empty);
            // from the item it just gives up focus, which commits the text — Esc
            // here means "I'm done", not "throw away what I typed".
            if inNext {
                delegate?.rowCancelNext(itemID)
            } else {
                window?.makeFirstResponder(nil)
            }
            return true
        case #selector(NSResponder.deleteBackward(_:)):
            // Backspace on an empty field means "take this line back" — there is
            // nothing to its left to delete, and a stray Return is the usual way
            // to end up here. A field with any text in it is left alone.
            guard textView.string.isEmpty else { return false }
            if inNext {
                delegate?.rowCancelNext(itemID)
            } else {
                delegate?.rowDeleteEmpty(itemID)
            }
            return true
        case #selector(NSResponder.moveUp(_:)):
            guard caretAtEdgeLine(textView, top: true) else { return false }
            delegate?.rowMoveFocus(from: itemID, in: inNext ? .next : .main, up: true)
            return true
        case #selector(NSResponder.moveDown(_:)):
            guard caretAtEdgeLine(textView, top: false) else { return false }
            delegate?.rowMoveFocus(from: itemID, in: inNext ? .next : .main, up: false)
            return true
        default:
            return false
        }
    }
}
