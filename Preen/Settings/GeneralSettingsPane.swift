// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import SamKit
import SwiftUI

struct GeneralSettingsPane: View {
    @Environment(AppModel.self) private var model
    @AppStorage(Feedback.soundsEnabledKey) private var playsSounds = true

    var body: some View {
        Form {
            Section {
                Toggle(isOn: Binding(get: { !model.isPaused }, set: { $0 ? model.resume() : model.pause(.untilResumed) })) {
                    Text("Clean links when you copy them")
                    if let pausedUntil = model.pausedUntil, pausedUntil != .distantFuture {
                        Text("Paused until \(pausedUntil.formatted(date: .omitted, time: .shortened))")
                    }
                }

                if let access = clipboardAccess {
                    LabeledContent {
                        Button("Open Privacy & Security…", action: ClipboardAccess.openSettings)
                    } label: {
                        Text(access.title)
                        Text(access.detail)
                    }
                }
            }

            Section {
                LoginItemToggle(model: model.loginItem)

                Toggle("Play sounds", isOn: $playsSounds)
            }
        }
        .settingsPaneStyle()
        .onAppear {
            model.refreshClipboardAccess()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            model.refreshClipboardAccess()
        }
    }

    private var clipboardAccess: (title: String, detail: String)? {
        switch model.clipboardAccess {
        case .alwaysDeny: ("Clipboard access is off", "Preen can’t clean links you copy until you allow it to read the clipboard. Services and Shortcuts still work.")
        case .ask: ("macOS asks before Preen reads the clipboard", "Choose Allow for Preen so links are cleaned without a question each time.")
        default: nil
        }
    }
}

enum ClipboardAccess {
    static func openSettings() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Pasteboard")!)
    }
}
