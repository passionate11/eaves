import AppKit

// MARK: - Resize handles

/// Which window edge a handle drags. The top edge is missing on purpose — that
/// is the tab strip, where a drag moves the window instead.
enum ResizeKind {
    case left, right, bottom, bottomLeft, bottomRight
}

/// A thin invisible strip along one window edge. The panel is borderless, so
/// AppKit contributes no resize behaviour of its own; these supply it.
final class ResizeHandle: FlippedView {
    let kind: ResizeKind
    var onResize: (() -> Void)?
    var onEnd: (() -> Void)?

    private var startFrame: NSRect = .zero
    private var startPoint: NSPoint = .zero

    init(_ kind: ResizeKind) {
        self.kind = kind
        super.init(frame: .zero)
    }

    required init?(coder: NSCoder) { fatalError() }

    private var cursor: NSCursor {
        if #available(macOS 15.0, *) {
            switch kind {
            case .left: return .frameResize(position: .left, directions: .all)
            case .right: return .frameResize(position: .right, directions: .all)
            case .bottom: return .frameResize(position: .bottom, directions: .all)
            case .bottomLeft: return .frameResize(position: .bottomLeft, directions: .all)
            case .bottomRight: return .frameResize(position: .bottomRight, directions: .all)
            }
        }
        switch kind {
        case .left, .right: return .resizeLeftRight
        case .bottom: return .resizeUpDown
        case .bottomLeft, .bottomRight: return .crosshair
        }
    }

    override func resetCursorRects() { addCursorRect(bounds, cursor: cursor) }

    override func mouseDown(with event: NSEvent) {
        startFrame = window?.frame ?? .zero
        startPoint = NSEvent.mouseLocation
    }

    override func mouseDragged(with event: NSEvent) {
        guard let w = window else { return }
        let p = NSEvent.mouseLocation
        let dx = p.x - startPoint.x
        let dy = p.y - startPoint.y
        var f = startFrame

        switch kind {
        case .left, .bottomLeft:
            f.size.width = max(M.minWidth, startFrame.width - dx)
            f.origin.x = startFrame.maxX - f.size.width      // right edge stays put
        case .right, .bottomRight:
            f.size.width = max(M.minWidth, startFrame.width + dx)
        case .bottom:
            break
        }
        switch kind {
        case .bottom, .bottomLeft, .bottomRight:
            f.size.height = max(M.minHeight, startFrame.height - dy)
            f.origin.y = startFrame.maxY - f.size.height     // top edge stays put
        case .left, .right:
            break
        }

        w.setFrame(f, display: true)
        onResize?()
    }

    override func mouseUp(with event: NSEvent) { onEnd?() }

    /// Only the bottom-right corner draws: three ticks, so the window still
    /// advertises that it can be resized at all.
    override func draw(_ dirtyRect: NSRect) {
        guard kind == .bottomRight else { return }
        NSColor.tertiaryLabelColor.withAlphaComponent(0.5).setStroke()
        let p = NSBezierPath()
        for i in stride(from: 4, through: 10, by: 3) {
            p.move(to: NSPoint(x: bounds.maxX - CGFloat(i), y: bounds.maxY - 3))
            p.line(to: NSPoint(x: bounds.maxX - 3, y: bounds.maxY - CGFloat(i)))
        }
        p.lineWidth = 1
        p.stroke()
    }
}

// MARK: - Chrome

/// The accent progress line along the bottom edge of the tab strip.
///
/// Full-bleed and only two points tall, sitting exactly on the strip's own
/// hairline: it reads as the boundary between chrome and list filling in, which
/// is the one place a coloured bar can live without becoming the loudest thing
/// in the window. An earlier inset pill with a visible groove looked like a
/// download progress bar bolted to a to-do list.
final class ProgressBarView: FlippedView {
    private var fraction: CGFloat = 0
    private var accent: NSColor = .systemBlue
    var track: NSColor = NSColor(white: 0, alpha: 0.08) { didSet { needsDisplay = true } }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    func configure(done: Int, total: Int, accent: NSColor) {
        fraction = total > 0 ? CGFloat(done) / CGFloat(total) : 0
        self.accent = accent
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        track.setFill()
        bounds.fill()
        guard fraction > 0 else { return }
        // Softened: at full saturation a red line across the whole width pulls
        // the eye away from the text it is reporting on.
        accent.withAlphaComponent(0.85).setFill()
        NSRect(x: 0, y: 0, width: bounds.width * min(1, fraction),
               height: bounds.height).fill()
    }
}

/// The note's actual surface.
///
/// Solid by default. Frosted glass inverts contrast on macOS — the system draws
/// the focused window as glass and background windows as opaque, so a
/// translucent note reads worst exactly while it is being used. The `.glass`
/// theme keeps the frosted look for anyone who wants it; the rest paint a real
/// surface here and leave the vibrancy view behind them switched off.
/// Click-through, so it never swallows a press meant for the view underneath.
final class CardView: FlippedView {
    var palette: Palette = .of(.auto, systemDark: false) {
        didSet { needsDisplay = true }
    }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func draw(_ dirtyRect: NSRect) {
        let r = M.corner - 0.5
        let path = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5),
                                xRadius: r, yRadius: r)
        // A vertical gradient rather than a flat fill: the top reads as
        // catching the light, which is what keeps a flat panel from looking
        // like a rectangle of paint.
        //
        // `angle: 90`, not -90, because this view is flipped — in a flipped
        // context an angle points the opposite way down the screen, so the two
        // ends of the gradient come out swapped.
        NSGradient(starting: palette.cardTop, ending: palette.card)?
            .draw(in: path, angle: 90)

        // The highlight just inside the rim along the top edge. This, more than
        // the gradient, is what makes a panel read as a raised surface: it is
        // where a real material would catch the light on its own bevel.
        //
        // Filled as a ring rather than stroked and clipped, so the gradient can
        // fade it out down the sides. A stroke clipped to the top would have to
        // stop somewhere, and wherever it stopped would be a visible stub.
        let ring = NSBezierPath()
        ring.append(NSBezierPath(roundedRect: bounds.insetBy(dx: 1, dy: 1),
                                 xRadius: r - 0.5, yRadius: r - 0.5))
        ring.append(NSBezierPath(roundedRect: bounds.insetBy(dx: 2, dy: 2),
                                 xRadius: r - 1.5, yRadius: r - 1.5))
        ring.windingRule = .evenOdd
        // Fading to the same colour at zero alpha rather than to `.clear`, so
        // the interpolation cannot travel through some other hue on the way out.
        NSGradient(colorsAndLocations: (palette.innerLight, 0),
                   (palette.innerLight.withAlphaComponent(0), 0.28))?
            .draw(in: ring, angle: 90)

        palette.rim.setStroke()
        path.lineWidth = 1
        path.stroke()
    }
}

/// A one-pixel divider. Used above the footer so the add-field reads as its own
/// zone without spending real estate on a heavier separator.
final class HairlineView: FlippedView {
    var color: NSColor = .clear { didSet { needsDisplay = true } }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func draw(_ dirtyRect: NSRect) {
        color.setFill()
        bounds.fill()
    }
}

/// Empty space that means "start a new to-do": the band the add field sits in,
/// and whatever is left below the last row.
///
/// The add field is one line of text in a much taller footer, and the list
/// usually ends well above the bottom of the window. Both leave large areas
/// that look like they should take a click and, until now, did nothing —
/// so the caret was reachable only by aiming at the placeholder itself.
final class AddZoneView: FlippedView {
    var fill: NSColor = .clear { didSet { needsDisplay = true } }
    /// Painted while the pointer is inside, if `showsHover` is set.
    var wash: NSColor = .clear
    /// Only the footer lights up. The blank area under the list is clickable
    /// too, but washing half the window on hover would be noise, not an
    /// affordance.
    var showsHover = false
    var onClick: (() -> Void)?

    private var hovered = false
    private var tracking: NSTrackingArea?

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        guard showsHover else { return }
        if let t = tracking { removeTrackingArea(t) }
        let t = NSTrackingArea(rect: bounds,
                               options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                               owner: self)
        addTrackingArea(t)
        tracking = t
    }

    override func mouseEntered(with event: NSEvent) { hovered = true; needsDisplay = true }
    override func mouseExited(with event: NSEvent) { hovered = false; needsDisplay = true }

    override func mouseDown(with event: NSEvent) {
        window?.makeKeyAndOrderFront(nil)
        onClick?()
    }

    override func draw(_ dirtyRect: NSRect) {
        fill.setFill()
        bounds.fill()
        guard showsHover, hovered else { return }
        wash.setFill()
        bounds.fill()
    }
}

