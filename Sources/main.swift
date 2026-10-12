import AppKit

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
// A regular app, with a Dock icon, so ⌘Tab can find the window once it is no
// longer pinned above everything else.
app.setActivationPolicy(.regular)
app.run()
