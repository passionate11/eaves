import AppKit

// MARK: - Tab strip

protocol TabBarDelegate: AnyObject {
    func tabBarSelect(_ id: UUID)
    func tabBarToggleCollapse()
    /// The hide button was pressed: tuck the window into the screen edge.
    func tabBarHide()
    /// The pin was pressed: toggle whether the window stays above other apps.
    func tabBarTogglePin()
    func tabBarShowMenu(for id: UUID?, from view: NSView)
    func tabBarAddNote()
    func tabBarRename(_ id: UUID, to title: String)
    /// A tab dropped at a different place in the strip. The strip has already
    /// moved its own tabs, so this only has to write the same move to the model.
    func tabBarMove(_ id: UUID, to index: Int)
}

/// One tab. Drawn rather than composed from controls, because a tab has to
/// shrink below the point where stacked NSTextFields would lay out sensibly.
final class TabItemView: FlippedView {
    static let titleFont = NSFont.systemFont(ofSize: 12.5, weight: .medium)
    static let activeTitleFont = NSFont.systemFont(ofSize: 12.5, weight: .semibold)
    static let progFont = NSFont.systemFont(ofSize: 11, weight: .medium)

    weak var delegate: TabBarDelegate?
    private(set) var id = UUID()

    var palette: Palette = .of(.auto, systemDark: false) { didSet { needsDisplay = true } }

    private var title = ""
    /// What the counter draws — the numbers, or a tick once the list is done.
    private var progress = ""
    /// What its width is reserved for, which stays the numbers either way so
    /// that finishing a list moves nothing. See `Note.progressText`.
    private var progressRoom = ""
    private var color: NoteColor = .blue
    private var active = false
    private var hovered = false
    /// Cleared when the strip is too crowded to afford the `3/7` suffix.
    var showsProgress = true { didSet { needsDisplay = true } }

    /// Set while this tab is the one being dragged, so it draws lifted and the
    /// strip holds a gap open where it would land.
    var lifted = false { didSet { needsDisplay = true } }

    private var editor: NSTextField?
    private var tracking: NSTrackingArea?