/// Root view of the window. A vibrancy view, so the desktop shows through; it
/// also owns the hover tracking area that drives the inactive fade.
final class BoardRootView: NSVisualEffectView {
    override var isFlipped: Bool { true }

    var onEnter: (() -> Void)?
    var onExit: (() -> Void)?
    var onAppearanceChange: (() -> Void)?
    private var tracking: NSTrackingArea?

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        onAppearanceChange?()
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

    override func mouseEntered(with event: NSEvent) { onEnter?() }
    override func mouseExited(with event: NSEvent) { onExit?() }
    override func mouseDown(with event: NSEvent) { window?.makeKeyAndOrderFront(nil) }
}

// MARK: - Controller

/// Owns the single shared window. Every note is a tab in it; only the selected
/// note's checklist is built into views, so switching tabs is a rebuild of the
/// body rather than a window swap.

final class BoardController: NSObject, NSWindowDelegate {
    let window: NoteWindow

    private let root = BoardRootView()
    private let card = CardView()
    private let tabBar = TabBarView()
    private let bar = ProgressBarView()
    private let scroll = NSScrollView()
    private let rowsHost = AddZoneView()
    private let footerBand = AddZoneView()
    private let footerLine = HairlineView()
    private let addField = NSTextField()
    private let emptyLabel = plainField("", size: 12)
    private let handles: [ResizeHandle] = [
        ResizeHandle(.left), ResizeHandle(.right), ResizeHandle(.bottom),
        ResizeHandle(.bottomLeft), ResizeHandle(.bottomRight),
    ]

    private var rows: [ItemRowView] = []
    private var mouseInside = false
    private(set) var isRetracted = false

    /// Fires once after the window stops moving, to decide where it should dock.
    private var settleTimer: Timer?
    /// True while this class is the one moving the window, so its own moves do
    /// not come back round as "the user dragged it somewhere".
    private var isPositioning = false

    /// True while any field in the window has a caret in it. `NSText` rather
    /// than the field itself because what holds first-responder status during
    /// editing is the shared field editor, not the control it is editing.
    var isEditing: Bool { window.firstResponder is NSText }

    /// Live state of a row drag: which row is in the air, and where it would
    /// land if it were let go now. Nothing is written to the note until then —
    /// a drag that is abandoned by dropping a row back where it started must
    /// leave no trace, and reordering the model on every mouse-moved event
    /// would rebuild the rows out from under the gesture.
    private var dragRow: ItemRowView?
    private var dragFrom = 0
    private var dragTo = 0
    private var dragY: CGFloat = 0
    /// Runs for the length of a drag. Without it a row can be picked up and have
    /// nowhere to go: a window this size is full at six items, so the slot you
    /// want is often off-screen, and there is no hand free to scroll with.
    private var dragScroll: Timer?

    /// When the pointer was last seen off the window, and when the user last
    /// typed. Auto-hide reads both: leaving is the trigger, typing is the veto.
    private var pointerLeftAt: Date?
    private var lastTypedAt: Date = .distantPast

    /// The one field editor handed to every text field in the window, kept so
    /// `allowsUndo` is set exactly once, plus whichever control last used it.
    fileprivate var fieldEditor: NSTextView?
    fileprivate weak var lastEditorClient: AnyObject?

    /// The note whose checklist the body is showing.
    private var current: Note? { Store.shared.selected.flatMap { Store.shared.note($0) } }
    private var tabNotes: [Note] { Store.shared.visibleNotes }

    override init() {
        window = NoteWindow(frame: Store.shared.windowFrame)
        super.init()

        // Write the frame straight back, so a geometry that came from migrating
        // an old notes.json is persisted rather than re-derived every launch.
        Store.shared.windowFrame = window.frame

        window.delegate = self
        window.applyFloatOnTop(Store.shared.floatOnTop)

        root.blendingMode = .behindWindow
        // .active, not .followsWindowActiveState: this is an accessory app that
        // is almost never frontmost, and a greyed-out blur would look broken.
        root.state = .active
        // Both, and they do different jobs: the mask rounds the blur itself
        // (which ignores cornerRadius entirely), the layer rounds the subviews
        // drawn on top of it. Without the mask the left corners came out square.
        root.maskImage = roundedMaskImage(radius: M.corner)
        root.wantsLayer = true
        root.layer?.cornerRadius = M.corner
        root.layer?.cornerCurve = .continuous
        root.layer?.masksToBounds = true
        root.onEnter = { [weak self] in
            self?.mouseInside = true
            self?.updateAlpha()
        }
        root.onExit = { [weak self] in
            self?.mouseInside = false
            self?.updateAlpha()
        }
        // Only `.auto` and `.glass` track the system; the other two force their
        // own appearance, so re-resolving is a no-op for them.
        root.onAppearanceChange = { [weak self] in
            guard let self, Store.shared.theme == .auto || Store.shared.theme == .glass
            else { return }
            self.applyTheme()
        }

        tabBar.delegate = self

        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.scrollerStyle = .overlay
        scroll.documentView = rowsHost
        scroll.contentView.drawsBackground = false

        addField.isBordered = false
        addField.drawsBackground = false
        addField.focusRingType = .none
        addField.font = .systemFont(ofSize: 12.5)
        addField.placeholderString = L("field.addTodo")
        addField.delegate = self
        addField.cell?.usesSingleLineMode = true

        footerBand.showsHover = true
        for z in [rowsHost, footerBand] {
            z.onClick = { [weak self] in self?.beginAdding() }
        }

        emptyLabel.isEditable = false
        emptyLabel.isSelectable = false
        emptyLabel.alignment = .center
        emptyLabel.textColor = .tertiaryLabelColor
        emptyLabel.stringValue = L("empty.hint")
        emptyLabel.isHidden = true

        for h in handles {
            h.onResize = { [weak self] in self?.layoutContents() }
            h.onEnd = { [weak self] in self?.commitFrame() }
        }

        // footerBand before footerLine so the hairline draws on top of it, and
        // both before addField so the placeholder isn't painted over.
        [card, tabBar, bar, scroll, footerBand, footerLine, addField, emptyLabel]
            .forEach(root.addSubview)
        // Added last so the edge strips sit above the scroll view and the rows.
        handles.forEach(root.addSubview)
        window.contentView = root

        if Store.shared.collapsed {
            var f = window.frame
            f.origin.y = f.maxY - M.tab
            f.size.height = M.tab
            window.setFrame(f, display: false)
        }
        reload()
        applyTheme()
        if Store.shared.dock != .none { retract(animated: false) }

        // Park the initial focus on a view that cannot be typed into. Left nil,
        // AppKit picks the first eligible key view when the window first becomes
        // key — which here is the first todo's text field, so the app comes up
        // with a caret already sitting in a real item and any stray keystroke
        // silently rewrites it. `root` does not accept first responder, so the
        // window keeps focus and nothing is editing until something is clicked.
        window.initialFirstResponder = root

        NotificationCenter.default.addObserver(
            self, selector: #selector(screensChanged),
            name: NSApplication.didChangeScreenParametersNotification, object: nil)

        window.orderFront(nil)
    }

    /// Displays added, removed, or rearranged.
    ///
    /// A dock that was valid can stop being so — plug a second monitor in to the
    /// right of the one holding a right-docked note and the sliver is no longer
    /// at the edge of anything, so sliding out lands the window on the new
    /// screen instead of hiding it. The reverse also happens: unplugging frees
    /// an edge that was previously shared. Re-checking here keeps the docked
    /// state honest across both, and rescues a window whose screen just went
    /// away.
    @objc private func screensChanged() {
        guard Store.shared.dock != .none else {
            clampOnScreen()
            return
        }
        if hasNeighbor(beyond: Store.shared.dock) {
            Store.shared.dock = .none
            isRetracted = false
            window.hasShadow = true
            clampOnScreen()
            refreshChrome()
            commitFrame()
            return
        }
        // Still a real edge — but the screen may have resized underneath it, so
        // re-seat the window against wherever that edge is now.
        var f = window.frame
        f.origin = isRetracted ? retractedOrigin() : expandedOrigin()
        setFrame(f, animated: false)
    }

    // MARK: Theme

    /// System dark mode, read independent of any appearance we have forced on
    /// the window — otherwise `.auto` would latch onto its own output.
    private var systemIsDark: Bool {
        NSApp.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
    }

    private(set) var palette: Palette = .of(.auto, systemDark: false)

