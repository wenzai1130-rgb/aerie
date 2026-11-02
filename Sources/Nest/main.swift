import AppKit

// Nest — The menu bar nest. Icons you tuck in stay tucked;
// everything else is never touched.

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
