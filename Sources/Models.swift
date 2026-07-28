import AppKit
import Foundation

// MARK: - Palette

enum NoteColor: String, Codable, CaseIterable {
    case red, orange, yellow, green, blue, purple, gray

    var label: String {
        switch self {
        case .red: return L("color.red")
        case .orange: return L("color.orange")
        case .yellow: return L("color.yellow")
        case .green: return L("color.green")
        case .blue: return L("color.blue")
        case .purple: return L("color.purple")
        case .gray: return L("color.gray")
        }
    }

    /// Accent used for the colour dot, the checkbox fill, the progress bar, and
    /// as a wash over the chrome — the tab strip and the footer are tinted a
    /// tenth of the way towards it. The card itself is left neutral: it is the
    /// ground the text sits on, and text wants a neutral ground.
    var accent: NSColor {
        switch self {
        case .red: return NSColor(srgbRed: 0.90, green: 0.29, blue: 0.31, alpha: 1)
        case .orange: return NSColor(srgbRed: 0.93, green: 0.55, blue: 0.20, alpha: 1)
        case .yellow: return NSColor(srgbRed: 0.85, green: 0.68, blue: 0.13, alpha: 1)
        case .green: return NSColor(srgbRed: 0.30, green: 0.68, blue: 0.36, alpha: 1)
        case .blue: return NSColor(srgbRed: 0.24, green: 0.53, blue: 0.90, alpha: 1)
        case .purple: return NSColor(srgbRed: 0.57, green: 0.40, blue: 0.87, alpha: 1)
        case .gray: return NSColor(srgbRed: 0.48, green: 0.52, blue: 0.56, alpha: 1)
        }
    }
}

// MARK: - Theme

/// How the window's surface is painted.
///
/// The default is deliberately *solid*. Frosted glass inverts contrast on macOS
/// — the system renders the focused window as glass and background windows as
/// opaque, so a translucent note is at its least readable exactly while you are
/// working in it. Translucency suits transient chrome; a checklist you stare at
/// for minutes is content, and content wants a stable surface. `.glass` is kept
/// for when the note is sitting over a quiet wallpaper and looks good doing it.
///
/// The two light and two dark variants are not padding: a warm paper tint and a
/// cool near-white read completely differently against a wallpaper, and which
/// one looks right depends on the desktop behind it, not on taste in the
/// abstract. Same on the dark side — `graphite` is a genuinely neutral mid-dark
/// panel and `ink` is a near-black with a blue cast, which is far enough apart
/// that the menu offers four dark-and-light choices rather than two plus two
/// near-duplicates.
enum Theme: String, Codable, CaseIterable {
    case auto, paper, sand, graphite, ink, glass

    var label: String {
        switch self {
        case .auto: return L("theme.auto")
        case .paper: return L("theme.paper")
        case .sand: return L("theme.sand")
        case .graphite: return L("theme.graphite")
        case .ink: return L("theme.ink")
        case .glass: return L("theme.glass")
        }
    }

    var detail: String {
        switch self {
        case .auto: return L("theme.auto.detail")
        case .paper: return L("theme.paper.detail")
        case .sand: return L("theme.sand.detail")
        case .graphite: return L("theme.graphite.detail")
        case .ink: return L("theme.ink.detail")
        case .glass: return L("theme.glass.detail")
        }
    }

    /// Resolves `.auto` against the current system appearance.
    func resolved(dark: Bool) -> Theme {
        self == .auto ? (dark ? .ink : .paper) : self
    }

    var isDark: Bool { self == .graphite || self == .ink }
    var isGlass: Bool { self == .glass }

    /// Forced appearance, so text and controls match the surface even when the
    /// system is in the other mode. `.auto` and `.glass` follow the system.
    var appearance: NSAppearance? {
        switch self {
        case .paper, .sand: return NSAppearance(named: .aqua)
        case .graphite, .ink: return NSAppearance(named: .darkAqua)
        case .auto, .glass: return nil
        }
    }
}

/// Blends `base` a fraction of the way towards `accent` while keeping its own
/// alpha. Preserving alpha is the point: the glass palettes are built entirely
/// out of translucent washes, and `blended(withFraction:of:)` on its own would
/// quietly drag them towards opaque.
func mixed(_ base: NSColor, _ accent: NSColor, _ f: CGFloat) -> NSColor {
    (base.blended(withFraction: f, of: accent) ?? base)
        .withAlphaComponent(base.alphaComponent)
}

