// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit

// Before the delegate makes the model, which reads them.
UserDefaults.registerPreenDefaults()
let delegate = AppDelegate()
NSApplication.shared.delegate = delegate
NSApplication.shared.run()
