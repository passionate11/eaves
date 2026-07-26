#!/usr/bin/env swift
// Prints each screen's frame and backing scale, so Tools/shoot.sh can place the
// window on a Retina display before capturing. A 1x screenshot of a 380pt
// window is 380px wide, which looks soft in a README on any modern screen.
import AppKit

for (i, s) in NSScreen.screens.enumerated() {
    let f = s.frame
    print("\(i) x=\(Int(f.minX)) y=\(Int(f.minY)) w=\(Int(f.width)) h=\(Int(f.height)) scale=\(s.backingScaleFactor)")
}