    /// Pushes the active theme into the window and every view that paints a
    /// surface. Called at launch, on a theme change, and when the system flips
    /// between light and dark.
    func applyTheme() {
        let theme = Store.shared.theme
        palette = .of(theme, systemDark: systemIsDark)

        // Forcing the appearance is what makes "always light" / "always dark"
        // actually mean it: semantic colours in every text field resolve against
        // this, not against the system setting.
        window.appearance = theme.appearance

        // The vibrancy view only does work for the glass theme. The others paint
        // an opaque card over it, so the blur would be invisible anyway — and
        // switching it off keeps the window server from compositing it at all.
        let glass = theme.resolved(dark: systemIsDark).isGlass
        root.material = glass ? .popover : .windowBackground
        root.state = glass ? .active : .inactive
        window.isOpaque = false

        card.palette = palette
        footerBand.wash = palette.hover
        footerLine.color = palette.hairline
        bar.track = palette.track
        rows.forEach { $0.palette = palette }
        // A theme switch can change whether the idle fade applies at all.
        updateAlpha()
        // The tab strip and the footer are not set here: their colour depends on
        // the selected note as well as on the theme, so `refreshChrome` owns
        // them and this call is what pushes the new theme through to them.
        refreshChrome()
    }

    // MARK: Rendering

    /// Full rebuild: tab strip plus the selected note's rows.
    func reload() {
        rows.forEach { $0.removeFromSuperview() }
        rows = (current?.items ?? []).map { item in
            let r = ItemRowView()
            r.delegate = self
            r.palette = palette
            r.configure(item: item, accent: current?.color.accent ?? .systemBlue)
            rowsHost.addSubview(r)
            return r
        }
        refreshChrome()
        layoutContents()
    }

    /// Cheap refresh: tab titles and progress, row check state, colours.
    func refreshChrome() {
        let color = current?.color ?? .gray
        // Chrome top and bottom, list in between — and both bands carry a wash
        // of the selected note's colour, which is the only thing in the window
        // that makes one note look different from another at a glance.
        let chrome = palette.tinted(by: color.accent)
        footerBand.fill = chrome.header
        tabBar.palette = chrome
        tabBar.configure(notes: tabNotes, selected: current?.id,
                         collapsed: Store.shared.collapsed,
                         hideEdge: hideEdge, autoHide: Store.shared.autoHide)
        bar.configure(done: current?.doneCount ?? 0,
                      total: current?.items.count ?? 0, accent: color.accent)
        for (r, item) in zip(rows, current?.items ?? []) {
            r.configure(item: item, accent: color.accent)
        }
        let brk = dayBreakIndex(current?.items ?? [])
        for (i, r) in rows.enumerated() { r.showsDayBreak = (i == brk) }
    }

    /// Where to draw the line that says "everything below this started today",
    /// or nil for "nowhere".
    ///
    /// Only when today's items form an unbroken run at the bottom of the list.
    /// Rows can be dragged anywhere, so today is not guaranteed to be a block at
    /// all, and a line across an interleaved list would assert a boundary that
    /// is not there. Drawing nothing is the honest answer, and a hairline this
    /// quiet is not missed on the days it cannot be earned.
    ///
    /// Rows written before the app recorded creation times count as older, which
    /// is the one thing a missing timestamp definitely means.
    private func dayBreakIndex(_ items: [ChecklistItem]) -> Int? {
        let today = Calendar.current
        let now = Date()
        func isToday(_ item: ChecklistItem) -> Bool {
            guard let c = item.created else { return false }
            return today.isDate(c, inSameDayAs: now)
        }
        guard let first = items.firstIndex(where: isToday),
              // Nothing above it to divide from: the whole list is today's.
              first > 0,
              items[first...].allSatisfy(isToday) else { return nil }
        return first
    }

    func layoutContents() {
        let w = root.bounds.width
        let h = root.bounds.height
        card.frame = root.bounds
        tabBar.frame = NSRect(x: 0, y: 0, width: w, height: M.tab)
        // configure() lays the tabs out against the strip's own bounds, so it
        // has to run again after a width change.
        refreshTabsLayout()

        if Store.shared.collapsed {
            bar.isHidden = true
            scroll.isHidden = true
            addField.isHidden = true
            footerLine.isHidden = true
            footerBand.isHidden = true
            emptyLabel.isHidden = true
            handles.forEach { $0.isHidden = true }
            return
        }
        layoutHandles(width: w, height: h)

        let empty = current == nil
        scroll.isHidden = empty
        addField.isHidden = empty
        footerLine.isHidden = empty
        footerBand.isHidden = empty
        emptyLabel.isHidden = !empty
        bar.isHidden = empty || (current?.items.isEmpty ?? true)

        // Sits on the tab strip's bottom edge, full width, replacing its
        // hairline where it is drawn. Chrome and list stay flush: no gap for a
        // gauge to float in.
        bar.frame = NSRect(x: 0, y: M.tab - M.progressBar, width: max(1, w),
                           height: M.progressBar)
        let top = M.tab

        if empty {
            emptyLabel.frame = NSRect(x: 0, y: (h + M.tab) / 2 - 10, width: w, height: 20)
            return
        }

        let listH = max(0, h - top - M.footer)
        scroll.frame = NSRect(x: 0, y: top, width: w, height: listH)

        let items = current?.items ?? []
        var y: CGFloat = 6
        // `slot` counts the rows that stay put, which is the list the dragged
        // row will be inserted back into — so it is what `dragTo` indexes.
        var slot = 0
        let liftedH = dragRow?.frame.height ?? 0
        for (r, item) in zip(rows, items) {
            let rh = ItemRowView.height(for: item, width: w)
            // The row in the air follows the cursor; the rest close up behind it
            // and open a gap of exactly its height at the target index, so the
            // list shows where it would land rather than only what it left.
            if r === dragRow {
                r.frame = NSRect(x: 0, y: dragY, width: w, height: rh)
                continue
            }
            if slot == dragTo { y += liftedH }
            r.frame = NSRect(x: 0, y: y, width: w, height: rh)
            y += rh
            slot += 1
        }
        if dragRow != nil, dragTo >= slot { y += liftedH }
        rowsHost.frame = NSRect(x: 0, y: 0, width: w, height: max(listH, y + 6))

        footerLine.frame = NSRect(x: 0, y: h - M.footer, width: w, height: 1)
        footerBand.frame = NSRect(x: 0, y: h - M.footer, width: w, height: M.footer)
        addField.frame = NSRect(x: M.pad + ItemRowView.checkboxW, y: h - M.footer + 8,
                                width: max(10, w - M.pad * 2 - ItemRowView.checkboxW), height: 18)
    }

    /// Positions the invisible drag strips. Corners are laid out last and win
    /// the overlap, so grabbing a corner resizes both axes.
    private func layoutHandles(width w: CGFloat, height h: CGFloat) {
        let g = M.grab, c = M.grabCorner
        for hd in handles {
            hd.isHidden = false
            switch hd.kind {
            case .left:
                hd.frame = NSRect(x: 0, y: M.tab, width: g, height: max(0, h - M.tab - c))
            case .right:
                hd.frame = NSRect(x: w - g, y: M.tab, width: g, height: max(0, h - M.tab - c))
            case .bottom:
                hd.frame = NSRect(x: c, y: h - g, width: max(0, w - c * 2), height: g)
            case .bottomLeft:
                hd.frame = NSRect(x: 0, y: h - c, width: c, height: c)
            case .bottomRight:
                hd.frame = NSRect(x: w - c, y: h - c, width: c, height: c)
            }
            window.invalidateCursorRects(for: hd)
        }
    }

    private func refreshTabsLayout() {
        tabBar.configure(notes: tabNotes, selected: current?.id,
                         collapsed: Store.shared.collapsed,
                         hideEdge: hideEdge, autoHide: Store.shared.autoHide)
    }