/// Every surface colour in the window, resolved from the active theme once and
/// handed to the views. Keeping it in one place is what stopped the tab strip,
/// the card and the rows from each inventing their own greys.
struct Palette {
    var card: NSColor            // the note's surface, at the bottom of the gradient
    var cardTop: NSColor         // top of the surface gradient
    var header: NSColor          // the tab strip and the footer, a shade off the card
    var rim: NSColor             // outer hairline around the window
    var innerLight: NSColor      // highlight just inside the rim along the top edge
    var hairline: NSColor        // internal dividers
    var activeTab: NSColor       // the selected tab's chip
    var hover: NSColor           // row and tab hover wash
    var track: NSColor           // progress-bar groove
    var dark: Bool

    /// A copy with the chrome pulled towards a note's colour.
    ///
    /// Only the band behind the tabs and the footer move. Tinting the card as
    /// well would be the sticky-note register, and it is the wrong one here: a
    /// list you read for minutes at a time wants black on white, not black on
    /// pale purple. This way switching to a purple note visibly changes the
    /// window without changing the surface any text is on.
    func tinted(by accent: NSColor) -> Palette {
        var p = self
        // Less of it on the dark themes. The same fraction does not buy the same
        // amount of colour at both ends: mixed into a near-black band an accent
        // is a large part of what little luminance is there, so a tenth of the
        // way lands at around 0.4 saturation where on a near-white band it lands
        // at 0.06. Matching the numbers would make the dark side garish.
        p.header = mixed(header, accent, dark ? 0.07 : 0.10)
        return p
    }

    static func of(_ theme: Theme, systemDark: Bool) -> Palette {
        switch theme.resolved(dark: systemDark) {
        case .sand:
            // The classic paper-note look: warm, slightly yellow, and low
            // enough in luminance that black text on it is easier on the eye
            // than on pure white.
            return Palette(
                card: NSColor(srgbRed: 0.973, green: 0.955, blue: 0.909, alpha: 1),
                cardTop: NSColor(srgbRed: 0.999, green: 0.992, blue: 0.969, alpha: 1),
                header: NSColor(srgbRed: 0.953, green: 0.926, blue: 0.859, alpha: 1),
                rim: NSColor(srgbRed: 0.62, green: 0.55, blue: 0.42, alpha: 0.32),
                innerLight: NSColor(white: 1, alpha: 0.85),
                hairline: NSColor(srgbRed: 0.45, green: 0.38, blue: 0.24, alpha: 0.12),
                activeTab: NSColor(white: 1, alpha: 1),
                hover: NSColor(srgbRed: 0.45, green: 0.38, blue: 0.24, alpha: 0.07),
                track: NSColor(srgbRed: 0.45, green: 0.38, blue: 0.24, alpha: 0.14),
                dark: false)
        case .paper:
            // Near-white but not #fff, with a faintly cool cast — this is the
            // Things/Reminders register rather than the sticky-note one.
            return Palette(
                card: NSColor(srgbRed: 0.974, green: 0.976, blue: 0.982, alpha: 1),
                cardTop: NSColor(white: 1, alpha: 1),
                header: NSColor(srgbRed: 0.941, green: 0.945, blue: 0.957, alpha: 1),
                rim: NSColor(white: 0, alpha: 0.17),
                innerLight: NSColor(white: 1, alpha: 0.9),
                hairline: NSColor(white: 0, alpha: 0.08),
                activeTab: NSColor(white: 1, alpha: 1),
                hover: NSColor(white: 0, alpha: 0.045),
                track: NSColor(white: 0, alpha: 0.11),
                dark: false)
        case .ink:
            // Near-black, blue. A dark panel with a hue reads as designed; a
            // pure neutral one reads as "the lights are off". Pushed well below
            // `graphite` so the two are a choice rather than a pair.
            return Palette(
                card: NSColor(srgbRed: 0.063, green: 0.073, blue: 0.106, alpha: 1),
                cardTop: NSColor(srgbRed: 0.098, green: 0.114, blue: 0.161, alpha: 1),
                header: NSColor(srgbRed: 0.043, green: 0.051, blue: 0.078, alpha: 1),
                rim: NSColor(white: 1, alpha: 0.15),
                innerLight: NSColor(white: 1, alpha: 0.11),
                hairline: NSColor(white: 1, alpha: 0.08),
                activeTab: NSColor(srgbRed: 0.196, green: 0.224, blue: 0.302, alpha: 1),
                hover: NSColor(white: 1, alpha: 0.055),
                track: NSColor(white: 1, alpha: 0.10),
                dark: true)
        case .graphite:
            // The neutral dark: a mid-dark panel with no cast at all, for a
            // desktop busy enough that a tinted one would fight it.
            return Palette(
                card: NSColor(srgbRed: 0.169, green: 0.167, blue: 0.163, alpha: 1),
                cardTop: NSColor(srgbRed: 0.216, green: 0.213, blue: 0.208, alpha: 1),
                header: NSColor(srgbRed: 0.129, green: 0.127, blue: 0.124, alpha: 1),
                rim: NSColor(white: 1, alpha: 0.17),
                innerLight: NSColor(white: 1, alpha: 0.10),
                hairline: NSColor(white: 1, alpha: 0.09),
                activeTab: NSColor(white: 1, alpha: 0.16),
                hover: NSColor(white: 1, alpha: 0.06),
                track: NSColor(white: 1, alpha: 0.11),
                dark: true)
        default:   // .glass — painted over live vibrancy, so everything is alpha
            return systemDark
                ? Palette(card: NSColor(white: 0.11, alpha: 0.72),
                          cardTop: NSColor(white: 0.20, alpha: 0.68),
                          header: NSColor(white: 0.04, alpha: 0.40),
                          rim: NSColor(white: 1, alpha: 0.15),
                          innerLight: NSColor(white: 1, alpha: 0.16),
                          hairline: NSColor(white: 1, alpha: 0.09),
                          activeTab: NSColor(white: 1, alpha: 0.20),
                          hover: NSColor(white: 1, alpha: 0.06),
                          track: NSColor(white: 1, alpha: 0.11),
                          dark: true)
                // The chrome band is a *white* wash rather than a grey one. A
                // grey wash over live blur does not read as recessed the way an
                // opaque one does — with the wallpaper still showing through it
                // just reads as a smudge, which is what made this the one theme
                // that looked dirty rather than frosted.
                : Palette(card: NSColor(white: 1, alpha: 0.80),
                          cardTop: NSColor(white: 1, alpha: 0.90),
                          header: NSColor(white: 1, alpha: 0.30),
                          rim: NSColor(white: 1, alpha: 0.80),
                          innerLight: NSColor(white: 1, alpha: 0.9),
                          hairline: NSColor(white: 0, alpha: 0.06),
                          activeTab: NSColor(white: 1, alpha: 0.95),
                          hover: NSColor(white: 0, alpha: 0.04),
                          track: NSColor(white: 0, alpha: 0.08),
                          dark: false)
        }
    }
}

