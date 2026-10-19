// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

enum PreferenceKey {
    static let pausedUntil = "pausedUntil"
    static let exceptedSites = "exceptedSites"
    static let excludedApps = "excludedApps"
    static let updatesRules = "updatesRulesAutomatically"
}

extension UserDefaults {
    static func registerPreenDefaults() {
        standard.register(defaults: [
            PreferenceKey.updatesRules: true,
            PreferenceKey.excludedApps: ExcludedApp.defaults.map(\.plist),
        ])
    }
}

/// An app whose copies Preen leaves alone, such as a password manager.
struct ExcludedApp: Hashable, Identifiable {
    let bundleIdentifier: String
    let name: String

    var id: String { bundleIdentifier }

    var plist: [String: String] { ["id": bundleIdentifier, "name": name] }

    init(bundleIdentifier: String, name: String) {
        self.bundleIdentifier = bundleIdentifier
        self.name = name
    }

    init?(plist: Any) {
        guard let dictionary = plist as? [String: String], let id = dictionary["id"] else { return nil }
        self.init(bundleIdentifier: id, name: dictionary["name"] ?? id)
    }

    /// Password managers mark most copies as concealed, but not every one does, or does it for
    /// everything, so their copies are left alone outright.
    static let defaults = [
        ExcludedApp(bundleIdentifier: "com.apple.Passwords", name: "Passwords"),
        ExcludedApp(bundleIdentifier: "com.apple.keychainaccess", name: "Keychain Access"),
        ExcludedApp(bundleIdentifier: "com.1password.1password", name: "1Password"),
        ExcludedApp(bundleIdentifier: "com.bitwarden.desktop", name: "Bitwarden"),
    ]
}

enum AppFiles {
    /// Downloaded rules, in the app's sandbox container, so a development build has its own.
    static var rules: URL {
        URL.applicationSupportDirectory.appending(path: "Rules")
    }

    static func bundledRules(_ name: String) -> URL {
        Bundle.main.url(forResource: name, withExtension: nil)!
    }
}
