import AppKit

// DiskMount has no storyboard or main menu nib. Keep an explicit strong
// reference to the delegate so the status item and its panel are always built.
let application = NSApplication.shared
let applicationDelegate = AppDelegate()

application.setActivationPolicy(.accessory)
application.delegate = applicationDelegate
application.run()
