import AppKit

// MARK: - Metrics

enum M {
    /// Height of the tab strip. When collapsed this is the whole window.
    static let tab: CGFloat = 34
    static let footer: CGFloat = 34
    static let pad: CGFloat = 14
    static let rowMin: CGFloat = 32
    /// Row padding above and below the text.
    static let rowPad: CGFloat = 7
    static let corner: CGFloat = 16
    /// Thickness of the accent progress line at the bottom edge of the tab strip.
    static let progressBar: CGFloat = 2
    /// Visible width of the docked, retracted window. Deliberately tiny — it is
    /// a hint that something is parked there, not a UI element. The hot zone
    /// that slides it back out is widened separately, so a 3px sliver is still
    /// easy to hit.
    static let sliver: CGFloat = 3
    /// Thickness of the invisible band at the screen edge that slides a docked
    /// window back out. Wider than the sliver on purpose: the visual hint can be
    /// discreet as long as the target is forgiving.
    static let dockHotZone: CGFloat = 10
    /// How close to a screen edge a drag must end to snap.
    static let snapDistance: CGFloat = 26
    static let fadeAlpha: CGFloat = 0.96
    /// A tab never shrinks below this; past that point the strip clips.
    static let tabMinWidth: CGFloat = 46
    /// A tab never grows past this, however much room the strip has. Tabs do
    /// take up the slack when there is some — a lone tab as a small chip in an
    /// otherwise empty strip looks lost — but a single note in a wide window
    /// should still read as a tab, not as a title bar.
    static let tabMaxWidth: CGFloat = 128
    /// Titles stop growing here so one long name can't crowd out the rest.
    static let tabTitleMax: CGFloat = 96
    /// Titles shrink to this before the `3/7` suffix is given up.
    static let tabTitleMin: CGFloat = 26
    /// Width of the invisible drag strips along the left, right and bottom edges.
    static let grab: CGFloat = 6
    /// Side of the square grab zones in the two bottom corners.
    static let grabCorner: CGFloat = 14
    static let minWidth: CGFloat = 220
    static let minHeight: CGFloat = tab + footer + 40
}

// MARK: - Panel

/// Borderless floating panel. Two behaviours matter here:
///
/// 1. `canJoinAllSpaces` + `fullScreenAuxiliary` is what puts the note above
///    *other apps'* fullscreen windows — the thing Apple's Stickies cannot do.
///    Window level alone is not enough; the collection behaviour is the lever.
/// 2. `constrainFrameRect` is overridden so AppKit stops yanking the window
///    back on-screen, which would make edge-docking impossible.
final class NoteWindow: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect {
        frameRect
    }

    init(frame: NSRect) {
        super.init(contentRect: frame,
                   styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered,
                   defer: false)
        isFloatingPanel = true
        hidesOnDeactivate = false
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        isMovableByWindowBackground = false
        collectionBehavior = [.canJoinAllSpaces, .stationary,
                              .fullScreenAuxiliary, .ignoresCycle]
        animationBehavior = .none
    }

    func applyFloatOnTop(_ on: Bool) {
        level = on ? .floating : .normal
    }
}

// MARK: - Small helpers

/// NSView whose `isFlipped` is true, so manual layout runs top-down.
class FlippedView: NSView {
    override var isFlipped: Bool { true }
}

/// A resizable rounded-rectangle image for use as an `NSVisualEffectView` mask.
///
/// `layer.cornerRadius` does *not* round a `.behindWindow` vibrancy view: the
/// blur is composited by the window server outside the layer tree, so the
/// corners stay square no matter what the layer says. Handing AppKit a mask
/// image is the only thing that actually clips it.
func roundedMaskImage(radius: CGFloat) -> NSImage {
    let d = radius * 2 + 1
    let img = NSImage(size: NSSize(width: d, height: d), flipped: false) { rect in
        NSColor.black.setFill()
        NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill()
        return true
    }
    img.capInsets = NSEdgeInsets(top: radius, left: radius, bottom: radius, right: radius)
    img.resizingMode = .stretch
    return img
}

extension NSShadow {
    /// A plain drop shadow. `dy` is in the drawing view's own direction, so a
    /// negative value falls downward inside a flipped view.
    static func drop(radius: CGFloat, alpha: CGFloat, dy: CGFloat) -> NSShadow {
        let s = NSShadow()
        s.shadowBlurRadius = radius
        s.shadowOffset = NSSize(width: 0, height: dy)
        s.shadowColor = NSColor.black.withAlphaComponent(alpha)
        return s
    }
}

func symbolButton(_ name: String, size: CGFloat = 11,
                  target: AnyObject?, action: Selector) -> NSButton {
    let b = NSButton()
    b.isBordered = false
    b.bezelStyle = .regularSquare
    b.imagePosition = .imageOnly
    let cfg = NSImage.SymbolConfiguration(pointSize: size, weight: .semibold)
    b.image = NSImage(systemSymbolName: name, accessibilityDescription: nil)?
        .withSymbolConfiguration(cfg)
    b.target = target
    b.action = action
    b.setButtonType(.momentaryChange)
    return b
}

func plainField(_ text: String, size: CGFloat, bold: Bool = false) -> NSTextField {
    let f = NSTextField(string: text)
    f.isBordered = false
    f.drawsBackground = false
    f.focusRingType = .none
    f.font = bold ? .systemFont(ofSize: size, weight: .semibold)
                  : .systemFont(ofSize: size)
    f.lineBreakMode = .byTruncatingTail
    f.cell?.usesSingleLineMode = true
    f.cell?.wraps = false
    f.cell?.isScrollable = true
    return f
}
