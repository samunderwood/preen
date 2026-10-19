// SPDX-License-Identifier: GPL-3.0-or-later

import SamKit
import SamKitUpdates
import SwiftUI

enum Links {
    static let sourceCode = URL(string: "https://github.com/samunderwood/preen")!
    static let licence = URL(string: "https://www.gnu.org/licenses/gpl-3.0.html")!
}

struct AboutSettingsPane: View {
    var body: some View {
        AboutPane(links: [
            AboutLink("Source Code", url: Links.sourceCode),
            AboutLink("Licence: GNU GPL 3.0 or later", url: Links.licence),
        ]) {
            UpdatesSection()
        }
    }
}