    func configure(note: Note, active: Bool) {
        id = note.id
        title = note.title
        progress = note.items.isEmpty ? "" : note.progressLabel
        progressRoom = note.items.isEmpty ? "" : note.progressText
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
        if active || lifted {
            // A raised chip carrying the note's colour. The tint has to be
            // stronger than it looks like it should be: the chip is nearly
            // white on the light themes, and a few percent of an accent mixed
            // into white comes back out as white.
            //
            // A tab in the air gets the same surface whether or not it is the
            // active one — what is being held has to read as off the strip —
            // but a lighter tint, so being picked up is not mistaken for being
            // selected.
            let path = NSBezierPath(roundedRect: pill, xRadius: 8, yRadius: 8)
            if lifted {
                NSGraphicsContext.saveGraphicsState()
                NSShadow.drop(radius: 5, alpha: palette.dark ? 0.5 : 0.18, dy: -1).set()
            }
            mixed(palette.activeTab, color.accent, active ? 0.14 : 0.08).setFill()
            path.fill()
            if lifted { NSGraphicsContext.restoreGraphicsState() }
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

        let titleX = dotR.maxX + 6
        let titleAttrs: [NSAttributedString.Key: Any] = {
            let para = NSMutableParagraphStyle()
            para.lineBreakMode = .byTruncatingTail
            return [.font: active ? TabItemView.activeTitleFont : TabItemView.titleFont,
                    .foregroundColor: active ? NSColor.labelColor : NSColor.secondaryLabelColor,
                    .paragraphStyle: para]
        }()

        if showsProgress, !progress.isEmpty {
            let attrs: [NSAttributedString.Key: Any] = [
                .font: TabItemView.progFont,
                .foregroundColor: NSColor.tertiaryLabelColor,
            ]
            let size = (progress as NSString).size(withAttributes: attrs)
            // Follows the title rather than sitting against the right edge. A
            // tab wide enough to have slack would otherwise show `3/7` marooned
            // across a gap from the name it belongs to; against the right rim it
            // reads as a separate column instead of part of the tab.
            let titleW = ceil((title as NSString).size(withAttributes: titleAttrs).width)
            let rightAligned = bounds.maxX - 9 - ceil(size.width)
            let x = min(rightAligned, titleX + titleW + 6)
            (progress as NSString).draw(at: NSPoint(x: x, y: mid - size.height / 2),
                                        withAttributes: attrs)
        }

        let titleMax = bounds.maxX - 9 - progWidth - titleX
        guard titleMax > 6, editor == nil else { return }

        let h = ceil((title as NSString).size(withAttributes: titleAttrs).height)
        (title as NSString).draw(in: NSRect(x: titleX, y: mid - h / 2, width: titleMax, height: h),
                                 withAttributes: titleAttrs)
    }

    /// Room the `3/7` suffix needs, so the title knows where to truncate.
    private var progWidth: CGFloat {
        guard showsProgress, !progressRoom.isEmpty else { return 0 }
        return ceil((progressRoom as NSString)
            .size(withAttributes: [.font: TabItemView.progFont]).width) + 6
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

    // A press selects, and may go on to drag the tab to a different place in
    // the strip. Moving the *window* is the gutter's job now — `M.tabGutter`
    // says why. A plain click still reads as a click: nothing happens until the
    // pointer passes a threshold, same as before.
    override func mouseDown(with event: NSEvent) {
        if event.clickCount == 2 {
            delegate?.tabBarToggleCollapse()
            return
        }
        delegate?.tabBarSelect(id)
        (superview as? TabBarView)?.beginTabDrag(self, with: event)
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
    private lazy var pin = symbolButton("pin", size: 10, target: self,
                                        action: #selector(pinTapped))
    private var pinned = false
    private lazy var hide = symbolButton("arrow.right.to.line", size: 10, target: self,
                                         action: #selector(hideTapped))
    private lazy var chevron = symbolButton("chevron.down", target: self,
                                            action: #selector(collapseTapped))
    private lazy var plus = symbolButton("plus", size: 10, target: self,
                                         action: #selector(addTapped))
    private var collapsed = false

    /// Room reserved on the right for the pin, the hide button, the chevron
    /// and the ＋.
    private let controlsW: CGFloat = 91
    /// Gap between the left edge of the strip and the first tab.
    static let inset: CGFloat = 4

    /// The tab in the air, and where it came from and would land. `widths` is
    /// the last layout's answer, kept so the gesture can lay the strip out
    /// again without the notes it was measured from.
    private var dragTab: TabItemView?
    private var dragFrom = 0
    private var dragTo = 0
    private var dragX: CGFloat = 0
    private var widths: [CGFloat] = []

    override init(frame: NSRect) {
        super.init(frame: frame)
        chevron.toolTip = L("tabBar.collapse.tip")
        plus.toolTip = L("tabBar.newList.tip")
        addSubview(pin)
        addSubview(hide)
        addSubview(chevron)
        addSubview(plus)
    }

    required init?(coder: NSCoder) { fatalError() }

    func configure(notes: [Note], selected: UUID?, collapsed: Bool,
                   hideEdge: DockEdge, autoHide: Bool, pinned: Bool) {
        self.collapsed = collapsed
        self.pinned = pinned

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
        pin.image = NSImage(systemSymbolName: pinned ? "pin.fill" : "pin",
                            accessibilityDescription: nil)?
            .withSymbolConfiguration(hcfg)
        pin.toolTip = L(pinned ? "tabBar.unpin.tip" : "tabBar.pin.tip")
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
        // Filled and in the accent colour when on, so a glance tells you whether
        // the window will stay put above everything else.
        pin.contentTintColor = pinned ? .controlAccentColor : fg
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
        // Everything but the gutter, which is the window's handle and carries
        // nothing.
        let top = M.tabGutter
        let h = bounds.height - top

        chevron.frame = NSRect(x: bounds.width - 44, y: top + (h - 16) / 2, width: 16, height: 16)
        plus.frame = NSRect(x: bounds.width - 23, y: top + (h - 16) / 2, width: 16, height: 16)
        hide.frame = NSRect(x: bounds.width - 65, y: top + (h - 16) / 2, width: 16, height: 16)
        pin.frame = NSRect(x: bounds.width - 86, y: top + (h - 16) / 2, width: 16, height: 16)

        guard !notes.isEmpty else { return }
        // Not while a tab is in the air. A refresh landing mid-gesture would put
        // every tab back where the model still has it, including the one under
        // the hand, and the drag would be fighting its own strip.
        guard dragTab == nil else { return }

        var withProgress = true
        var widths = fitted(notes: notes, selected: selected, avail: avail, withProgress: true)
        if widths.reduce(0, +) > avail {
            withProgress = false
            widths = fitted(notes: notes, selected: selected, avail: avail, withProgress: false)
        }

        var x = TabBarView.inset
        for (t, w) in zip(tabs, widths) {
            t.showsProgress = withProgress
            t.frame = NSRect(x: x, y: top, width: w, height: h)
            x += w
        }
        self.widths = widths
    }

    /// Natural widths fitted to `avail`: scaled down toward it when they
    /// overflow, each clamped at its own floor, and grown into the slack when
    /// they fall short.
    private func fitted(notes: [Note], selected: UUID?,
                        avail: CGFloat, withProgress: Bool) -> [CGFloat] {
        let natural = notes.map {
            TabItemView.naturalWidth(note: $0, active: $0.id == selected,
                                     withProgress: withProgress)
        }
        let total = natural.reduce(0, +)
        guard total > 0 else { return natural }
        guard total > avail else { return grown(natural, avail: avail) }

        let floors = notes.map {
            withProgress ? TabItemView.floorWidth(note: $0, withProgress: true)
                         : M.tabMinWidth
        }
        let scale = avail / total
        return zip(natural, floors).map { max($1, $0 * scale) }
    }

    /// Spreads leftover strip width over the tabs, evenly and up to a ceiling.
    ///
    /// Evenly rather than in proportion to the titles, because the point is to
    /// fill the strip, not to reward the note with the longest name — and equal
    /// tabs are what a strip of tabs is expected to look like. The inset is
    /// taken off so the last tab stops where the controls begin instead of
    /// tucking under them.
    private func grown(_ natural: [CGFloat], avail: CGFloat) -> [CGFloat] {
        var w = natural
        var slack = avail - TabBarView.inset - w.reduce(0, +)
        guard slack > 0 else { return w }
        // Several passes: a tab that hits the ceiling hands its share back to
        // the others rather than stranding the width.
        while slack > 0.5 {
            let hungry = w.indices.filter { w[$0] < M.tabMaxWidth }
            guard !hungry.isEmpty else { break }
            let share = slack / CGFloat(hungry.count)
            var used: CGFloat = 0
            for i in hungry {
                let take = min(share, M.tabMaxWidth - w[i])
                w[i] += take
                used += take
            }
            slack -= used
            if used < 0.5 { break }
        }
        return w
    }

    // MARK: Tab reordering

    /// Runs a tab drag from the press that started it, in a local event loop.
    ///
    /// The same shape as the item and step drags in `ItemRowView`, and for the
    /// same reason: `configure` can rebuild the strip at any point — a rename
    /// committing, a tick landing — and a gesture spread over three callbacks
    /// on views that may be replaced underneath it is much easier to get wrong
    /// than one that holds its own state on the stack.
    func beginTabDrag(_ t: TabItemView, with event: NSEvent) {
        guard let from = tabs.firstIndex(where: { $0 === t }), tabs.count > 1 else { return }
        let start = event.locationInWindow
        // Where in the tab it was grabbed, so it does not jump to centre itself
        // under the cursor on the first event.
        let grab = convert(start, from: nil).x - t.frame.minX
        var dragging = false

        while let e = window?.nextEvent(matching: [.leftMouseDragged, .leftMouseUp]) {
            if e.type == .leftMouseUp { break }
            let p = e.locationInWindow
            if !dragging {
                // Below AppKit's own drag threshold this is still a click, and
                // the selection it already made is all it was.
                guard abs(p.x - start.x) > 3 || abs(p.y - start.y) > 3 else { continue }
                dragging = true
                NSCursor.closedHand.push()
                tabDragBegan(t, from: from)
            }
            tabDragMoved(to: convert(p, from: nil).x - grab)
        }

        guard dragging else { return }
        NSCursor.pop()
        tabDragEnded()
    }

    private func tabDragBegan(_ t: TabItemView, from: Int) {
        dragTab = t
        dragFrom = from
        dragTo = from
        dragX = t.frame.minX
        t.lifted = true
        // Above its neighbours, so the chip it draws is not cut into by the tab
        // it is passing over.
        addSubview(t, positioned: .above, relativeTo: nil)
    }

    private func tabDragMoved(to x: CGFloat) {
        guard let d = dragTab else { return }
        // Clamped to the band the tabs occupy. A tab dragged past the ＋ does
        // not go under the controls, it stops at the last slot.
        let last = max(TabBarView.inset,
                       TabBarView.inset + widths.reduce(0, +) - d.frame.width)
        dragX = min(max(TabBarView.inset, x), last)
        // Without animation: this is the thing being held, and interpolating it
        // would leave it trailing the cursor by the animation's whole duration.
        d.frame.origin.x = dragX

        // Whichever slot's middle the held tab's middle is nearest, measured in
        // the layout the strip had before anything was lifted out of it — the
        // same reasoning as the step drag, and the same reason not to read the
        // live frames: they already contain the open gap, so feeding them back
        // in would flicker between two answers while the cursor stands still.
        // Tabs are not all the same width, which is exactly the case nearest
        // middle handles and a boundary test does not.
        let mid = dragX + d.frame.width / 2
        var to = 0
        var best = CGFloat.greatestFiniteMagnitude
        var left = TabBarView.inset
        for (slot, w) in widths.enumerated() {
            let reach = abs(mid - (left + w / 2))
            if reach < best { best = reach; to = slot }
            left += w
        }
        guard to != dragTo else { return }
        dragTo = to
        settleTabs(over: 0.12)
    }

    private func tabDragEnded() {
        guard let d = dragTab else { return }
        d.lifted = false
        let from = dragFrom, to = dragTo
        dragTab = nil
        // Identity rather than range alone: a rebuild landing mid-gesture can
        // resync the strip, and moving whatever now sits at the old index would
        // reorder a note the hand never touched.
        guard from != to, tabs.indices.contains(from), tabs[from] === d else {
            // Dropped where it started, or onto a strip that changed under it.
            // Nothing to write; just let it settle back into a slot.
            settleTabs(over: 0.14)
            return
        }
        tabs.remove(at: from)
        tabs.insert(d, at: to)
        widths.insert(widths.remove(at: from), at: to)
        settleTabs(over: 0.14)
        delegate?.tabBarMove(d.id, to: to)
    }

    /// Lays the strip out for the order the drag is currently proposing: the
    /// held tab wherever the hand has it, the rest closed up behind it with a
    /// gap of its width held open at the target slot, so the strip shows where
    /// the tab would land rather than only where it left from.
    private func settleTabs(over duration: TimeInterval) {
        let top = M.tabGutter
        let h = bounds.height - top
        let heldW = dragTab?.frame.width ?? 0
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = duration
            ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
            ctx.allowsImplicitAnimation = true
            var x = TabBarView.inset
            // `slot` counts the tabs that stay put, which is the list the held
            // one will be put back into — so it is what `dragTo` indexes.
            var slot = 0
            for (t, w) in zip(tabs, widths) {
                if t === dragTab {
                    t.frame = NSRect(x: dragX, y: top, width: w, height: h)
                    continue
                }
                if dragTab != nil, slot == dragTo { x += heldW }
                t.frame = NSRect(x: x, y: top, width: w, height: h)
                x += w
                slot += 1
            }
        }
    }

    // The gutter behaves like a title bar: drag moves the window, double-click
    // folds it. So does whatever strip is left over past the last tab.
    override func mouseDown(with event: NSEvent) {
        if event.clickCount == 2 {
            delegate?.tabBarToggleCollapse()
            return
        }
        // Docking is decided in `windowDidMove` once the window comes to rest,
        // not here: `performDrag` returns while the window is still at its
        // starting point, so nothing useful can be measured across this call.
        window?.performDrag(with: event)
    }

    override func rightMouseDown(with event: NSEvent) {
        delegate?.tabBarShowMenu(for: nil, from: self)
    }

    @objc private func collapseTapped() { delegate?.tabBarToggleCollapse() }
    @objc private func addTapped() { delegate?.tabBarAddNote() }
    @objc private func pinTapped() { delegate?.tabBarTogglePin() }
    @objc private func hideTapped() { delegate?.tabBarHide() }
}

// MARK: - Checklist row

/// Which of a row's fields is being talked about: its own text, or the step at
/// this index under it.
enum RowField: Equatable {
    case main, sub(Int)
}

protocol ItemRowDelegate: AnyObject {
    func rowToggle(_ id: UUID)
    func rowTextChanged(_ id: UUID, _ text: String)
    func rowDelete(_ id: UUID)
    func rowInsertAfter(_ id: UUID)
    /// Return with the caret at the very start of a row that already has text:
    /// the new empty row takes this one's place and this one moves down.
    func rowInsertBefore(_ id: UUID)
    /// Tab. `at` is where the new step goes in the item's list, so the caller
    /// has already decided between "below this one" and "in front of this one" —
    /// the same split Return makes between `rowInsertAfter` and
    /// `rowInsertBefore`, and for the same reason: with the caret at the head of
    /// a step that already has text, the blank one should take that step's place
    /// and push it down, not appear on the far side of it.
    ///
    /// The caret lands in whichever step it makes, and a still-empty step is
    /// jumped back into rather than doubled.
    func rowAddSub(_ id: UUID, at index: Int)
    func rowSubTextChanged(_ id: UUID, index: Int, text: String)
    func rowToggleSub(_ id: UUID, index: Int)
    /// The little ↥ on a step: it becomes a to-do of its own, directly below the
    /// item it was under, keeping whatever state it had. This is the deliberate
    /// replacement for the old behaviour where ticking an item promoted its one
    /// follow-up automatically — promotion is now something asked for.
    func rowPromoteSub(_ id: UUID, index: Int)
    /// Esc, Backspace-on-empty, or focus leaving a step that was never typed
    /// into. An empty step is dropped entirely, so a mis-hit Tab leaves nothing
    /// behind; the caret goes back to whatever is above it.
    func rowCancelSub(_ id: UUID, index: Int)
    /// Backspace with the caret at the start of an empty item. Removes the item
    /// and hands the caret back to the one above, so the keystroke undoes the
    /// Return that created it.
    func rowDeleteEmpty(_ id: UUID)
    /// ↑/↓ pressed with the caret already at the top/bottom line of a field:
    /// move the caret to the neighbouring row instead.
    func rowMoveFocus(from id: UUID, in field: RowField, up: Bool)
    /// A drag started in the row's left column. `grabOffset` is how far down the
    /// row the cursor was, so the row keeps the same grip while it moves.
    func rowDragBegan(_ id: UUID, grabOffset: CGFloat)
    /// `y` is the new top of the dragged row, in the list's coordinates.
    func rowDragMoved(to y: CGFloat)
    func rowDragEnded()
    /// A step dragged to a new place among its siblings. The row has already
    /// moved its own views, so this only has to write the same move to the
    /// model — and must not reload, or the step would snap into its slot at the
    /// exact moment the drag deserves to look finished.
    func rowMoveSub(_ id: UUID, from: Int, to: Int)
    /// ⌥↑ / ⌥↓ with the caret in the item's own text: move the whole row one
    /// place, steps and all. The keyboard's answer to dragging it — and the only
    /// one that works without letting go of what you were typing.
    func rowMoveItem(_ id: UUID, up: Bool)
}

/// The little creation stamp at the right-hand end of a row.
///
/// Fixed patterns rather than localized templates. `M/d-HH:mm` is the format
/// this was asked for by example, and letting the locale have it would produce
/// `7/25-1:21 PM` on a 12-hour system — wider than the strip it has to fit in,
/// and no longer the thing that was asked for.
///
/// Past the turn of the year the time has stopped telling you anything and the
/// year has started to, so they trade places. That also keeps the string inside
/// the same width, which a year *plus* a time would not.
enum Stamp {
    private static let sameYear = formatter("M/d-HH:mm")
    private static let older = formatter("yy/M/d")

    private static func formatter(_ pattern: String) -> DateFormatter {
        let f = DateFormatter()
        f.dateFormat = pattern
        return f
    }

    static func text(for date: Date) -> String {
        Calendar.current.isDate(date, equalTo: Date(), toGranularity: .year)
            ? sameYear.string(from: date)
            : older.string(from: date)
    }
}

/// A field kept aside for no purpose but to be asked how tall text would be.
///
/// Configured exactly like the fields it stands in for, and reused rather than
/// made per call: measuring happens once per row per layout pass, and building
/// a control each time would be the expensive part of it.
private let textRuler: NSTextField = {
    let f = NSTextField()
    f.isBordered = false
    f.drawsBackground = false
    f.focusRingType = .none
    f.cell?.usesSingleLineMode = false
    f.cell?.wraps = true
    f.cell?.isScrollable = false
    f.maximumNumberOfLines = 0
    return f
}()

/// Height a wrapping `NSTextField` needs for this text at this width.
///
/// Asked of an actual field rather than computed with `NSString.boundingRect`,
/// because the two do not agree and the disagreement is not a rounding error. A
/// cell keeps a small inset inside the frame it is handed, so it wraps slightly
/// earlier than a bare string measurement predicts. At the widths where that
/// tips one last word onto a second line — `验证devspace连接是否成功` at a
/// 301pt window is one — `boundingRect` reports one line, the row is built one
/// line short, and the field draws its final line below the row's bottom edge,
/// where it is clipped to a row of half-glyphs.
///
/// This is right by construction instead of by a constant: same class, same
/// cell settings, same answer. A fudge factor would have to be re-found every
/// time a font, an inset, or a system version moved underneath it.
func measuredHeight(_ text: String, font: NSFont, width: CGFloat) -> CGFloat {
    textRuler.font = font
    textRuler.stringValue = text.isEmpty ? " " : text
    let bounds = NSRect(x: 0, y: 0, width: max(10, width), height: .greatestFiniteMagnitude)
    guard let h = textRuler.cell?.cellSize(forBounds: bounds).height else { return font.pointSize }
    return ceil(h)
}

func lerp(_ a: NSPoint, _ b: NSPoint, _ t: CGFloat) -> NSPoint {
    NSPoint(x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t)
}

/// Scales the current context about the middle of a square of the given side.
/// Concatenated, so the caller is expected to have saved the graphics state.
func scaleAboutCentre(_ s: CGFloat, side: CGFloat) {
    let xf = NSAffineTransform()
    xf.translateX(by: side / 2, yBy: side / 2)
    xf.scale(by: s)
    xf.translateX(by: -side / 2, yBy: -side / 2)
    xf.concat()
}

/// Text struck through as far along as `t` has got, dimming as it goes.
///
/// Shared by the item row and its steps so the two tick the same way. The line
/// is the part that means "done", so it is worth watching it get drawn — and
/// unticking runs the same thing backwards for free.
func struckText(_ text: String, tick t: CGFloat, font: NSFont) -> NSAttributedString {
    let colour = t >= 1 ? NSColor.tertiaryLabelColor
                        : NSColor.labelColor.withAlphaComponent(1 - 0.74 * t)
    let s = NSMutableAttributedString(
        string: text, attributes: [.font: font, .foregroundColor: colour])
    let n = (text as NSString).length
    let cut = min(n, Int((CGFloat(n) * t).rounded()))
    guard cut > 0 else { return s }
    // Rounded out to whole characters: a range that stops halfway through a
    // composed sequence is not one an emoji survives.
    let r = (text as NSString)
        .rangeOfComposedCharacterSequences(for: NSRange(location: 0, length: cut))
    s.addAttributes([.strikethroughStyle: NSUnderlineStyle.single.rawValue,
                     .strikethroughColor: NSColor.tertiaryLabelColor], range: r)
    return s
}

// MARK: - Step row

/// One step under a to-do: a small checkbox, its text, and — on hover — a ↥ that
/// makes it a to-do of its own and a ✕ that removes it.
///
/// A view in its own right rather than N sets of fields juggled by `ItemRowView`,
/// because each step needs the same four-way relationship between a checkbox, a
/// field editor, and two hover buttons that the item row already has, and one
/// object owning one step's worth of that is the only version that stays
/// readable at N > 1.
///
/// It is a subview of the item row, which is what makes dragging free: the whole
/// block lifts together because the steps are inside the thing being lifted.
final class SubRowView: FlippedView {
    static let font = NSFont.systemFont(ofSize: 12)
    static let boxSide: CGFloat = 13
    /// How far a step is inset past the item's own text.
    static let indent: CGFloat = 16
    /// The ↳, the box, and the gap after it.
    static let leading: CGFloat = indent + 12 + boxSide + 5
    static let buttonSide: CGFloat = 11
    /// What the two hover buttons and their gaps reserve on the right. Held
    /// clear at all times rather than only on hover, for the same reason the
    /// item row reserves its ✕: a row that rearranges itself under the cursor is
    /// worse than one that pays the width.
    static let buttonGutter: CGFloat = buttonSide * 2 + 6 + 6

    /// The width a step's text gets. The single source of truth for both
    /// `height(for:width:)` and `layout()` — see `measuredHeight`: a row
    /// measured at one width and wrapped at another clips its own last line.
    static func textWidth(in width: CGFloat) -> CGFloat {
        max(10, width - leading - buttonGutter - M.pad)
    }

    static func height(for sub: SubItem, width: CGFloat) -> CGFloat {
        max(15, measuredHeight(sub.text, font: font, width: textWidth(in: width)))
    }

    /// Which step this is, under its parent. Reassigned by `syncSubRows` rather
    /// than fixed at creation: the views are reused across reloads, so a step
    /// removed from the middle shifts every view below it onto a new index.
    var index = 0
    weak var owner: ItemRowView?

    let check = NSButton()
    let field = NSTextField()
    lazy var promote = symbolButton("arrow.turn.left.up", size: 9, target: self,
                                    action: #selector(promoteTapped))
    lazy var del = symbolButton("xmark", size: 8, target: self,
                                action: #selector(deleteTapped))

    var palette: Palette = .of(.auto, systemDark: false) {
        didSet { render() }
    }
    /// Set while this step is the one being dragged, so it draws lifted and the
    /// item row holds a gap open where it would land.
    var lifted = false { didSet { needsDisplay = true } }
    private var accent: NSColor = .systemBlue
    private var text = ""
    private var tick: CGFloat = 0

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
        field.font = SubRowView.font
        field.placeholderString = L("field.subItem")
        field.cell?.usesSingleLineMode = false
        field.cell?.wraps = true
        field.cell?.isScrollable = false
        field.maximumNumberOfLines = 0

        promote.toolTip = L("row.promoteSub.tip")
        del.toolTip = L("row.deleteSub.tip")
        promote.isHidden = true
        del.isHidden = true
        [check, field, promote, del].forEach(addSubview)
    }

    required init?(coder: NSCoder) { fatalError() }

    /// `hovered` is the parent row's hover, not this view's: the buttons appear
    /// when the pointer is anywhere on the block, so moving between a step and
    /// its item does not make them flicker.
    func configure(sub: SubItem, accent: NSColor, hovered: Bool) {
        self.accent = accent
        text = sub.text
        tick = sub.done ? 1 : 0
        promote.isHidden = !hovered
        del.isHidden = !hovered
        render()
        needsLayout = true
    }

    private func render() {
        check.image = ItemRowView.boxImage(tick: tick, accent: accent,
                                           dark: palette.dark,
                                           side: SubRowView.boxSide)
        // Never over the editor. A field being typed into holds the newer text;
        // writing the model's copy back into it would fight the caret.
        guard field.currentEditor() == nil else { return }
        guard tick > 0 else {
            field.stringValue = text
            field.textColor = .secondaryLabelColor
            return
        }
        field.attributedStringValue = struckText(text, tick: tick, font: SubRowView.font)
    }

    override func layout() {
        super.layout()
        let w = bounds.width
        let box = SubRowView.boxSide
        check.frame = NSRect(x: SubRowView.indent + 12, y: 1, width: box, height: box)
        let tw = SubRowView.textWidth(in: w)
        field.frame = NSRect(x: SubRowView.leading, y: 0, width: tw,
                             height: max(14, bounds.height))
        let b = SubRowView.buttonSide
        del.frame = NSRect(x: w - M.pad - b, y: 1, width: b, height: b)
        promote.frame = NSRect(x: w - M.pad - b * 2 - 6, y: 1, width: b, height: b)
    }

    /// The ↳ in front of the step. Drawn rather than folded into the text so the
    /// stored string stays exactly what the user typed.
    override func draw(_ dirtyRect: NSRect) {
        // A step in the air gets its own surface, starting at the depth it is
        // indented to rather than at the row's edge: what is being held is the
        // step, so the card has to begin where the step visibly begins.
        if lifted {
            let r = NSRect(x: SubRowView.indent - 4, y: 0,
                           width: max(0, bounds.width - SubRowView.indent - M.pad + 4),
                           height: bounds.height)
            let path = NSBezierPath(roundedRect: r, xRadius: 6, yRadius: 6)
            NSGraphicsContext.saveGraphicsState()
            NSShadow.drop(radius: 5, alpha: palette.dark ? 0.5 : 0.18, dy: -1).set()
            palette.activeTab.setFill()
            path.fill()
            NSGraphicsContext.restoreGraphicsState()
            palette.hairline.setStroke()
            path.lineWidth = 1
            path.stroke()
        }
        ("↳" as NSString).draw(
            at: NSPoint(x: SubRowView.indent, y: 0),
            withAttributes: [.font: NSFont.systemFont(ofSize: 10),
                             .foregroundColor: NSColor.tertiaryLabelColor])
    }

    func beginEditing(atEnd: Bool = false) {
        window?.makeKeyAndOrderFront(nil)
        window?.makeFirstResponder(field)
        if atEnd { field.currentEditor()?.moveToEndOfDocument(nil) }
    }

    @objc func checkTapped() { owner?.subToggled(index) }
    @objc private func promoteTapped() { owner?.subPromoted(index) }
    @objc private func deleteTapped() { owner?.subDeleted(index) }
}

final class ItemRowView: FlippedView {
    static let font = NSFont.systemFont(ofSize: 14)
    static let checkboxW: CGFloat = 25
    static let trailing: CGFloat = 20
    static let boxSide: CGFloat = 17
    /// Width the creation stamp is right-aligned within. Sized for the widest
    /// string the format can produce — `12/31-23:59` — so no date ever arrives
    /// clipped into a half-date, which would be worse than showing none.
    static let stampW: CGFloat = 57
    static let delSide: CGFloat = 12
    /// Gutter a stamped row keeps clear on the right: the stamp, the ✕, and the
    /// gaps around them.
    ///
    /// Both are reserved even though the ✕ only appears on hover, which costs
    /// every stamped row the ✕'s width all the time. The alternative was to let
    /// them share the strip and swap, and that turned out to be backwards:
    /// pointing at a row is when you are reading it, so it is the last moment
    /// to take something off it. Paying the width buys a row that does not
    /// rearrange itself under the cursor.
    static let stampGutter: CGFloat = stampW + 6 + delSide + 6
    static let stampFont = NSFont.systemFont(ofSize: 9.5)
    /// Gap between the item's own text and the first step under it.
    static let subGap: CGFloat = 2

    /// The width the item's own text gets. Shared by `height(for:)` and
    /// `layout()`, which have to agree exactly: they are the width a row is
    /// measured at and the width it then wraps at, and a row measured against
    /// one number and laid out against another clips its own last line.
    ///
    /// A row with no stamp keeps the old, narrower gutter. That is not just
    /// thrift — items from a notes.json that predates the stamp have nothing to
    /// show there, and reserving the space anyway would reflow every list that
    /// existed before this feature for no visible gain.
    static func textWidth(in width: CGFloat, stamped: Bool) -> CGFloat {
        max(10, width - (M.pad + checkboxW)
                - max(trailing, stamped ? stampGutter : 0) - M.pad)
    }

    weak var delegate: ItemRowDelegate?
    private(set) var itemID: UUID = UUID()

    /// Set on the way in, before `configure`. The box is repainted from here as
    /// well as from there because its empty outline is one of the few things
    /// drawn from a fixed grey, so it is the one thing a theme switch would
    /// otherwise leave behind at the old side's value.
    var palette: Palette = .of(.auto, systemDark: false) {
        didSet {
            renderTick()
            // The steps' boxes are drawn from the same fixed greys and would
            // otherwise keep the old side's value across a theme switch.
            subRows.forEach { $0.palette = palette }
            needsDisplay = true
        }
    }

    private let check = NSButton()
    private let field = NSTextField()
    /// One per step, in order. Reused across reloads rather than rebuilt — see
    /// `syncSubRows`.
    private(set) var subRows: [SubRowView] = []
    private lazy var del = symbolButton("xmark", size: 9, target: self,
                                        action: #selector(deleteTapped))
    private var accent: NSColor = .systemBlue
    /// The row's own text, kept because the label is rebuilt from it on every
    /// frame of the tick and `stringValue` is not a reliable place to read it
    /// back from once an attributed string has been set.
    private var text = ""

    /// How far through the tick the row is: 0 is an empty box and plain text, 1
    /// is the filled box with the line drawn all the way across. Every value
    /// between is a frame of `playTick`. Both end states draw exactly what the
    /// two static states used to, so nothing depends on the animation running.
    private var tick: CGFloat = 0
    private var tickTimer: Timer?
    private static let tickDuration: CGFloat = 0.18

    /// The formatted creation stamp, or nil for an item that has no recorded
    /// creation time. Kept formatted rather than as a `Date` because it is
    /// wanted on every redraw and the row already knows when it changes.
    private var stamp: String?
    private var hovered = false
    private var tracking: NSTrackingArea?

    /// Set by the first Backspace on an empty row: the row is offering to remove
    /// itself, and says so, until the next keystroke either takes it up or calls
    /// it off. See `control(_:textView:doCommandBy:)`.
    private var armed = false
    private var armTimer: Timer?

    /// Set while this row is the one being dragged, so it draws lifted and the
    /// hover wash stays out of the way.
    var lifted = false { didSet { needsDisplay = true } }

    /// Draws a hairline along this row's top edge: everything from here down was
    /// added today. Set by the controller, which is the only thing that can see
    /// a row's neighbours — see `BoardController.dayBreakIndex`.
    var showsDayBreak = false { didSet { needsDisplay = true } }

    deinit { armTimer?.invalidate(); tickTimer?.invalidate() }

    /// Noticky-style checkbox: a rounded square, empty and hairline-thin until
    /// it is ticked, then filled solid with the note's accent. Drawn rather than
    /// taken from SF Symbols because the corner radius is the whole look.
    ///
    /// `t` runs 0…1 so one routine draws both resting states and every frame
    /// between them. At 0 and 1 it produces exactly the two images it always
    /// did; in between the box dips as if pressed, the fill grows out of the
    /// middle, and the tick is stroked on by length rather than faded in, so it
    /// reads as drawn rather than as switched on.
    ///
    /// `side` is a parameter so a step's smaller box is the same drawing at a
    /// smaller size rather than a second one kept in step by hand. The corner
    /// radius scales with it, which is what keeps the two reading as the same
    /// shape — a fixed 5.5 on a 13pt box is visibly rounder.
    static func boxImage(tick t: CGFloat, accent: NSColor, dark: Bool,
                         side: CGFloat = boxSide) -> NSImage {
        return NSImage(size: NSSize(width: side, height: side), flipped: false) { _ in
            let box = NSRect(x: 0.5, y: 0.5, width: side - 1, height: side - 1)
            let r = side * (5.5 / boxSide)
            let path = NSBezierPath(roundedRect: box, xRadius: r, yRadius: r)

            // The whole glyph shrinks and comes back, peaking mid-transition and
            // landing at exactly 1 on both ends. Scaling down rather than
            // overshooting past 1 is deliberate: the image is the size of the
            // box, so anything larger would be clipped square at the corners at
            // the very moment the eye is on it.
            NSGraphicsContext.saveGraphicsState()
            scaleAboutCentre(1 - 0.12 * sin(.pi * t), side: side)

            if t < 1 {
                // Fixed greys rather than dynamic colours: this closure can run
                // outside the view's appearance, where semantic colours would
                // resolve against the wrong side. Two of them, because one grey
                // is not appearance-neutral — the weight that reads as a quiet
                // hairline on paper is a bright ring on a near-black card, which
                // needs markedly less lightness to sit at the same distance.
                NSColor(white: dark ? 0.46 : 0.62, alpha: 1)
                    .withAlphaComponent(1 - min(1, t * 2)).setStroke()
                path.lineWidth = 1.4
                path.stroke()
            }

            if t > 0 {
                // Full size by the time the outline has finished fading, so the
                // two never both read as edges at once — a part-grown fill
                // inside a still-visible ring looks like a box within a box.
                NSGraphicsContext.saveGraphicsState()
                scaleAboutCentre(1 - pow(1 - min(1, t * 2), 2), side: side)
                accent.withAlphaComponent(min(1, t * 4)).setFill()
                path.fill()
                NSGraphicsContext.restoreGraphicsState()
            }

            // Held back until the fill has somewhere to sit, then stroked on
            // over the rest of the transition.
            let q = max(0, (t - 0.35) / 0.65)
            if q > 0 {
                let a = NSPoint(x: side * 0.28, y: side * 0.52)
                let b = NSPoint(x: side * 0.44, y: side * 0.34)
                let c = NSPoint(x: side * 0.74, y: side * 0.68)
                let ab = hypot(b.x - a.x, b.y - a.y), bc = hypot(c.x - b.x, c.y - b.y)
                var left = (ab + bc) * (1 - pow(1 - min(1, q), 2))
                let tick = NSBezierPath()
                tick.move(to: a)
                tick.line(to: lerp(a, b, min(1, left / ab)))
                left -= min(left, ab)
                if left > 0 { tick.line(to: lerp(b, c, min(1, left / bc))) }
                tick.lineWidth = 1.9
                tick.lineCapStyle = .round
                tick.lineJoinStyle = .round
                NSColor.white.setStroke()
                tick.stroke()
            }

            NSGraphicsContext.restoreGraphicsState()
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

        del.isHidden = true
        [check, field, del].forEach(addSubview)
    }

    required init?(coder: NSCoder) { fatalError() }

    static func height(for item: ChecklistItem, width: CGFloat) -> CGFloat {
        let textW = textWidth(in: width, stamped: item.created != nil)
        var h = max(M.rowMin, measuredHeight(item.text, font: font, width: textW) + M.rowPad * 2)
        for sub in item.subs {
            h += SubRowView.height(for: sub, width: width) + subGap
        }
        return h
    }

    /// Grows or shrinks `subRows` to `count` views.
    ///
    /// Reused rather than rebuilt per `configure`: `refreshChrome` reconfigures
    /// every row on every model change, and replacing the views each time would
    /// tear out the field editor of whichever step is being typed into — the
    /// caret would leave the row on the first keystroke.
    private func syncSubRows(count: Int) {
        while subRows.count < count {
            let s = SubRowView()
            s.owner = self
            s.palette = palette
            s.field.delegate = self
            addSubview(s)
            subRows.append(s)
        }
        while subRows.count > count {
            subRows.removeLast().removeFromSuperview()
        }
        for (i, s) in subRows.enumerated() { s.index = i }
    }

    func configure(item: ChecklistItem, accent: NSColor) {
        itemID = item.id
        self.accent = accent
        text = item.text
        stamp = item.created.map(Stamp.text(for:))

        // A refresh that lands mid-tick leaves the tick alone. The frame it is
        // on is more current than the model's end state, and the timer is on its
        // way to that end state regardless — snapping to it here is the one way
        // to make the animation visibly stutter.
        if tickTimer == nil { tick = item.done ? 1 : 0 }
        renderTick()

        syncSubRows(count: item.subs.count)
        for (s, sub) in zip(subRows, item.subs) {
            s.configure(sub: sub, accent: accent, hovered: hovered)
        }
        needsLayout = true
        needsDisplay = true
    }

    /// Paints the box and the label for whatever `tick` currently is. Every
    /// frame of the animation and every `configure` goes through here, so the
    /// two can never end up disagreeing about what the row looks like.
    private func renderTick() {
        check.image = ItemRowView.boxImage(tick: tick, accent: accent, dark: palette.dark)
        guard field.currentEditor() == nil else { return }
        guard tick > 0 else {
            field.stringValue = text
            field.textColor = .labelColor
            return
        }
        field.attributedStringValue = struckText(text, tick: tick, font: ItemRowView.font)
    }

    /// Plays the tick in or out. Driven by a timer rather than by Core
    /// Animation because what moves is a drawn image and a range of text,
    /// neither of which is a layer property anything can interpolate.
    ///
    /// Always restarts from the far end rather than from wherever `tick` sits:
    /// the model has already been written and `configure` has already snapped
    /// the row to the finished state by the time this is called.
    func playTick(to on: Bool) {
        tickTimer?.invalidate()
        tick = on ? 0 : 1
        let step = 1 / (ItemRowView.tickDuration * 60)
        let t = Timer(timeInterval: 1.0 / 60, repeats: true) { [weak self] timer in
            guard let self = self else { return timer.invalidate() }
            self.tick = on ? min(1, self.tick + step) : max(0, self.tick - step)
            if self.tick == (on ? 1 : 0) {
                timer.invalidate()
                self.tickTimer = nil
            }
            self.renderTick()
        }
        // Common modes rather than the default one: a tick set off from the
        // menu bar, or while the list is being scrolled or a row dragged, leaves
        // the run loop in a tracking mode, and a default-mode timer would simply
        // stop for the duration and finish the animation in one jump afterwards.
        RunLoop.current.add(t, forMode: .common)
        tickTimer = t
        renderTick()
    }

    override func layout() {
        super.layout()
        let w = bounds.width
        let side = ItemRowView.boxSide
        let top = M.rowPad
        check.frame = NSRect(x: M.pad, y: top, width: side, height: side)
        del.frame = NSRect(x: w - M.pad - ItemRowView.delSide, y: top + 3,
                           width: ItemRowView.delSide, height: ItemRowView.delSide)

        let x = M.pad + ItemRowView.checkboxW
        let textW = ItemRowView.textWidth(in: w, stamped: stamp != nil)

        let ownH = ownBlockHeight
        field.frame = NSRect(x: x, y: top, width: textW, height: max(14, ownH - top * 2))

        // Each step is measured from its own live text, so the row keeps
        // following along while one is being typed into. Stacked below the
        // item's block, in the order they are shown.
        //
        // `slot` counts the steps that stay put, which is the list the dragged
        // step will be put back into — so it is what `dragSubTo` indexes.
        var y = ownH
        var slot = 0
        let liftedH = dragSub?.frame.height ?? 0
        for s in subRows {
            let sh = max(15, measuredHeight(s.field.stringValue, font: SubRowView.font,
                                            width: SubRowView.textWidth(in: w)))
            // The step in the air follows the cursor; the rest close up behind
            // it and open a gap of exactly its height at the target index, so
            // the block shows where it would land rather than only what it left.
            if s === dragSub {
                s.frame = NSRect(x: 0, y: dragSubY, width: w, height: sh)
                continue
            }
            if dragSub != nil, slot == dragSubTo { y += liftedH + ItemRowView.subGap }
            s.frame = NSRect(x: 0, y: y, width: w, height: sh)
            y += sh + ItemRowView.subGap
            slot += 1
        }
    }

    /// The height of the item's own line — everything above the first step.
    ///
    /// Computed exactly the way `height(for:)` computes it — same expression,
    /// same width — rather than reverse-engineered from whatever the steps left
    /// over. The two have to agree to the pixel: this is the height the row was
    /// measured at, and deriving it a second way means a `max(M.rowMin, …)` that
    /// binds in one place and not the other draws the item's last line over the
    /// first step.
    private var ownBlockHeight: CGFloat {
        let textW = ItemRowView.textWidth(in: bounds.width, stamped: stamp != nil)
        return max(M.rowMin,
                   measuredHeight(field.stringValue, font: ItemRowView.font,
                                  width: textW) + M.rowPad * 2)
    }

    /// The washes, the day-break hairline, and the creation stamp. The ↳ in
    /// front of each step is drawn by the step itself.
    override func draw(_ dirtyRect: NSRect) {
        // Before the washes, so a hovered row draws its wash over the line
        // rather than the line cutting across it. Not while the row is lifted:
        // a row in the air has left the order the line is a statement about.
        if showsDayBreak, !lifted {
            palette.hairline.setFill()
            NSRect(x: M.pad, y: 0, width: max(0, bounds.width - M.pad * 2), height: 1).fill()
        }

        if lifted {
            // A real surface, not a wash: while it moves, the row has to look
            // like it came off the page rather than like a highlighted line.
            let r = bounds.insetBy(dx: 6, dy: 1)
            let path = NSBezierPath(roundedRect: r, xRadius: 8, yRadius: 8)
            NSGraphicsContext.saveGraphicsState()
            NSShadow.drop(radius: 7, alpha: palette.dark ? 0.55 : 0.22, dy: -2).set()
            palette.activeTab.setFill()
            path.fill()
            NSGraphicsContext.restoreGraphicsState()
            palette.hairline.setStroke()
            path.lineWidth = 1
            path.stroke()
        } else if armed {
            // Red rather than the hover grey, because this is the one wash that
            // means something is about to go away. On an empty row it is the
            // only thing there is to see, which is the point — one press has to
            // be visibly different from none.
            NSColor.systemRed.withAlphaComponent(palette.dark ? 0.30 : 0.15).setFill()
            NSBezierPath(roundedRect: bounds.insetBy(dx: 6, dy: 1),
                         xRadius: 8, yRadius: 8).fill()
        } else if hovered {
            palette.hover.setFill()
            NSBezierPath(roundedRect: bounds.insetBy(dx: 6, dy: 1),
                         xRadius: 8, yRadius: 8).fill()
        }

        // When the row was made, just to the left of where the ✕ appears. It
        // stays put and stays visible while the pointer is on the row — that is
        // the moment you are actually reading the row, so it is the wrong one
        // to take anything off it — and darkens a step instead, which is about
        // the only emphasis available to something this small.
        if let s = stamp {
            let p = NSMutableParagraphStyle()
            p.alignment = .right
            (s as NSString).draw(
                in: NSRect(x: bounds.width - M.pad - ItemRowView.delSide - 6 - ItemRowView.stampW,
                           y: M.rowPad + 3, width: ItemRowView.stampW, height: 13),
                withAttributes: [.font: ItemRowView.stampFont,
                                 .foregroundColor: hovered ? NSColor.secondaryLabelColor
                                                           : NSColor.tertiaryLabelColor,
                                 .paragraphStyle: p])
        }
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

    /// The steps' buttons follow the whole block's hover rather than each
    /// step's own, so crossing from the item into a step under it does not make
    /// them blink out and back.
    private func showSubButtons(_ show: Bool) {
        for s in subRows {
            s.promote.isHidden = !show
            s.del.isHidden = !show
        }
    }

    override func mouseEntered(with event: NSEvent) {
        hovered = true; del.isHidden = false; showSubButtons(true); needsDisplay = true
    }

    override func mouseExited(with event: NSEvent) {
        hovered = false; del.isHidden = !armed; showSubButtons(false); needsDisplay = true
    }

    override func resetCursorRects() {
        // The row drags from anywhere on it, so there is no handle to point at
        // and no glyph in the margin pretending to be one. This is the only
        // hint left: the margin is the one part of the row that means nothing
        // else, so an open hand over it can say "movable" without promising
        // that the text under the I-beam is not.
        addCursorRect(NSRect(x: 0, y: 0, width: M.pad, height: bounds.height),
                      cursor: .openHand)
    }

    private var editing: Bool {
        field.currentEditor() != nil || subRows.contains { $0.field.currentEditor() != nil }
    }

    /// The row takes the press itself, so a drag can start anywhere on it.
    ///
    /// It has to be swallowed before the subviews see it: whether a press means
    /// "move this" or "put the caret here" is only known once the pointer has
    /// either moved or failed to, and the text field would have acted on it
    /// long before then. `mouseDown` delivers the click by hand if no drag
    /// follows.
    override func hitTest(_ point: NSPoint) -> NSView? {
        guard let hit = super.hitTest(point) else { return nil }
        // A row with the caret in it is being written, not arranged. Inside the
        // text you are working on a press means a caret, a selection or a
        // shift-extend, and taking those over from the field editor would mean
        // reimplementing all of them worse. Such a row still drags by its grip.
        if editing { return hit }
        // The ✕ is small and already means exactly one thing. So are a step's
        // ↥ and ✕ — nobody aims at an 11pt button and means "drag the row", and
        // routing them through `deliver(click:)` instead would make each of them
        // a case there for no gain.
        if hit === del { return hit }
        if subRows.contains(where: { $0.promote === hit || $0.del === hit }) { return hit }
        return self
    }

    /// Rows are reordered by dragging them up or down.
    override func mouseDown(with event: NSEvent) {
        window?.makeKeyAndOrderFront(nil)
        let start = event.locationInWindow
        let local = convert(start, from: nil)
        let grab = local.y
        // What the press would have landed on, had the row not taken it.
        let under = superview.flatMap { super.hitTest($0.convert(start, from: nil)) }
        // Captured once rather than read per event: ending another row's edit
        // can drop an empty ↳ line, which rebuilds the list and takes this view
        // out of the hierarchy while the gesture is still running. The
        // controller follows the drag by item id and is unbothered, but a
        // `superview` read after that point would be nil and strand it.
        let host = superview
        // A press on a step moves that step among its siblings; a press on the
        // item's own line moves the whole block, steps and all. Which of the two
        // was meant is the one thing the pointer already says without ambiguity,
        // so there is no modifier and no second handle to find.
        let step = subRows.first { $0.frame.contains(local) }
        // Read before the step is in the air. Afterwards its own frame is
        // wherever the hand has taken it, so a grip measured against it per
        // event would compound into a slide.
        let stepGrab = step.map { grab - $0.frame.minY }
        var dragging = false

        // A local event loop rather than mouseDragged/mouseUp overrides: the
        // rows underneath are rebuilt as the order changes, and a half-finished
        // gesture spread over three callbacks on a view that may be replaced
        // mid-drag is far easier to get wrong.
        while let e = window?.nextEvent(matching: [.leftMouseDragged, .leftMouseUp]) {
            if e.type == .leftMouseUp { break }
            let p = e.locationInWindow
            if !dragging {
                // Below AppKit's own drag threshold this is still a click.
                guard abs(p.y - start.y) > 3 || abs(p.x - start.x) > 3 else { continue }
                dragging = true
                NSCursor.closedHand.push()
                if let step = step { subDragBegan(step) }
                else { delegate?.rowDragBegan(itemID, grabOffset: grab) }
            }
            if let stepGrab = stepGrab {
                subDragMoved(to: convert(p, from: nil).y - stepGrab)
                continue
            }
            guard let host = host else { continue }
            delegate?.rowDragMoved(to: host.convert(p, from: nil).y - grab)
        }

        if dragging {
            NSCursor.pop()
            if step != nil { subDragEnded() } else { delegate?.rowDragEnded() }
            return
        }
        deliver(click: event, to: under)
    }

    // MARK: Step reordering

    /// ⌥↑ / ⌥↓ — move whatever the caret is in one place: a step among its
    /// siblings, or the whole item among the other items.
    ///
    /// Taken as a key equivalent rather than in `control(_:textView:doCommandBy:)`
    /// where every other key is handled, because AppKit's own binding for ⌥↑ is
    /// *two* commands — `moveBackward:` and then `moveToBeginningOfParagraph:`.
    /// Answering the second still lets the first through, so the caret would
    /// creep one character left on every press. A key equivalent is offered
    /// before the field editor is given the event at all, which is the only
    /// place the pair can be stopped as one thing.
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        // Option and nothing else. Not `== .option`: an arrow key carries
        // `.function` and `.numericPad` of its own, so an equality test here
        // matches a synthetic event and never a real keystroke.
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        guard flags.contains(.option),
              flags.isDisjoint(with: [.command, .control, .shift])
        else { return false }
        let up: Bool
        switch event.keyCode {
        case 126: up = true      // ↑
        case 125: up = false     // ↓
        default: return false
        }
        // Every row in the window is offered every keystroke, so this has to be
        // the row the caret is actually in — and which field within it.
        if let i = subRows.firstIndex(where: { $0.field.currentEditor() != nil }) {
            moveStep(from: i, to: up ? i - 1 : i + 1)
            // Swallowed even at the ends of the list. The alternative is that
            // ⌥↑ on the first step falls through to AppKit and jumps the caret
            // instead, which is a strange answer to "move this up".
            return true
        }
        guard field.currentEditor() != nil else { return false }
        delegate?.rowMoveItem(itemID, up: up)
        return true
    }

    /// Live state of a step drag: which step is in the air, and where it would
    /// land if let go.
    ///
    /// Kept here rather than in the controller, unlike the item drag. A step
    /// never leaves the item it belongs to, so everything the gesture moves is
    /// already laid out by this view — and staying local means the gesture makes
    /// no model call until the drop, which is what keeps a mid-drag rebuild from
    /// pulling this view out from under its own event loop.
    private var dragSub: SubRowView?
    private var dragSubFrom = 0
    private var dragSubTo = 0
    private var dragSubY: CGFloat = 0

    private func subDragBegan(_ s: SubRowView) {
        guard let from = subRows.firstIndex(where: { $0 === s }) else { return }
        dragSub = s
        s.lifted = true
        dragSubFrom = from
        dragSubTo = from
        dragSubY = s.frame.minY
        // The hover buttons go away for the length of the gesture. A step in the
        // air is not a step you can aim a ✕ at, and the held one carrying two
        // buttons through the air is the clearest way to suggest otherwise.
        showSubButtons(false)
        // Above its siblings, so the surface it draws is not cut into by the
        // step it is passing over.
        addSubview(s, positioned: .above, relativeTo: nil)
    }

    private func subDragMoved(to y: CGFloat) {
        guard let d = dragSub else { return }
        // Clamped to the band the steps occupy: a step dragged off the top of
        // its item does not turn into something else, it stops at the first
        // slot. ↥ promotes, and it stays the only way to.
        let floorY = ownBlockHeight
        dragSubY = min(max(floorY, y), max(floorY, bounds.height - d.frame.height))
        // Without animation: this is the thing being held, and interpolating it
        // would leave it trailing the cursor by the animation's whole duration.
        d.frame.origin.y = dragSubY
        // An item with enough steps to run past the bottom of the list would
        // otherwise be steered blind. No timer, unlike the item drag: a step
        // cannot leave its item, so the furthest it can ever ask the list to
        // scroll is the height of one item — which one nudge per event covers,
        // and which a repeating scroll would badly overshoot.
        scrollToVisible(d.frame)

        // Whichever slot's middle the held step's middle is nearest, in the
        // layout the steps had before anything was lifted out of it.
        //
        // Not their live frames: reading those would feed the open gap back into
        // its own input and flicker between two answers while the cursor stands
        // still. And not the stack with the lifted step taken out either —
        // there, a step's own slot sits exactly on the boundary, so one point of
        // travel would already reorder it. Nearest middle asks for half a step
        // of movement before it commits, in either direction, and stays right
        // when the steps are not all the same height.
        let mid = dragSubY + d.frame.height / 2
        var to = 0
        var best = CGFloat.greatestFiniteMagnitude
        var top = floorY
        for (slot, s) in subRows.enumerated() {
            let reach = abs(mid - (top + s.frame.height / 2))
            if reach < best { best = reach; to = slot }
            top += s.frame.height + ItemRowView.subGap
        }
        guard to != dragSubTo else { return }
        dragSubTo = to
        // Only the steps standing aside animate, so the gap glides open. The
        // held one is re-asserted by `layout()` too, but to the value just set
        // above — nothing to interpolate, so it stays welded to the cursor.
        settleSteps(over: 0.12)
    }

    private func subDragEnded() {
        guard let d = dragSub else { return }
        d.lifted = false
        showSubButtons(hovered)
        let from = dragSubFrom, to = dragSubTo
        dragSub = nil
        // Identity rather than range alone: a refresh landing mid-gesture can
        // resync the steps under it, and moving whatever now sits at the old
        // index would rearrange something the hand never touched.
        guard from != to, subRows.indices.contains(from), subRows[from] === d else {
            // Dropped where it started, or onto a list that has changed under
            // it. Nothing to write; just let it settle back into a slot.
            settleSteps(over: 0.14)
            return
        }
        moveStep(from: from, to: to)
    }

    /// Puts a step in a different slot: the views, their indices, the model, and
    /// the animation that takes the moved one there.
    ///
    /// Shared by the drop and by ⌥↑/⌥↓, which is the whole point of it being one
    /// function — two ways of asking for the same move that disagreed about what
    /// it meant would be the kind of difference nobody finds until it bites.
    ///
    /// The views are moved rather than rebuilt so the one that moved animates
    /// from where it was — and so a step being typed into keeps its field
    /// editor, which a reload would take with it. They are also what `configure`
    /// zips the model against, so the two orders have to change together or the
    /// next refresh writes each step's text into the wrong view.
    @discardableResult
    private func moveStep(from: Int, to: Int) -> Bool {
        guard subRows.indices.contains(from), subRows.indices.contains(to),
              from != to else { return false }
        let moved = subRows.remove(at: from)
        subRows.insert(moved, at: to)
        for (i, s) in subRows.enumerated() { s.index = i }
        delegate?.rowMoveSub(itemID, from: from, to: to)
        settleSteps(over: 0.14)
        return true
    }

    private func settleSteps(over duration: TimeInterval) {
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = duration
            ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
            ctx.allowsImplicitAnimation = true
            // Called rather than flagged: `needsLayout` would defer the frames
            // past the end of this group, and they would jump instead.
            layout()
        }
    }

    /// A press that never moved. The row swallowed it to find out whether a
    /// drag was coming, so what it was for has to happen here instead.
    private func deliver(click event: NSEvent, to view: NSView?) {
        if view === check {
            delegate?.rowToggle(itemID)
            return
        }
        // A step's box. It went through `hitTest` like everything else on the
        // row, so its own target/action never fired — this is the path a tick
        // takes when the row was not already being edited.
        if let s = subRows.first(where: { $0.check === view }) {
            subToggled(s.index)
            return
        }
        guard let tf = view as? NSTextField else { return }
        window?.makeFirstResponder(tf)
        guard let ed = tf.currentEditor() as? NSTextView else { return }
        // Where in the text the click actually landed. Becoming first responder
        // selects the whole field — right when ⇥ lands on it, wrong for a click
        // that was aimed at a particular word.
        let p = ed.convert(event.locationInWindow, from: nil)
        ed.setSelectedRange(NSRange(location: ed.characterIndexForInsertion(at: p),
                                    length: 0))
        // The field editor never saw this press, so the counts it would have
        // acted on are honoured here. From the second click onward the row is
        // editing and it receives them itself.
        if event.clickCount == 2 { ed.selectWord(nil) }
        else if event.clickCount >= 3 { ed.selectLine(nil) }
    }

    /// First Backspace on an empty row. Shows the row is about to go and starts
    /// the clock on that offer.
    private func arm() {
        armTimer?.invalidate()
        armed = true
        del.isHidden = false
        needsDisplay = true
        // Long enough that the second press is comfortable, short enough that
        // the offer never outlives the moment that raised it. Coming back to a
        // row still glowing red from a minute ago would be worse than no
        // confirmation at all.
        armTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: false) { [weak self] _ in
            self?.disarm()
        }
    }

    private func disarm() {
        guard armed else { return }
        armTimer?.invalidate()
        armTimer = nil
        armed = false
        del.isHidden = !hovered
        needsDisplay = true
    }

    func beginEditing(atEnd: Bool = false) {
        window?.makeKeyAndOrderFront(nil)
        window?.makeFirstResponder(field)
        if atEnd { field.currentEditor()?.moveToEndOfDocument(nil) }
    }

    /// Puts the caret in the step at `index`, if there still is one there.
    func beginEditing(sub index: Int, atEnd: Bool = false) {
        guard subRows.indices.contains(index) else { return }
        subRows[index].beginEditing(atEnd: atEnd)
    }

    /// Which step, if any, currently holds the caret. The text-field delegate
    /// callbacks arrive naming a control, not an index.
    private func subIndex(of control: AnyObject?) -> Int? {
        subRows.firstIndex { $0.field === (control as? NSTextField) }
    }

    // Called by the steps, which know their own index but not the item's id.
    func subToggled(_ i: Int) { delegate?.rowToggleSub(itemID, index: i) }
    func subPromoted(_ i: Int) { delegate?.rowPromoteSub(itemID, index: i) }
    func subDeleted(_ i: Int) { delegate?.rowCancelSub(itemID, index: i) }

    @objc private func checkTapped() { delegate?.rowToggle(itemID) }
    @objc private func deleteTapped() { delegate?.rowDelete(itemID) }
}

extension ItemRowView: NSTextFieldDelegate {
    func controlTextDidChange(_ obj: Notification) {
        disarm()
        if let i = subIndex(of: obj.object as AnyObject?) {
            delegate?.rowSubTextChanged(itemID, index: i,
                                        text: subRows[i].field.stringValue)
        } else {
            delegate?.rowTextChanged(itemID, field.stringValue)
        }
    }

    func controlTextDidEndEditing(_ obj: Notification) {
        // Losing focus calls off a pending removal too — an armed row the caret
        // has left is just a red row nobody asked for.
        disarm()
        // An untouched step is not a step — drop it rather than leaving an
        // empty ↳ behind.
        if let i = subIndex(of: obj.object as AnyObject?),
           subRows[i].field.stringValue.trimmingCharacters(in: .whitespaces).isEmpty {
            delegate?.rowCancelSub(itemID, index: i)
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
        let sub = subIndex(of: control)
        // Anything that is not another Backspace calls the offer off. Two
        // presses has to mean two *consecutive* presses, or the row could be
        // armed, left alone while the caret went elsewhere, and then taken by a
        // Backspace that meant something else entirely.
        if selector != #selector(NSResponder.deleteBackward(_:)) { disarm() }
        switch selector {
        case #selector(NSResponder.insertNewline(_:)):
            // Return in front of an item that already has text opens a line
            // above it, the way it would in any editor: what you had written
            // stays where you left it and moves down, rather than the blank
            // line appearing on the far side of it.
            //
            // Everywhere else it still goes below — at the end of the text, in
            // the middle of it, on an empty row, or in a step. An empty row is
            // deliberately in that list: above and below are the same place when
            // there is nothing to push, so the simpler path wins.
            //
            // From inside a step it still makes a *to-do*, not another step:
            // Return has meant "another item on the list" everywhere in this app
            // since before steps existed, and Tab is what adds a step.
            //
            // Either way the caret lands in the new row, which is what makes
            // the two cases feel like one key: an empty line appears where you
            // are, and only the text you had already typed moves.
            if sub == nil, !textView.string.isEmpty,
               textView.selectedRange() == NSRange(location: 0, length: 0) {
                delegate?.rowInsertBefore(itemID)
            } else {
                delegate?.rowInsertAfter(itemID)
            }
            return true
        case #selector(NSResponder.insertTab(_:)):
            // Tab descends: from the item it opens the first step, and from a
            // step it opens another one. Pressing it repeatedly is how a list of
            // steps gets typed, so each press has to add one rather than
            // toggling between two fields the way it used to when an item could
            // only have a single follow-up.
            //
            // Where the new one goes splits exactly the way Return's does. At
            // the head of a step that already has text, the blank one takes that
            // step's place and the text moves down; anywhere else it goes below.
            // An empty step is deliberately in the second case: in front of
            // nothing and after nothing are the same place, so the simpler path
            // wins. Either way the caret ends up in the new step.
            guard let i = sub else {
                // From the item's own field the step goes at the top of its
                // list, which is both "below the item" and the only position
                // that exists when there are none yet.
                delegate?.rowAddSub(itemID, at: 0)
                return true
            }
            // Tab in a step that is still blank does nothing: there is nothing
            // to write in a second one until this has something in it, and the
            // caret is already where a fresh step would have put it. This is
            // what stops two Tabs in a row leaving an empty step behind.
            guard !textView.string.trimmingCharacters(in: .whitespaces).isEmpty else {
                return true
            }
            let atHead = !textView.string.isEmpty
                && textView.selectedRange() == NSRange(location: 0, length: 0)
            delegate?.rowAddSub(itemID, at: atHead ? i : i + 1)
            return true
        case #selector(NSResponder.insertBacktab(_:)):
            // ⇧Tab is the way back up, and it is the whole reason Tab is free to
            // mean "add" — the pair still gets typed without leaving the
            // keyboard, just not by the same key.
            guard let i = sub else { return false }
            if i == 0 { beginEditing(atEnd: true) } else { beginEditing(sub: i - 1, atEnd: true) }
            return true
        case #selector(NSResponder.cancelOperation(_:)):
            // Esc is the way out of a mis-typed Tab. From a step it backs up
            // into whatever is above it (dropping the step if it is still
            // empty); from the item it just gives up focus, which commits the
            // text — Esc here means "I'm done", not "throw away what I typed".
            if let i = sub {
                delegate?.rowCancelSub(itemID, index: i)
            } else {
                window?.makeFirstResponder(nil)
            }
            return true
        case #selector(NSResponder.deleteBackward(_:)):
            // Backspace on an empty field means "take this line back" — there is
            // nothing to its left to delete, and a stray Return is the usual way
            // to end up here. A field with any text in it is left alone.
            guard textView.string.isEmpty else { disarm(); return false }
            // A step goes on one press: it holds nothing, it was opened a moment
            // ago with Tab, and Esc already drops it the same way.
            if let i = sub {
                disarm()
                delegate?.rowCancelSub(itemID, index: i)
                return true
            }
            // The row itself takes two. Backspace is a reflex at the start of a
            // line, and a row vanishing under the caret on the first press is
            // startling even when nothing was written in it. The first press
            // only offers — the row turns red and waits.
            guard armed else { arm(); return true }
            disarm()
            delegate?.rowDeleteEmpty(itemID)
            return true
        case #selector(NSResponder.moveUp(_:)):
            guard caretAtEdgeLine(textView, top: true) else { return false }
            delegate?.rowMoveFocus(from: itemID, in: sub.map(RowField.sub) ?? .main, up: true)
            return true
        case #selector(NSResponder.moveDown(_:)):
            guard caretAtEdgeLine(textView, top: false) else { return false }
            delegate?.rowMoveFocus(from: itemID, in: sub.map(RowField.sub) ?? .main, up: false)
            return true
        default:
            return false
        }
    }
}