    /// The idle fade only applies to `.glass`. On a solid theme a 4% fade is
    /// enough to let a bright terminal behind the note show straight through the
    /// card — which defeats the point of picking an opaque surface in the first
    /// place. Glass is already translucent, so there the fade costs nothing.
    private func updateAlpha() {
        let solid = !Store.shared.theme.resolved(dark: systemIsDark).isGlass
        let target: CGFloat = (solid || mouseInside || window.isKeyWindow) ? 1.0 : M.fadeAlpha
        guard abs(window.alphaValue - target) > 0.01 else { return }
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.16
            window.animator().alphaValue = target
        }
    }

    // MARK: Model sync

    private func commit(_ mutate: (inout Note) -> Void) {
        guard let id = current?.id else { return }
        Store.shared.update(id, mutate)
    }

    /// Persists the window frame. While collapsed only the origin is live — the
    /// stored height stays at its expanded value so unfolding restores it. While
    /// docked the origin belongs to the dock, but a resize still has to stick.
    private func commitFrame() {
        var f = Store.shared.windowFrame
        if Store.shared.dock != .none {
            f.size = window.frame.size
            Store.shared.windowFrame = f
            return
        }
        if Store.shared.collapsed {
            f.origin.x = window.frame.origin.x
            f.origin.y = window.frame.maxY - f.size.height
        } else {
            f = window.frame
        }
        Store.shared.windowFrame = f
    }

    // MARK: Selection

    func select(_ id: UUID) {
        guard Store.shared.selected != id else { return }
        Store.shared.selected = id
        reload()
    }

    // MARK: Collapse

    func toggleCollapse() {
        if !Store.shared.collapsed { commitFrame() }
        Store.shared.collapsed.toggle()

        var f = window.frame
        let newH = Store.shared.collapsed ? M.tab : Store.shared.windowFrame.height
        f.origin.y = f.maxY - newH          // keep the top edge pinned
        f.size.height = newH
        refreshChrome()
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.18
            window.animator().setFrame(f, display: true)
        }, completionHandler: { [weak self] in
            self?.layoutContents()
            self?.commitFrame()
        })
        layoutContents()
    }

    // MARK: Docking

    private func screenFrame() -> NSRect {
        (window.screen ?? NSScreen.main ?? NSScreen.screens[0]).visibleFrame
    }

    /// The screen edges ranked by how near the window's *centre* is to each,
    /// nearest first.
    ///
    /// Measured from the centre rather than from the matching frame edge, which
    /// is what this used to do and what made docking unpredictable. A window
    /// docked to the top is flush with the top — distance zero, and while
    /// retracted a large negative number — so by frame-edge distance the top won
    /// every comparison it was in, however far to the right the window had been
    /// dragged. That is why dragging a top-docked note to the right side sent it
    /// back to the top, and why one already on the right refused to re-tuck: the
    /// answer never depended on where the note had been put.
    ///
    /// A centre is somewhere the window actually is, whether it is docked, half
    /// off-screen, or mid-slide. Halved on the vertical axis because a landscape
    /// screen is wider than it is tall, so raw centre distances would make the
    /// top and bottom edges win over most of it; this makes the four edges divide
    /// the screen into rough quarters, which is how it looks to the eye.
    private func edgeDistances() -> [(DockEdge, CGFloat)] {
        let sf = screenFrame()
        let c = NSPoint(x: window.frame.midX, y: window.frame.midY)
        let aspect = sf.height > 0 ? sf.width / sf.height : 1
        // Listed right-first so that the dead centre of the screen — where all
        // four distances are exactly equal — resolves to the right edge rather
        // than to whichever way a sort happened to fall. A tie has to have an
        // answer, and for a note this is the side to be on.
        let order: [(DockEdge, CGFloat)] = [
            (.right, sf.maxX - c.x), (.left, c.x - sf.minX),
            (.top, (sf.maxY - c.y) * aspect), (.bottom, (c.y - sf.minY) * aspect),
        ]
        // A stable sort, so equal distances keep the order above.
        return order.enumerated()
            .sorted { ($0.element.1, $0.offset) < ($1.element.1, $1.offset) }
            .map(\.element)
    }

    /// Whether another display sits immediately beyond `edge`, in the band the
    /// window actually occupies.
    ///
    /// This is the difference between an edge of the screen and an edge of the
    /// desktop. Retracting slides the window off `screenFrame()` — which only
    /// hides it if there is nothing on the other side. With a laptop parked to
    /// the left of an external monitor the two frames touch, so "tucking away"
    /// to that shared boundary slid the whole window onto the laptop instead of
    /// out of sight: it looked like the note had walked into the next screen and
    /// stayed there, and auto-hide never fired again because the window was, as
    /// far as the code was concerned, already retracted.
    private func hasNeighbor(beyond edge: DockEdge) -> Bool {
        guard let cur = window.screen ?? NSScreen.main else { return false }
        let c = cur.frame, f = window.frame
        // A 1pt slack: adjoining displays report frames that touch exactly, but
        // floating-point scaling can leave them a hair apart.
        let slack: CGFloat = 1
        for s in NSScreen.screens where s !== cur {
            let o = s.frame
            switch edge {
            case .left:
                if o.maxX <= c.minX + slack, o.maxY > f.minY, o.minY < f.maxY { return true }
            case .right:
                if o.minX >= c.maxX - slack, o.maxY > f.minY, o.minY < f.maxY { return true }
            case .top:
                if o.minY >= c.maxY - slack, o.maxX > f.minX, o.minX < f.maxX { return true }
            case .bottom:
                if o.maxY <= c.minY + slack, o.maxX > f.minX, o.minX < f.maxX { return true }
            case .none:
                return false
            }
        }
        return false
    }

    /// The edges this window can actually disappear into, nearest first.
    private func dockableEdges() -> [(DockEdge, CGFloat)] {
        edgeDistances().filter { !hasNeighbor(beyond: $0.0) }
    }

    /// Pulls a window that was dragged past an edge back far enough that the tab
    /// strip is still clickable. Without this, refusing to dock at a shared
    /// display boundary would just leave the note stranded half off-screen with
    /// no way to grab it — `constrainFrameRect` is overridden, so AppKit will
    /// not rescue it either.
    private func clampOnScreen() {
        let sf = screenFrame()
        var f = window.frame
        // Keep a grabbable amount of the strip on screen rather than the whole
        // window: a note deliberately parked mostly off the side should stay
        // roughly where it was put.
        let keep: CGFloat = 60
        f.origin.x = min(max(sf.minX - f.width + keep, f.origin.x), sf.maxX - keep)
        f.origin.y = min(max(sf.minY - f.height + M.tab, f.origin.y), sf.maxY - M.tab)
        guard f.origin != window.frame.origin else { return }
        setFrame(f, animated: true)
    }


    /// The edge the hide button would tuck the window into: whichever reachable
    /// edge the window is nearest. Edges with another display behind them are
    /// skipped — sliding into one of those does not hide anything.
    ///
    /// Deliberately does *not* short-circuit to the edge already docked to. It
    /// used to, and that one line outranked everything else: the note stayed on
    /// whichever edge it was first put on, however far it was afterwards dragged,
    /// because the current dock was consulted instead of the window's position.
    /// Fixing how the nearest edge is measured could not help while this was
    /// returning before that measurement ran.
    private var hideEdge: DockEdge {
        dockableEdges().first?.0 ?? .right
    }

    /// The hide button, and the menu. Tucks the window into `edge`, or into the
    /// nearest edge when none is given.
    func hideToEdge(_ edge: DockEdge? = nil) {
        let target = edge ?? hideEdge
        guard target != .none else { undock(); return }

        // Re-seated whether or not the edge changed. Only doing this on a change
        // was the other half of "it will not go anywhere": after a drag the
        // window is wherever the hand left it, so even the same edge needs the
        // frame put back against it before the retract below slides it out.
        if Store.shared.dock == .none { commitFrame() }  // remember where it floated
        Store.shared.dock = target
        isRetracted = false
        var f = window.frame
        f.origin = expandedOrigin()
        positioning(0.05) { window.setFrame(f, display: true) }

        retract(animated: true)
        refreshChrome()
    }

    /// Called when a drag in the tab strip ends: dock to whichever edge the
    /// window is now nearest. A click that never moved the window does not reach
    /// here.
    ///
    /// Nearest edge, unconditionally — no distance threshold, no memory of where
    /// the drag started, no preference for the direction the hand went. Three
    /// attempts at cleverer rules each fixed the case in front of me and broke
    /// another: a threshold meant letting go early left the note on its old
    /// edge, and direction-tracking meant a drag whose dominant axis was not the
    /// one I guessed went somewhere unasked-for. Every one of them was a rule
    /// the user had to know to predict the outcome.
    ///
    /// The cost is real and worth naming: the window can no longer float in the
    /// middle of the screen. Drop it anywhere and it goes to an edge. That was
    /// the trade asked for, and it buys a rule with nothing to learn — the note
    /// ends up on the side you put it on.
    func evaluateDock() {
        // Nearest *dockable* edge, so a drag toward the boundary with another
        // display does not arm a dock that could never hide the window.
        // Dragging across that boundary is how the note gets moved to the other
        // screen, and that has to keep working.
        guard let (edge, _) = dockableEdges().first else {
            // Nowhere to dock: every edge adjoins another display. Leave it
            // floating, and make sure it is still grabbable.
            if Store.shared.dock != .none { Store.shared.dock = .none; isRetracted = false }
            clampOnScreen()
            commitFrame()
            refreshChrome()
            return
        }
        commitFrame()
        // Set unconditionally rather than only on a change: the window has just
        // been dragged off its resting place, so even the same edge needs the
        // retract below to put it back. This is the "docked right, dragged
        // flush against the right edge, and it just sat there" case — the edge
        // had not changed, so nothing re-tucked it.
        Store.shared.dock = edge
        isRetracted = false
        retract(animated: true)
        refreshChrome()
    }

    func undock() {
        guard Store.shared.dock != .none else { return }
        let sf = screenFrame()
        var f = window.frame
        f.origin.x = min(max(sf.minX + 20, f.origin.x), sf.maxX - f.width - 20)
        f.origin.y = min(max(sf.minY + 20, f.origin.y), sf.maxY - f.height - 20)
        Store.shared.dock = .none
        isRetracted = false
        window.hasShadow = true
        positioning(0.4) { window.setFrame(f, display: true, animate: true) }
        commitFrame()
        refreshChrome()
    }

    /// Where the window sits when slid out — flush against its edge.
    private func expandedOrigin() -> NSPoint {
        let sf = screenFrame(), f = window.frame
        let free = freeAxisOrigin()
        switch Store.shared.dock {
        case .right: return NSPoint(x: sf.maxX - f.width, y: free.y)
        case .left: return NSPoint(x: sf.minX, y: free.y)
        case .top: return NSPoint(x: free.x, y: sf.maxY - f.height)
        case .bottom: return NSPoint(x: free.x, y: sf.minY)
        case .none: return f.origin
        }
    }

    /// Where it sits when tucked away — everything off-screen but `M.sliver`.
    private func retractedOrigin() -> NSPoint {
        let sf = screenFrame(), f = window.frame
        let free = freeAxisOrigin()
        switch Store.shared.dock {
        case .right: return NSPoint(x: sf.maxX - M.sliver, y: free.y)
        case .left: return NSPoint(x: sf.minX - f.width + M.sliver, y: free.y)
        case .top: return NSPoint(x: free.x, y: sf.maxY - M.sliver)
        case .bottom: return NSPoint(x: free.x, y: sf.minY + M.sliver - f.height)
        case .none: return f.origin
        }
    }

    /// The current origin with both axes pulled back onto the screen, for the
    /// axis a dock edge does not control to use.
    ///
    /// Docking sets one coordinate and leaves the other where it was, which is
    /// right — sliding to the right edge should not also move the note up the
    /// screen. But "where it was" is only safe if it was somewhere visible, and
    /// after a retract it is not: a window tucked into the right edge is sitting
    /// at x = screen width − 3. Dock that to the top and the old code carried
    /// that x across verbatim, so the window slid up to the top edge while still
    /// three pixels from the right one and retracted into a 3×3 corner. Nothing
    /// was left to grab, and switching back to the right edge only fixed the
    /// axis that was already fine — the window came out at full width and three
    /// pixels tall, which is why it stayed lost.
    ///
    /// Clamped rather than reset to a default, so a note deliberately parked low
    /// on the screen stays low when it is docked to the side.
    private func freeAxisOrigin() -> NSPoint {
        let sf = screenFrame(), f = window.frame
        // `max` on the outside, so a window taller or wider than the screen
        // lands at the top-left corner rather than inverting the clamp and
        // hanging off the far side.
        return NSPoint(x: max(sf.minX, min(f.origin.x, sf.maxX - f.width)),
                       y: max(sf.minY, min(f.origin.y, sf.maxY - f.height)))
    }

    /// Slides the window off its docked edge, leaving only the sliver.
    ///
    /// Runs even when `isRetracted` is already set, which it often is: a docked
    /// note is retracted, slides out under the cursor, and gets dragged — and the
    /// flag never went false, because sliding out under the cursor is `expand`
    /// but being dragged is not. Returning early on the flag meant a window that
    /// had been dragged flush against its edge simply stayed there in full view.
    /// The flag says where the window is meant to be, so the way to honour it is
    /// to move the window, not to skip the move.
    func retract(animated: Bool) {
        guard Store.shared.dock != .none else { return }
        isRetracted = true
        // The drop shadow of an off-screen window spills back onto the desktop
        // as a grey band several times wider than the sliver itself — which is
        // what made a thin sliver still look like a fat bar.
        window.hasShadow = false
        var f = window.frame
        f.origin = retractedOrigin()
        guard f.origin != window.frame.origin else { return }
        setFrame(f, animated: animated)
    }

    func expand(animated: Bool) {
        guard Store.shared.dock != .none, isRetracted else { return }
        isRetracted = false
        window.hasShadow = true
        // A fresh slide-out starts the clock over, so the window can't reach the
        // hide threshold on the very next tick using a stale timestamp.
        pointerLeftAt = nil
        var f = window.frame
        f.origin = expandedOrigin()
        setFrame(f, animated: animated)
    }

    private func setFrame(_ f: NSRect, animated: Bool) {
        positioning(animated ? 0.45 : 0.1) {
            if animated {
                NSAnimationContext.runAnimationGroup { ctx in
                    ctx.duration = 0.18
                    ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
                    window.animator().setFrame(f, display: true)
                }
            } else {
                positioning(0.05) { window.setFrame(f, display: true) }
            }
        }
    }

    /// Marks `body` as this class moving the window, so the moves it posts are
    /// not mistaken for the user dragging it. `settle` is how long afterwards to
    /// keep ignoring them — long enough to cover an animation still in flight.
    private func positioning(_ settle: TimeInterval, _ body: () -> Void) {
        isPositioning = true
        body()
        DispatchQueue.main.asyncAfter(deadline: .now() + settle) {
            self.isPositioning = false
        }
    }

    /// Hot zone that triggers slide-out while retracted. Wider than the visible
    /// sliver — the hint is 3px, but the target it stands for is not.
    var dockHotZone: NSRect {
        let f = window.frame
        let sf = screenFrame()
        let s = M.dockHotZone
        switch Store.shared.dock {
        case .right: return NSRect(x: sf.maxX - s, y: f.minY, width: s + 4, height: f.height)
        case .left: return NSRect(x: sf.minX - 4, y: f.minY, width: s + 4, height: f.height)
        case .top: return NSRect(x: f.minX, y: sf.maxY - s, width: f.width, height: s + 4)
        case .bottom: return NSRect(x: f.minX, y: sf.minY - 4, width: f.width, height: s + 4)
        case .none: return .zero
        }
    }

    // MARK: Auto-hide

    /// Any keystroke anywhere in the note. Auto-hide refuses to fire for
    /// `M.typingGrace` after this, which is what keeps a half-written todo from
    /// being tucked out of sight mid-thought.
    private func noteTyping() { lastTypedAt = Date() }

    /// Polled from the app delegate. Slides a docked window away once the user
    /// has plainly finished with it: pointer off the window, no recent typing,
    /// and — if a field still holds the caret — a longer wait on top.
    ///
    /// The pointer test is done here against `NSEvent.mouseLocation` rather than
    /// from the tracking area, because the window slides out from *under* a
    /// stationary cursor: no `mouseEntered` is ever delivered, and trusting the
    /// tracking area would retract it again the instant it appeared.
    func tickAutoHide() {
        guard Store.shared.autoHide, Store.shared.dock != .none,
              !isRetracted, window.isVisible else { return }
        // A sheet or a pop-up menu means the user is mid-interaction even though
        // the pointer has wandered off the panel.
        guard window.attachedSheet == nil else { return }

        let now = Date()
        // A margin around the frame: the pointer drifting a few pixels past the
        // edge on its way to a checkbox is not "done with it".
        if window.frame.insetBy(dx: -12, dy: -12).contains(NSEvent.mouseLocation) {
            pointerLeftAt = nil
            return
        }
        let left = pointerLeftAt ?? now
        pointerLeftAt = left

        let speed = Store.shared.hideSpeed
        guard now.timeIntervalSince(lastTypedAt) >= speed.typingGrace else { return }
        let editing = window.firstResponder is NSTextView
        guard now.timeIntervalSince(left) >= (editing ? speed.leaveEditing : speed.leave) else {
            return
        }
        // Committing first means nothing half-typed is left only in a field
        // editor when the window goes away.
        if editing { window.makeFirstResponder(nil) }
        retract(animated: true)
    }

    // MARK: Menu

    /// The window-level preferences, as a standalone menu.
    ///
    /// Built once and used from two places — the status-bar icon's 「设置」
    /// submenu and the right-click menu on the note itself. Keeping it in one
    /// function is what stops the two from drifting: every option is reachable
    /// from the menu bar, which is where people look for settings, without the
    /// right-click menu losing anything.
    func settingsMenu() -> NSMenu {
        let menu = NSMenu()
        // Manual enabling: AppKit's automatic pass re-enables anything with a
        // live target, which would undo the greying-out of the speed options
        // while auto-hide is off.
        menu.autoenablesItems = false

        let top = add(menu, L("settings.floatOnTop"), #selector(toggleTop))
        top.state = Store.shared.floatOnTop ? .on : .off
        top.toolTip = L("settings.floatOnTop.tip")

        menu.addItem(.separator())
        menu.addItem(header(L("settings.appearance")))
        for t in Theme.allCases {
            let mi = add(menu, "  " + t.label, #selector(pickTheme(_:)))
            mi.representedObject = t.rawValue
            mi.state = (t == Store.shared.theme) ? .on : .off
            mi.toolTip = t.detail
        }

        menu.addItem(.separator())
        let auto = add(menu, L("settings.autoHide"), #selector(toggleAutoHide))
        auto.state = Store.shared.autoHide ? .on : .off
        auto.toolTip = L("settings.autoHide.tip")

        // Only meaningful when auto-hide is on, so it is disabled rather than
        // hidden — a setting that vanishes is harder to find than a greyed one.
        menu.addItem(header(L("settings.hideSpeed")))
        for sp in HideSpeed.allCases {
            let mi = add(menu, "  " + sp.label, #selector(pickHideSpeed(_:)))
            mi.representedObject = sp.rawValue
            mi.state = (sp == Store.shared.hideSpeed) ? .on : .off
            mi.toolTip = sp.detail
            mi.isEnabled = Store.shared.autoHide
        }

        return menu
    }

    /// A non-selectable small-caps label used to group items inside one menu.
    private func header(_ title: String) -> NSMenuItem {
        let mi = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        mi.attributedTitle = NSAttributedString(
            string: title,
            attributes: [.font: NSFont.systemFont(ofSize: 11, weight: .semibold),
                         .foregroundColor: NSColor.secondaryLabelColor])
        mi.isEnabled = false
        return mi
    }

    /// `id` is the tab that was right-clicked; nil means the strip background,
    /// which offers only the window-level items.
    func buildMenu(for id: UUID?) -> NSMenu {
        let menu = NSMenu()

        if let id, let note = Store.shared.note(id) {
            let colorItem = NSMenuItem(title: L("menu.color"), action: nil, keyEquivalent: "")
            let colorMenu = NSMenu()
            for c in NoteColor.allCases {
                let mi = NSMenuItem(title: c.label, action: #selector(pickColor(_:)),
                                    keyEquivalent: "")
                mi.target = self
                mi.representedObject = c.rawValue
                mi.state = (c == note.color) ? .on : .off
                mi.image = NSImage(size: NSSize(width: 12, height: 12), flipped: false) { rect in
                    c.accent.setFill()
                    NSBezierPath(ovalIn: rect.insetBy(dx: 1, dy: 1)).fill()
                    return true
                }
                colorMenu.addItem(mi)
            }
            colorItem.submenu = colorMenu
            menu.addItem(colorItem)

            add(menu, L("menu.rename"), #selector(renameNote))
            add(menu, note.tags.isEmpty
                    ? L("menu.tags")
                    : L("menu.tagsWith", note.tags.joined(separator: ", ")),
                #selector(editTags))
            add(menu, L("menu.clearDone"), #selector(clearDone))
            add(menu, L("menu.copyAsText"), #selector(copyAsText))
            menu.addItem(.separator())
        }

        add(menu, L("menu.newList"), #selector(addNote))
        menu.addItem(.separator())

        let setItem = NSMenuItem(title: L("menu.settings"), action: nil, keyEquivalent: "")
        setItem.submenu = settingsMenu()
        menu.addItem(setItem)

        // The one remaining way to dock from a menu. Which edge is not asked:
        // it is wherever the note already is. Choosing an edge by name was a
        // question with a better answer available — the window's own position —
        // and the picker that asked it is gone.
        let dockItem = add(menu, L(Store.shared.dock == .none ? "menu.tuckAway" : "menu.undock"),
                           #selector(toggleDock))
        // Nowhere to tuck into: every edge this window can reach is shared with
        // another display, where sliding out would walk the note onto it rather
        // than hide it. Disabled with the reason attached, so it does not look
        // like the command silently failed.
        if Store.shared.dock == .none, dockableEdges().isEmpty {
            dockItem.isEnabled = false
            dockItem.toolTip = L("menu.tuckAway.blocked.tip")
        }

        if let id, Store.shared.notes.count > 0 {
            menu.addItem(.separator())
            let del = add(menu, L("menu.deleteList"), #selector(deleteNote))
            del.representedObject = id
        }
        return menu
    }

    @discardableResult
    private func add(_ menu: NSMenu, _ title: String, _ action: Selector) -> NSMenuItem {
        let mi = NSMenuItem(title: title, action: action, keyEquivalent: "")
        mi.target = self
        menu.addItem(mi)
        return mi
    }

    @objc private func pickColor(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String,
              let c = NoteColor(rawValue: raw) else { return }
        commit { $0.color = c }
        refreshChrome()
    }

    @objc private func pickTheme(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String,
              let t = Theme(rawValue: raw) else { return }
        Store.shared.theme = t
        applyTheme()
    }

    @objc private func toggleAutoHide() {
        Store.shared.autoHide.toggle()
        pointerLeftAt = nil
        refreshChrome()
    }

    @objc private func pickHideSpeed(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String,
              let sp = HideSpeed(rawValue: raw) else { return }
        Store.shared.hideSpeed = sp
        // Restart the clock: an old "left at" timestamp measured against the new,
        // shorter delay would retract the window the instant the menu closes.
        pointerLeftAt = nil
        refreshChrome()
    }

    @objc private func renameNote() {
        guard let id = current?.id else { return }
        tabBar.tab(for: id)?.beginRename()
    }

    @objc private func addNote() { tabBarAddNote() }

    @objc private func toggleTop() {
        Store.shared.floatOnTop.toggle()
        window.applyFloatOnTop(Store.shared.floatOnTop)
    }

    @objc private func toggleDock() {
        if Store.shared.dock == .none { hideToEdge() } else { undock() }
    }

    @objc private func clearDone() {
        commit { $0.items.removeAll(where: \.done) }
        reload()
    }

    @objc private func copyAsText() {
        guard let note = current else { return }
        var lines = ["# \(note.title)"]
        for item in note.items {
            lines.append("- [\(item.done ? "x" : " ")] \(item.text)")
            if !item.nextText.trimmingCharacters(in: .whitespaces).isEmpty {
                lines.append("  ↳ \(item.nextText)")
            }
        }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(lines.joined(separator: "\n"), forType: .string)
    }

    @objc private func deleteNote(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? UUID,
              let note = Store.shared.note(id) else { return }
        let a = NSAlert()
        a.messageText = L("alert.deleteList.title", note.title)
        a.informativeText = LPlural("alert.deleteList.body", note.items.count)
        a.alertStyle = .warning
        a.addButton(withTitle: L("alert.delete"))
        a.addButton(withTitle: L("alert.cancel"))
        if a.runModal() == .alertFirstButtonReturn {
            Store.shared.remove(id)
        }
    }

    @objc private func editTags() {
        guard let note = current else { return }
        let a = NSAlert()
        a.messageText = L("alert.tags.title")
        a.informativeText = L("alert.tags.body")
        let tf = NSTextField(frame: NSRect(x: 0, y: 0, width: 240, height: 22))
        tf.stringValue = note.tags.joined(separator: ", ")
        a.accessoryView = tf
        a.addButton(withTitle: L("alert.ok"))
        a.addButton(withTitle: L("alert.cancel"))
        if a.runModal() == .alertFirstButtonReturn {
            let tags = tf.stringValue
                .split(whereSeparator: { $0 == "," || $0 == "，" })
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
            commit { $0.tags = tags }
            Store.shared.onChange?()
        }
    }

    // MARK: Window delegate

    func windowDidBecomeKey(_ notification: Notification) { updateAlpha() }
    func windowDidResignKey(_ notification: Notification) { updateAlpha() }
    func windowDidResize(_ notification: Notification) { layoutContents() }

    /// The window moved — by a drag, or by anything else.
    ///
    /// This, rather than the return of `performDrag`, is what tells us a drag
    /// happened. `performDrag` returns while the window is still at its starting
    /// point: comparing the frame across the call reported "did not move" for
    /// every real drag, so the docking code was never reached at all. Whatever it
    /// does internally, it does not wait for the window to come to rest.
    ///
    /// Coalesced with a short timer because a drag posts this continuously, and
    /// docking mid-gesture would fight the hand. The timer restarts on each
    /// move, so it fires once, shortly after the window finally stops.
    func windowDidMove(_ notification: Notification) {
        // Not while the window is being put somewhere by this class — docking,
        // retracting and sliding out all move it, and re-entering the docking
        // decision from inside one of those is how a loop starts.
        guard !isPositioning else { return }
        settleTimer?.invalidate()
        settleTimer = Timer.scheduledTimer(withTimeInterval: 0.15, repeats: false) {
            [weak self] _ in
            self?.settleTimer = nil
            self?.evaluateDock()
        }
    }

    /// Hands out one shared field editor with undo switched on.
    ///
    /// `NSTextField` does not support undo through its own machinery — editing
    /// happens in the window's field editor, and that editor arrives with
    /// `allowsUndo` off. Without this, ⌘Z inside a todo did nothing no matter
    /// what the menu said.
    ///
    /// AppKit calls this each time a *different* control takes focus, which is
    /// also the moment to drop the undo history: one editor is shared by every
    /// field in the window, so without the reset ⌘Z in one todo would undo an
    /// edit made in a different one.
    func windowWillReturnFieldEditor(_ sender: NSWindow, to client: Any?) -> Any? {
        let tv: NSTextView
        if let existing = fieldEditor {
            tv = existing
        } else {
            tv = NSTextView()
            tv.isFieldEditor = true
            tv.allowsUndo = true
            // Plain-text fields: smart quotes would turn a typed " into a curly
            // one, and the stored string is what gets copied out as text.
            tv.isAutomaticQuoteSubstitutionEnabled = false
            tv.isAutomaticDashSubstitutionEnabled = false
            fieldEditor = tv
        }

        let obj = client as AnyObject?
        if obj !== lastEditorClient {
            lastEditorClient = obj
            tv.undoManager?.removeAllActions()
        }
        return tv
    }
}

// MARK: - Tab bar delegate

extension BoardController: TabBarDelegate {
    func tabBarSelect(_ id: UUID) { select(id) }

    func tabBarToggleCollapse() { toggleCollapse() }

    func tabBarHide() { hideToEdge() }

    func tabBarShowMenu(for id: UUID?, from view: NSView) {
        buildMenu(for: id).popUp(positioning: nil,
                                 at: NSPoint(x: 0, y: view.bounds.maxY + 4),
                                 in: view)
    }

    func tabBarAddNote() {
        var n = Note()
        n.color = NoteColor.allCases[Store.shared.notes.count % NoteColor.allCases.count]
        Store.shared.add(n)
        Store.shared.selected = n.id
        if Store.shared.collapsed { toggleCollapse() }
        reload()
        window.makeKeyAndOrderFront(nil)
        tabBar.tab(for: n.id)?.beginRename()
    }

    func tabBarRename(_ id: UUID, to title: String) {
        Store.shared.update(id) { $0.title = title }
        refreshChrome()
        Store.shared.onChange?()
    }
}

// MARK: - Row delegate

extension BoardController: ItemRowDelegate {
    func rowToggle(_ id: UUID) {
        var promoted = false
        commit {
            guard let i = $0.items.firstIndex(where: { $0.id == id }) else { return }
            $0.items[i].done.toggle()
            // The sweep counts from here. Cleared again on unticking, so putting
            // something back on the list puts it back for good.
            $0.items[i].doneAt = $0.items[i].done ? Date() : nil
            // Ticking an item hands its next line to a fresh todo right below it.
            // This is the whole point of the field: come back after the job has
            // finished and the follow-up is already sitting there, unticked.
            if $0.items[i].done, let n = $0.items[i].next,
               !n.trimmingCharacters(in: .whitespaces).isEmpty {
                $0.items[i].next = nil
                $0.items.insert(ChecklistItem(text: n), at: i + 1)
                promoted = true
            }
        }
        if promoted {
            reload()
        } else {
            refreshChrome()
            layoutContents()
        }
        // Looked up again rather than held onto from before the rebuild: on the
        // promoted path the view that was ticked no longer exists, and the tick
        // is worth seeing on that path too — it is the one where something else
        // also appears, and the animation is what tells the two apart.
        guard let items = current?.items,
              let i = items.firstIndex(where: { $0.id == id }), rows.indices.contains(i)
        else { return }
        rows[i].playTick(to: items[i].done)
    }

    func rowTextChanged(_ id: UUID, _ text: String) {
        noteTyping()
        commit {
            if let i = $0.items.firstIndex(where: { $0.id == id }) {
                $0.items[i].text = text
            }
        }
        layoutContents()
    }

    func rowBeginNext(_ id: UUID) {
        noteTyping()
        commit {
            if let i = $0.items.firstIndex(where: { $0.id == id }), $0.items[i].next == nil {
                $0.items[i].next = ""
            }
        }
        reload()
        rows.first { $0.itemID == id }?.beginEditingNext()
    }

    func rowNextChanged(_ id: UUID, _ text: String) {
        noteTyping()
        commit {
            if let i = $0.items.firstIndex(where: { $0.id == id }) {
                $0.items[i].next = text
            }
        }
        layoutContents()
    }

    func rowEndNext(_ id: UUID) {
        var dropped = false
        commit {
            if let i = $0.items.firstIndex(where: { $0.id == id }),
               ($0.items[i].next ?? "").trimmingCharacters(in: .whitespaces).isEmpty,
               $0.items[i].next != nil {
                $0.items[i].next = nil
                dropped = true
            }
        }
        if dropped { reload() }
    }

    /// Esc pressed in the next line. Focus goes back to the item above it, and
    /// an untouched line is dropped — which is what makes a mis-hit Tab a
    /// non-event rather than something to clean up by hand.
    ///
    /// The drop has to happen before focus moves: `reload()` rebuilds the rows,
    /// so a `beginEditing` issued against the old row would target a view that
    /// is no longer in the window.
    func rowCancelNext(_ id: UUID) {
        var dropped = false
        commit {
            if let i = $0.items.firstIndex(where: { $0.id == id }),
               ($0.items[i].next ?? "").trimmingCharacters(in: .whitespaces).isEmpty,
               $0.items[i].next != nil {
                $0.items[i].next = nil
                dropped = true
            }
        }
        if dropped { reload() }
        rows.first { $0.itemID == id }?.beginEditing(atEnd: true)
    }

    func rowDelete(_ id: UUID) {
        commit { $0.items.removeAll { $0.id == id } }
        reload()
    }

    func rowInsertAfter(_ id: UUID) { insertRow(around: id, offset: 1) }

    func rowInsertBefore(_ id: UUID) { insertRow(around: id, offset: 0) }

    /// Return made a new row. `offset` is 0 to put it above the given row and 1
    /// to put it below; the caret moves into the new row either way, so from the
    /// keyboard the only difference is which side of it the existing text lands.
    private func insertRow(around id: UUID, offset: Int) {
        noteTyping()
        let new = ChecklistItem()
        commit {
            if let i = $0.items.firstIndex(where: { $0.id == id }) {
                $0.items.insert(new, at: i + offset)
            } else {
                // The row is gone from under us. Appending is the one placement
                // that is still meaningful when there is nothing to be relative
                // to, and it is what the caller expects: a new empty row exists.
                $0.items.append(new)
            }
        }
        reload()
        focus(rowAt: rows.firstIndex { $0.itemID == new.id } ?? 0, field: .main)
    }

    /// Backspace in an empty item. Almost always a stray Return a moment ago, so
    /// this reads as an undo of that Return rather than as a deletion: the row
    /// goes away and the caret lands at the end of the line above, exactly where
    /// it was before.
    ///
    /// The next line has to be empty too. An item can have a follow-up typed into
    /// its ↳ field while its own text is still blank, and removing the row would
    /// take that with it — silently, since the caret is nowhere near it.
    func rowDeleteEmpty(_ id: UUID) {
        noteTyping()
        guard let items = current?.items,
              let i = items.firstIndex(where: { $0.id == id }),
              items[i].text.isEmpty,
              items[i].nextText.isEmpty else { return }

        commit { $0.items.removeAll { $0.id == id } }
        reload()

        // Where ↑ would have gone from here, so the two keys agree.
        guard i > 0 else {
            if rows.isEmpty { window.makeFirstResponder(addField) } else { focus(rowAt: 0, field: .main) }
            return
        }
        let above = current?.items[i - 1]
        focus(rowAt: i - 1, field: (above?.hasNext ?? false) ? .next : .main)
    }

    /// ↑/↓ walks the whole list as one column: item → its next line → the next
    /// item, and off the bottom into the add-field.
    func rowMoveFocus(from id: UUID, in field: RowField, up: Bool) {
        guard let i = rows.firstIndex(where: { $0.itemID == id }) else { return }
        let items = current?.items ?? []

        if up {
            if field == .next { focus(rowAt: i, field: .main); return }
            guard i > 0 else { return }
            focus(rowAt: i - 1, field: items[i - 1].hasNext ? .next : .main)
        } else {
            if field == .main, i < items.count, items[i].hasNext {
                focus(rowAt: i, field: .next)
                return
            }
            if i + 1 < rows.count {
                focus(rowAt: i + 1, field: .main)
            } else {
                window.makeFirstResponder(addField)
            }
        }
    }

    // MARK: Reordering

    func rowDragBegan(_ id: UUID, grabOffset: CGFloat) {
        guard let i = rows.firstIndex(where: { $0.itemID == id }) else { return }
        noteTyping()
        // A caret left in the row being dragged would keep the field editor
        // attached to a view that is about to be replaced on drop.
        window.makeFirstResponder(nil)
        dragRow = rows[i]
        dragRow?.lifted = true
        dragFrom = i
        dragTo = i
        dragY = rows[i].frame.minY
        rowsHost.addSubview(rows[i], positioned: .above, relativeTo: nil)

        let t = Timer(timeInterval: 1.0 / 60, repeats: true) { [weak self] _ in
            self?.dragScrollTick()
        }
        // Common modes: the drag runs inside its own event loop, which leaves
        // the run loop in a tracking mode for the whole gesture. A default-mode
        // timer would not get a single turn until the button came back up.
        RunLoop.current.add(t, forMode: .common)
        dragScroll = t
    }

    /// Nudges the list when the held row is pressed up against the top or bottom
    /// of the visible area, and carries the row along with it so it stays under
    /// the hand — the pointer has not moved, so nothing else would move it.
    func dragScrollTick() {
        guard let d = dragRow else { return }
        let clip = scroll.contentView
        let vis = clip.documentVisibleRect
        // A band inside each edge rather than the edge itself: by the time the
        // row is fully past the boundary it cannot be seen, and steering
        // something invisible towards a slot is not a gesture anyone can aim.
        let band: CGFloat = 26
        var over: CGFloat = 0
        if d.frame.minY < vis.minY + band { over = d.frame.minY - (vis.minY + band) }
        else if d.frame.maxY > vis.maxY - band { over = d.frame.maxY - (vis.maxY - band) }
        guard over != 0 else { return }

        // Speed rises with how far past the band the row is pushed, so easing
        // into it creeps and shoving into it moves — and either way it stops the
        // moment the row is pulled back inside.
        let limit = max(0, rowsHost.frame.height - vis.height)
        let to = min(limit, max(0, vis.minY + max(-16, min(16, over * 0.4))))
        let moved = to - vis.minY
        guard moved != 0 else { return }
        clip.scroll(to: NSPoint(x: vis.minX, y: to))
        scroll.reflectScrolledClipView(clip)
        // The pointer has not moved, so in the document's own coordinates it
        // has, by exactly the distance just scrolled. Feeding that back through
        // the normal path keeps the row welded to the hand and re-picks a target
        // against the rows that have just come into view.
        rowDragMoved(to: dragY + moved)
    }

    func rowDragMoved(to y: CGFloat) {
        guard let d = dragRow else { return }
        noteTyping()
        dragY = y
        // The row follows the hand on every event, and without animation: it is
        // the thing being held. Interpolating it would leave it trailing the
        // cursor by the animation's whole duration, and leaving it to the
        // reflow below — which only runs when the target changes — pins it in
        // place until the next row boundary is crossed, so it lurches a row at
        // a time instead of moving.
        d.frame.origin.y = y

        // Where the row would land, measured against the list as it would look
        // with the gap closed up. Reading the rows' live frames instead would
        // feed the gap back into its own input — the gap shifts the frames,
        // the shifted frames pick a different target, and the list flickers
        // between two of them while the cursor stands still.
        //
        // Comparing middles rather than edges is what makes the swap happen
        // when the two rows are visibly half-overlapped.
        let mid = y + d.frame.height / 2
        var to = 0
        var top: CGFloat = 6
        for (slot, r) in rows.filter({ $0 !== d }).enumerated() {
            if mid > top + r.frame.height / 2 { to = slot + 1 }
            top += r.frame.height
        }
        guard to != dragTo else { return }
        dragTo = to
        // Only the rows standing aside animate, so the gap glides open instead
        // of teleporting. `layoutContents` re-asserts the dragged row's
        // position too, but to the value just set above — nothing to
        // interpolate, so it stays welded to the cursor.
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.12
            ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
            ctx.allowsImplicitAnimation = true
            layoutContents()
        }
    }

    func rowDragEnded() {
        // Before the guard: the timer has to stop even on the paths that find
        // no row to drop, or it keeps scrolling a list nobody is holding.
        dragScroll?.invalidate()
        dragScroll = nil
        guard let d = dragRow else { return }
        d.lifted = false
        let from = dragFrom, to = dragTo
        dragRow = nil
        guard from != to else {
            // Dropped where it started. Nothing to write; just let the row
            // settle back into its slot.
            settle()
            return
        }
        commit {
            guard $0.items.indices.contains(from) else { return }
            let item = $0.items.remove(at: from)
            $0.items.insert(item, at: min(to, $0.items.count))
        }
        // The row views are reordered to match the model rather than rebuilt.
        // A reload would replace all of them, and a brand-new view cannot
        // animate from where the old one was — the held row would snap into its
        // slot at the exact moment the drag deserves to look finished. `update`
        // does not fire `onChange`, so nothing rebuilds them behind this — but
        // if the array has shifted under us anyway, identity says so and a full
        // rebuild is always correct.
        guard rows.indices.contains(from), rows[from] === d else { return reload() }
        let moved = rows.remove(at: from)
        rows.insert(moved, at: min(to, rows.count))
        settle()
    }

    /// Lets go: the held row glides from wherever the hand left it into the slot
    /// the list has been holding open for it, which is the only thing that still
    /// needs to move — every other row was already shifted aside during the drag.
    private func settle() {
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.14
            ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
            ctx.allowsImplicitAnimation = true
            layoutContents()
        }
    }

    /// Moves the caret into a row and scrolls it into view. Always lands at the
    /// end of the text, the way a single-column list is expected to behave.
    private func focus(rowAt index: Int, field: RowField) {
        guard rows.indices.contains(index) else { return }
        let r = rows[index]
        switch field {
        case .main: r.beginEditing(atEnd: true)
        case .next: r.beginEditingNext(atEnd: true)
        }
        r.scrollToVisible(r.bounds)
    }

    /// Where every click on empty space ends up. Clicking below the last row
    /// reads as "I want another one" — the same thing ↓ from the last row
    /// already does — so it puts the caret in the add field rather than doing
    /// nothing at all.
    private func beginAdding() {
        guard current != nil, !Store.shared.collapsed else { return }
        noteTyping()
        window.makeFirstResponder(addField)
    }
}

// MARK: - Add-item field

extension BoardController: NSTextFieldDelegate {
    func controlTextDidChange(_ obj: Notification) { noteTyping() }

    func control(_ control: NSControl, textView: NSTextView,
                 doCommandBy selector: Selector) -> Bool {
        guard control === addField else { return false }
        switch selector {
        case #selector(NSResponder.insertNewline(_:)):
            noteTyping()
            let text = addField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { return true }
            commit { $0.items.append(ChecklistItem(text: text)) }
            addField.stringValue = ""
            reload()
            scroll.documentView?.scrollToEndOfDocument(nil)
            return true
        case #selector(NSResponder.moveUp(_:)):
            // Up out of the add-field lands on the last todo, closing the loop
            // that ↓ off the bottom of the list opened.
            guard !rows.isEmpty else { return true }
            let last = rows.count - 1
            focus(rowAt: last, field: (current?.items[last].hasNext ?? false) ? .next : .main)
            return true
        case #selector(NSResponder.cancelOperation(_:)):
            // Esc clears a half-typed new todo and drops focus. Nothing has been
            // committed yet at this point, so there is nothing to preserve.
            addField.stringValue = ""
            window.makeFirstResponder(nil)
            return true
        default:
            return false
        }
    }
}