struct ChecklistItem: Codable, Identifiable, Equatable {
    var id: UUID = UUID()
    var text: String = ""
    var done: Bool = false
    /// "What to do once this finishes", shown as an indented line under the item.
    /// Optional rather than defaulting to "" because the synthesized decoder only
    /// tolerates a missing key on an Optional — a notes.json written before this
    /// field existed has to keep decoding.
    ///
    /// `nil` means no line at all; `""` means the line exists but is still being
    /// typed, which is what makes Tab able to open an empty one.
    var next: String? = nil
    /// When the item was made, shown small at the right-hand end of its row.
    ///
    /// Optional for the same reason `next` is, and the nil case is meaningful
    /// rather than merely tolerated: the synthesized decoder ignores this
    /// default and leaves the field nil for a notes.json written before it
    /// existed, which is right — those items have no recorded creation time,
    /// and a stamp reading "the day you updated the app" would be a fabrication
    /// sitting in the UI looking like a fact. They show no stamp at all.
    var created: Date? = Date()

    var nextText: String { next ?? "" }
    var hasNext: Bool { next != nil }
}

/// Which screen edge a note is docked to. `.none` means free-floating.
enum DockEdge: String, Codable, CaseIterable {
    case none, left, right, top, bottom

    var label: String {
        switch self {
        case .none: return L("edge.none")
        case .left: return L("edge.left")
        case .right: return L("edge.right")
        case .top: return L("edge.top")
        case .bottom: return L("edge.bottom")
        }
    }

    /// The SF Symbol for "tuck away in this direction".
    var arrowSymbol: String {
        switch self {
        case .left: return "arrow.left.to.line"
        case .right, .none: return "arrow.right.to.line"
        case .top: return "arrow.up.to.line"
        case .bottom: return "arrow.down.to.line"
        }
    }

    /// True when retracting slides the window sideways rather than up or down.
    var isHorizontal: Bool { self == .left || self == .right }
}

// MARK: - Auto-hide speed

