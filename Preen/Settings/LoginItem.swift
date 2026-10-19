// SPDX-License-Identifier: GPL-3.0-or-later

import OSLog
import ServiceManagement

private let log = Logger(subsystem: "com.samunderwood.Preen", category: "LoginItem")

enum LoginItem: Equatable {
    case off
    case on
    /// Registered, but waiting for approval in System Settings.
    case needsApproval

    static var status: LoginItem {
        switch SMAppService.mainApp.status {
        case .enabled: .on
        case .requiresApproval: .needsApproval
        default: .off
        }
    }

    var isOn: Bool { self != .off }

    static func set(_ on: Bool) -> LoginItem {
        do {
            if on {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            log.error("Couldn't change the login item: \(error.localizedDescription)")
        }
        return status
    }
}
