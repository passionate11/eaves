import AppKit
import Foundation

// MARK: - Palette

enum NoteColor: String, Codable, CaseIterable {
    case red, orange, yellow, green, blue, purple, gray

    var label: String {
        switch self {
        case .red: return "红"
        case .orange: return "橙"
        case .yellow: return "黄"
        case .green: return "绿"
        case .blue: return "蓝"
        case .purple: return "紫"
        case .gray: return "灰"
        }
    }

    /// Accent used for the color dot, the checkbox fill and the progress bar.
    /// It is the *only* place a note's colour shows: the window itself stays
    /// neutral so switching tabs doesn't repaint everything.
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
/// abstract. Same for neutral vs blue-black on the dark side.
enum Theme: String, Codable, CaseIterable {
    case auto, paper, sand, graphite, ink, glass

    var label: String {
        switch self {
        case .auto: return "跟随系统"
        case .paper: return "纸白"
        case .sand: return "米黄"
        case .graphite: return "石墨"
        case .ink: return "午夜蓝"
        case .glass: return "毛玻璃"
        }
    }

    var detail: String {
        switch self {
        case .auto: return "浅色/深色自动切换（不透明）"
        case .paper: return "冷白纸面，始终浅色"
        case .sand: return "暖米色便签纸，始终浅色"
        case .graphite: return "中性深灰，始终深色"
        case .ink: return "偏蓝的深色，始终深色"
        case .glass: return "半透明毛玻璃，桌面透出来"
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

/// Every surface colour in the window, resolved from the active theme once and
/// handed to the views. Keeping it in one place is what stopped the tab strip,
/// the card and the rows from each inventing their own greys.
struct Palette {
    var card: NSColor            // the note's surface
    var cardTop: NSColor         // top of the surface gradient
    var header: NSColor          // the tab strip, drawn a shade off the card
    var rim: NSColor             // outer hairline around the window
    var hairline: NSColor        // internal dividers
    var activeTab: NSColor       // the selected tab's chip
    var hover: NSColor           // row and tab hover wash
    var track: NSColor           // progress-bar groove
    var dark: Bool

    static func of(_ theme: Theme, systemDark: Bool) -> Palette {
        switch theme.resolved(dark: systemDark) {
        case .sand:
            // The classic paper-note look: warm, slightly yellow, and low
            // enough in luminance that black text on it is easier on the eye
            // than on pure white.
            return Palette(
                card: NSColor(srgbRed: 0.988, green: 0.973, blue: 0.937, alpha: 1),
                cardTop: NSColor(srgbRed: 0.996, green: 0.988, blue: 0.961, alpha: 1),
                header: NSColor(srgbRed: 0.976, green: 0.953, blue: 0.902, alpha: 1),
                rim: NSColor(srgbRed: 0.62, green: 0.55, blue: 0.42, alpha: 0.28),
                hairline: NSColor(srgbRed: 0.45, green: 0.38, blue: 0.24, alpha: 0.12),
                activeTab: NSColor(white: 1, alpha: 1),
                hover: NSColor(srgbRed: 0.45, green: 0.38, blue: 0.24, alpha: 0.07),
                track: NSColor(srgbRed: 0.45, green: 0.38, blue: 0.24, alpha: 0.12),
                dark: false)
        case .paper:
            // Near-white but not #fff, with a faintly cool cast — this is the
            // Things/Reminders register rather than the sticky-note one.
            return Palette(
                card: NSColor(srgbRed: 0.992, green: 0.992, blue: 0.996, alpha: 1),
                cardTop: NSColor(white: 1, alpha: 1),
                header: NSColor(srgbRed: 0.965, green: 0.969, blue: 0.976, alpha: 1),
                rim: NSColor(white: 0, alpha: 0.15),
                hairline: NSColor(white: 0, alpha: 0.08),
                activeTab: NSColor(white: 1, alpha: 1),
                hover: NSColor(white: 0, alpha: 0.045),
                track: NSColor(white: 0, alpha: 0.09),
                dark: false)
        case .ink:
            // Blue-black. A dark panel with a hue reads as designed; a pure
            // neutral one reads as "the lights are off".
            return Palette(
                card: NSColor(srgbRed: 0.106, green: 0.118, blue: 0.149, alpha: 1),
                cardTop: NSColor(srgbRed: 0.129, green: 0.145, blue: 0.184, alpha: 1),
                header: NSColor(srgbRed: 0.086, green: 0.098, blue: 0.125, alpha: 1),
                rim: NSColor(white: 1, alpha: 0.14),
                hairline: NSColor(white: 1, alpha: 0.08),
                activeTab: NSColor(srgbRed: 0.216, green: 0.243, blue: 0.310, alpha: 1),
                hover: NSColor(white: 1, alpha: 0.055),
                track: NSColor(white: 1, alpha: 0.10),
                dark: true)
        case .graphite:
            return Palette(
                card: NSColor(srgbRed: 0.137, green: 0.141, blue: 0.153, alpha: 1),
                cardTop: NSColor(srgbRed: 0.169, green: 0.173, blue: 0.188, alpha: 1),
                header: NSColor(srgbRed: 0.110, green: 0.114, blue: 0.125, alpha: 1),
                rim: NSColor(white: 1, alpha: 0.16),
                hairline: NSColor(white: 1, alpha: 0.09),
                activeTab: NSColor(white: 1, alpha: 0.15),
                hover: NSColor(white: 1, alpha: 0.06),
                track: NSColor(white: 1, alpha: 0.11),
                dark: true)
        default:   // .glass — painted over live vibrancy, so everything is alpha
            return systemDark
                ? Palette(card: NSColor(white: 0.13, alpha: 0.70),
                          cardTop: NSColor(white: 0.19, alpha: 0.66),
                          header: NSColor(white: 0.08, alpha: 0.35),
                          rim: NSColor(white: 1, alpha: 0.15),
                          hairline: NSColor(white: 1, alpha: 0.09),
                          activeTab: NSColor(white: 1, alpha: 0.20),
                          hover: NSColor(white: 1, alpha: 0.06),
                          track: NSColor(white: 1, alpha: 0.11),
                          dark: true)
                : Palette(card: NSColor(white: 1, alpha: 0.72),
                          cardTop: NSColor(white: 1, alpha: 0.84),
                          header: NSColor(white: 0.55, alpha: 0.13),
                          rim: NSColor(white: 1, alpha: 0.80),
                          hairline: NSColor(white: 0, alpha: 0.06),
                          activeTab: NSColor(white: 1, alpha: 0.95),
                          hover: NSColor(white: 0, alpha: 0.04),
                          track: NSColor(white: 0, alpha: 0.07),
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

    var nextText: String { next ?? "" }
    var hasNext: Bool { next != nil }
}

/// Which screen edge a note is docked to. `.none` means free-floating.
enum DockEdge: String, Codable, CaseIterable {
    case none, left, right, top, bottom

    var label: String {
        switch self {
        case .none: return "不吸边"
        case .left: return "左边"
        case .right: return "右边"
        case .top: return "上边"
        case .bottom: return "下边"
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
        case .fast: return "快"
        case .normal: return "标准"
        case .slow: return "慢"
        }
    }

    var detail: String {
        switch self {
        case .fast: return "鼠标一离开就收（约 0.4 秒）"
        case .normal: return "离开后稍等一下再收（约 0.8 秒）"
        case .slow: return "留足反悔时间（约 1.5 秒）"
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
    var title: String = "新便签"
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
        return base.appendingPathComponent("DeskNote", isDirectory: true)
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