/// How eagerly a docked window tucks itself away.
///
/// Three timings rather than one, because "finished with it" means different
/// things depending on what the user was doing, and they have to move together
/// — a short leave-delay with a long typing grace just feels broken. The grace
/// period is the one that actually protects a half-written todo, so it stays
/// the largest of the three at every speed.
enum HideSpeed: String, Codable, CaseIterable {
    case fast, normal, slow

    var label: String {
        switch self {
        case .fast: return L("speed.fast")
        case .normal: return L("speed.normal")
        case .slow: return L("speed.slow")
        }
    }

    var detail: String {
        switch self {
        case .fast: return L("speed.fast.detail")
        case .normal: return L("speed.normal.detail")
        case .slow: return L("speed.slow.detail")
        }
    }

    /// Pointer has been off the window this long → slide it away.
    var leave: TimeInterval {
        switch self {
        case .fast: return 0.35
        case .normal: return 0.8
        case .slow: return 1.5
        }
    }

    /// Same, but a text field still holds the caret: wait longer.
    var leaveEditing: TimeInterval {
        switch self {
        case .fast: return 0.8
        case .normal: return 1.6
        case .slow: return 3.0
        }
    }

    /// No auto-hide at all until this long after the last keystroke. This is the
    /// guard against tucking a half-written todo out of sight, so it is never
    /// short enough to fire inside a normal typing pause.
    var typingGrace: TimeInterval {
        switch self {
        case .fast: return 1.2
        case .normal: return 2.2
        case .slow: return 4.0
        }
    }
}

struct Note: Codable, Identifiable, Equatable {
    var id: UUID = UUID()
    var title: String = L("note.untitled")
    var items: [ChecklistItem] = []
    var color: NoteColor = .blue
    var tags: [String] = []

    // Legacy per-note window geometry. Notes are tabs of one shared window now,
    // so these are only read once, to migrate an old notes.json into a sensible
    // starting frame for that window. New code must not rely on them.
    var x: CGFloat = 200
    var y: CGFloat = 400
    var width: CGFloat = 280
    var height: CGFloat = 320

    var collapsed: Bool = false
    var dock: DockEdge = .none
    var floatOnTop: Bool = true

    var frame: CGRect {
        get { CGRect(x: x, y: y, width: width, height: height) }
        set {
            x = newValue.origin.x
            y = newValue.origin.y
            width = newValue.size.width
            height = newValue.size.height
        }
    }

    var doneCount: Int { items.filter(\.done).count }
    var progressText: String { "\(doneCount)/\(items.count)" }
}

// MARK: - Store

/// Single source of truth. Owns the note array and debounced JSON persistence.
final class Store {
    static let shared = Store()

    private(set) var notes: [Note] = []
    private var saveTimer: Timer?

    /// Tags that are currently hidden via the menu-bar filter.
    private(set) var mutedTags: Set<String> = []

    var onChange: (() -> Void)?

