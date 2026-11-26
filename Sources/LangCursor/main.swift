import AppKit

let application = NSApplication.shared
Preference.migrateLegacyBadge()
let appDelegate = AppDelegate()
application.delegate = appDelegate
application.setActivationPolicy(.accessory)
application.run()
