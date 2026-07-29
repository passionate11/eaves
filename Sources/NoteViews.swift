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
            // A raised chip carrying the note's colour. The tint has to be
            // stronger than it looks like it should be: the chip is nearly
            // white on the light themes, and a few percent of an accent mixed
            // into white comes back out as white.
            let path = NSBezierPath(roundedRect: pill, xRadius: 8, yRadius: 8)
            mixed(palette.activeTab, color.accent, 0.14).setFill()
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
        guard showsProgress, !progress.isEmpty else { return 0 }
        return ceil((progress as NSString)
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
    /// tabs are what a strip of tabs is expected to look like. The `4` matches
    /// the left inset in `layoutTabs`, so the last tab stops where the controls
    /// begin instead of tucking under them.
    private func grown(_ natural: [CGFloat], avail: CGFloat) -> [CGFloat] {
        var w = natural
        var slack = avail - 4 - w.reduce(0, +)
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
    /// Return with the caret at the very start of a row that already has text:
    /// the new empty row takes this one's place and this one moves down.
    func rowInsertBefore(_ id: UUID)
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
    /// A drag started in the row's left column. `grabOffset` is how far down the
    /// row the cursor was, so the row keeps the same grip while it moves.
    func rowDragBegan(_ id: UUID, grabOffset: CGFloat)
    /// `y` is the new top of the dragged row, in the list's coordinates.
    func rowDragMoved(to y: CGFloat)
    func rowDragEnded()
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

final class ItemRowView: FlippedView {
    static let font = NSFont.systemFont(ofSize: 13)
    static let nextFont = NSFont.systemFont(ofSize: 11)
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
    /// How far the next line is inset past the item's own text.
    static let nextIndent: CGFloat = 16

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
        didSet { renderTick(); needsDisplay = true }
    }

    private let check = NSButton()
    private let field = NSTextField()
    private let nextField = NSTextField()
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

    private var showsNext = false
    /// The formatted creation stamp, or nil for an item that has no recorded
    /// creation time. Kept formatted rather than as a `Date` because it is
    /// wanted on every redraw and the row already knows when it changes.
    private var stamp: String?
    private var hovered = false
    private var arrowY: CGFloat = 0
    private var tracking: NSTrackingArea?

    /// Set by the first Backspace on an empty row: the row is offering to remove
    /// itself, and says so, until the next keystroke either takes it up or calls
    /// it off. See `control(_:textView:doCommandBy:)`.
    private var armed = false
    private var armTimer: Timer?

    /// Set while this row is the one being dragged, so it draws lifted and the
    /// hover wash stays out of the way.
    var lifted = false { didSet { needsDisplay = true } }

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
    private static func boxImage(tick t: CGFloat, accent: NSColor, dark: Bool) -> NSImage {
        let side = boxSide
        return NSImage(size: NSSize(width: side, height: side), flipped: false) { _ in
            let box = NSRect(x: 0.5, y: 0.5, width: side - 1, height: side - 1)
            let path = NSBezierPath(roundedRect: box, xRadius: 5.5, yRadius: 5.5)

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
        let textW = textWidth(in: width, stamped: item.created != nil)
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
        text = item.text
        showsNext = item.hasNext
        stamp = item.created.map(Stamp.text(for:))

        // A refresh that lands mid-tick leaves the tick alone. The frame it is
        // on is more current than the model's end state, and the timer is on its
        // way to that end state regardless — snapping to it here is the one way
        // to make the animation visibly stutter.
        if tickTimer == nil { tick = item.done ? 1 : 0 }
        renderTick()

        if nextField.currentEditor() == nil {
            nextField.stringValue = item.nextText
            nextField.textColor = item.done ? .tertiaryLabelColor : .secondaryLabelColor
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
        let colour = tick >= 1 ? NSColor.tertiaryLabelColor
                               : NSColor.labelColor.withAlphaComponent(1 - 0.74 * tick)
        let s = NSMutableAttributedString(
            string: text, attributes: [.font: ItemRowView.font, .foregroundColor: colour])
        // Struck through only as far along as the tick has got. The line is the
        // part that means "done", so it is worth watching it get drawn — and
        // unticking runs the same thing backwards for free.
        let n = (text as NSString).length
        let cut = min(n, Int((CGFloat(n) * tick).rounded()))
        if cut > 0 {
            // Rounded out to whole characters: a range that stops halfway
            // through a composed sequence is not one an emoji survives.
            let r = (text as NSString)
                .rangeOfComposedCharacterSequences(for: NSRange(location: 0, length: cut))
            s.addAttributes([.strikethroughStyle: NSUnderlineStyle.single.rawValue,
                             .strikethroughColor: NSColor.tertiaryLabelColor], range: r)
        }
        field.attributedStringValue = s
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
        hovered = false; del.isHidden = !armed; needsDisplay = true
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
        field.currentEditor() != nil || nextField.currentEditor() != nil
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
        // The ✕ is small and already means exactly one thing.
        if hit === del { return hit }
        return self
    }

    /// Rows are reordered by dragging them up or down.
    override func mouseDown(with event: NSEvent) {
        window?.makeKeyAndOrderFront(nil)
        let start = event.locationInWindow
        let grab = convert(start, from: nil).y
        // What the press would have landed on, had the row not taken it.
        let under = superview.flatMap { super.hitTest($0.convert(start, from: nil)) }
        // Captured once rather than read per event: ending another row's edit
        // can drop an empty ↳ line, which rebuilds the list and takes this view
        // out of the hierarchy while the gesture is still running. The
        // controller follows the drag by item id and is unbothered, but a
        // `superview` read after that point would be nil and strand it.
        let host = superview
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
                delegate?.rowDragBegan(itemID, grabOffset: grab)
            }
            guard let host = host else { continue }
            delegate?.rowDragMoved(to: host.convert(p, from: nil).y - grab)
        }

        if dragging {
            NSCursor.pop()
            delegate?.rowDragEnded()
            return
        }
        deliver(click: event, to: under)
    }

    /// A press that never moved. The row swallowed it to find out whether a
    /// drag was coming, so what it was for has to happen here instead.
    private func deliver(click event: NSEvent, to view: NSView?) {
        if view === check {
            delegate?.rowToggle(itemID)
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
        disarm()
        if (obj.object as AnyObject?) === nextField {
            delegate?.rowNextChanged(itemID, nextField.stringValue)
        } else {
            delegate?.rowTextChanged(itemID, field.stringValue)
        }
    }

    func controlTextDidEndEditing(_ obj: Notification) {
        // Losing focus calls off a pending removal too — an armed row the caret
        // has left is just a red row nobody asked for.
        disarm()
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
            // the middle of it, on an empty row, or in the ↳ line. An empty row
            // is deliberately in that list: above and below are the same place
            // when there is nothing to push, so the simpler path wins.
            //
            // Either way the caret lands in the new row, which is what makes
            // the two cases feel like one key: an empty line appears where you
            // are, and only the text you had already typed moves.
            if !inNext, !textView.string.isEmpty,
               textView.selectedRange() == NSRange(location: 0, length: 0) {
                delegate?.rowInsertBefore(itemID)
            } else {
                delegate?.rowInsertAfter(itemID)
            }
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
            guard textView.string.isEmpty else { disarm(); return false }
            // The ↳ line goes on one press: it holds nothing, it was opened a
            // moment ago with Tab, and Esc already drops it the same way.
            if inNext {
                disarm()
                delegate?.rowCancelNext(itemID)
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

