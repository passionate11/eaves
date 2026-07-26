#!/usr/bin/env swift
// Prints "<windowID> <width>x<height>" for each on-screen window owned by the
// named application. Used by Tools/shoot.sh to capture DeskNote by window ID
// rather than by screen region, so README screenshots come out clean no matter
// what else happens to be on the desktop.
import CoreGraphics
import Foundation

let target = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "DeskNote"
guard let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly,
                                             .excludeDesktopElements], kCGNullWindowID)
        as? [[String: Any]] else { exit(1) }

for w in list {
    guard let owner = w[kCGWindowOwnerName as String] as? String, owner == target,
          let id = w[kCGWindowNumber as String] as? Int,
          let b = w[kCGWindowBounds as String] as? [String: Any],
          let width = b["Width"] as? Double, let height = b["Height"] as? Double
    else { continue }
    // Skip the status-bar item's own tiny window.
    if width < 60 || height < 60 { continue }
    print("\(id) \(Int(width))x\(Int(height))")
}
