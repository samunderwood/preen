// SPDX-License-Identifier: GPL-3.0-or-later

import SamKit
import SwiftUI

nonisolated enum SettingsTab: String, CaseIterable, SettingsPane {
    case general
    case exceptions
    case rules
    case about

    var id: Self { self }

    var title: String {
        switch self {
        case .general: "General"
        case .exceptions: "Exceptions"
        case .rules: "Rules"
        case .about: "About"
        }
    }

    var systemImage: String {
        switch self {
        case .general: "gearshape.fill"
        case .exceptions: "hand.raised.fill"
        case .rules: "list.bullet.rectangle.fill"
        case .about: "info.circle.fill"
        }
    }

    var tint: Color {
        switch self {
        case .general, .about: .gray
        case .exceptions: .orange
        case .rules: .blue
        }
    }
}

@Observable
final class SettingsNavigation {
    static let shared = SettingsNavigation()
    var selectedTab = SettingsTab.general
    private init() {}
}

struct SettingsView: View {
    @State private var navigation = SettingsNavigation.shared

    var body: some View {
        SettingsSplitView(groups: [[.general, .exceptions, .rules], [.about]], selection: $navigation.selectedTab) { tab in
            switch tab {
            case .general: GeneralSettingsPane()
            case .exceptions: ExceptionsSettingsPane()
            case .rules: RulesSettingsPane()
            case .about: AboutSettingsPane()
            }
        }
    }
}