    private let dir: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory,
                                            in: .userDomainMask)[0]
        return base.appendingPathComponent("Eaves", isDirectory: true)
    }()

    private var fileURL: URL { dir.appendingPathComponent("notes.json") }
    private var settingsURL: URL { dir.appendingPathComponent("settings.json") }

    private struct Settings: Codable {
        var mutedTags: [String] = []
        var allHidden: Bool = false
        // Geometry and state of the one shared window. Optional so that a
        // settings.json written before the tabbed rewrite triggers migration.
        var winX: CGFloat? = nil
        var winY: CGFloat? = nil
        var winW: CGFloat? = nil
        var winH: CGFloat? = nil
        var collapsed: Bool = false
        var dock: DockEdge = .none
        var floatOnTop: Bool = true
        var autoHide: Bool = true
        /// Optional, not defaulted: the synthesized decoder only tolerates a
        /// missing key on an Optional, and a settings.json written before this
        /// field existed must keep decoding rather than reset every setting.
        var hideSpeed: HideSpeed? = nil
        var theme: Theme = .auto
        var selected: UUID? = nil
    }

    private var s = Settings()

    var allHidden: Bool {
        get { s.allHidden }
        set { s.allHidden = newValue; scheduleSave() }
    }

    var collapsed: Bool {
        get { s.collapsed }
        set { s.collapsed = newValue; scheduleSave() }
    }

    var dock: DockEdge {
        get { s.dock }
        set { s.dock = newValue; scheduleSave() }
    }

    var floatOnTop: Bool {
        get { s.floatOnTop }
        set { s.floatOnTop = newValue; scheduleSave() }
    }

    /// Whether a docked window tucks itself away once the user stops working in
    /// it. Only ever applies while docked — a free-floating note never moves on
    /// its own.
    var autoHide: Bool {
        get { s.autoHide }
        set { s.autoHide = newValue; scheduleSave() }
    }

    /// How long auto-hide waits before tucking the window away.
    var hideSpeed: HideSpeed {
        get { s.hideSpeed ?? .fast }
        set { s.hideSpeed = newValue; scheduleSave() }
    }

    var theme: Theme {
        get { s.theme }
        set { s.theme = newValue; scheduleSave() }
    }

    /// Which tab is showing. Falls back to the first visible note.
    var selected: UUID? {
        get {
            if let id = s.selected, notes.contains(where: { $0.id == id }) { return id }
            return visibleNotes.first?.id ?? notes.first?.id
        }
        set { s.selected = newValue; scheduleSave() }
    }

    /// Geometry of the shared window. When settings.json predates the tabbed
    /// rewrite, the first note's old frame is reused so the window comes back
    /// roughly where the user last left their notes.
    var windowFrame: CGRect {
        get {
            let sf = (NSScreen.main ?? NSScreen.screens[0]).visibleFrame
            if let x = s.winX, let y = s.winY, let w = s.winW, let h = s.winH {
                return CGRect(x: x, y: y, width: w, height: h)
            }
            let h: CGFloat = 380
            // 360 is the width at which three CJK tab titles plus their progress
            // counts fit without truncation — narrower and the strip starts
            // eating the names it exists to show.
            let w: CGFloat = 360
            if let n = notes.first {
                return CGRect(x: min(n.x, sf.maxX - w), y: min(n.y + n.height - h, sf.maxY - h),
                              width: max(w, n.width), height: h)
            }
            return CGRect(x: sf.maxX - w - 20, y: sf.maxY - h - 40, width: w, height: h)
        }
        set {
            s.winX = newValue.origin.x
            s.winY = newValue.origin.y
            s.winW = newValue.size.width
            s.winH = newValue.size.height
            scheduleSave()
        }
    }

    private init() {
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        load()
    }

    // MARK: Load / save

    private func load() {
        if let data = try? Data(contentsOf: fileURL),
           let decoded = try? JSONDecoder().decode([Note].self, from: data) {
            notes = decoded
        }
        if let data = try? Data(contentsOf: settingsURL),
           let decoded = try? JSONDecoder().decode(Settings.self, from: data) {
            s = decoded
            mutedTags = Set(decoded.mutedTags)
        }
    }

    /// Coalesces bursts of edits (typing, dragging) into one write.
    func scheduleSave() {
        saveTimer?.invalidate()
        saveTimer = Timer.scheduledTimer(withTimeInterval: 0.6, repeats: false) { [weak self] _ in
            self?.saveNow()
        }
    }

    func saveNow() {
        saveTimer?.invalidate()
        saveTimer = nil
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? encoder.encode(notes) {
            try? data.write(to: fileURL, options: .atomic)
        }
        s.mutedTags = Array(mutedTags).sorted()
        if let data = try? encoder.encode(s) {
            try? data.write(to: settingsURL, options: .atomic)
        }
    }

    // MARK: Mutation

    func note(_ id: UUID) -> Note? { notes.first { $0.id == id } }

    @discardableResult
    func add(_ note: Note) -> Note {
        notes.append(note)
        scheduleSave()
        onChange?()
        return note
    }

    /// In-place edit. Does not fire `onChange` — the window owning the note is
    /// already showing the new value, and rebuilding it would kill the field editor.
    func update(_ id: UUID, _ mutate: (inout Note) -> Void) {
        guard let idx = notes.firstIndex(where: { $0.id == id }) else { return }
        mutate(&notes[idx])
        scheduleSave()
    }

    func remove(_ id: UUID) {
        notes.removeAll { $0.id == id }
        scheduleSave()
        onChange?()
    }

    var allTags: [String] {
        Array(Set(notes.flatMap(\.tags))).sorted()
    }

    /// Notes that survive the menu-bar tag filter — i.e. the notes that get a tab.
    var visibleNotes: [Note] {
        notes.filter { !isMuted($0) }
    }

    func isMuted(_ note: Note) -> Bool {
        !note.tags.isEmpty && note.tags.allSatisfy { mutedTags.contains($0) }
    }

    func toggleMute(_ tag: String) {
        if mutedTags.contains(tag) { mutedTags.remove(tag) } else { mutedTags.insert(tag) }
        scheduleSave()
        onChange?()
    }
}
