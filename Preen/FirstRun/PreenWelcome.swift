// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import SamKit
import ServiceManagement
import SwiftUI

extension Color {
    /// The coral of Preen's icon, from the asset catalogue's accent colour.
    static let preen = Color("AccentColor")
}

enum PreenWelcome {
    /// Shown the first time Preen opens: a link to try it on, and opening at login.
    static func show(model: AppModel) {
        OnboardingWindow.show { close in
            PreenWelcomeView(onFinish: close)
                .environment(model)
        }
    }
}

private struct PreenWelcomeView: View {
    @Environment(AppModel.self) private var model
    @State private var loginItem = LoginItem.status
    let onFinish: () -> Void

    private static let example = "https://example.com/recipes/lemon-tart?utm_source=newsletter&utm_medium=email&fbclid=IwAR2xYz"

    var body: some View {
        WelcomeView(
            appName: "Preen",
            icon: .appIcon,
            tint: .preen,
            subtitle: "Preen takes the tracking out of links you copy.",
            steps: [tryStep, loginStep],
            finishedMessage: "Copy links as usual. When Preen cleans one, its menu bar icon shows what was removed, with a way to put it back.",
            finishTitle: "Done",
            onFinish: onFinish,
            onSkip: onFinish
        ) { step in
            if step.id == "try" {
                Text(Self.example)
                    .font(.callout.monospaced())
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .truncationMode(.middle)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .task {
            while !Task.isCancelled {
                loginItem = LoginItem.status
                try? await Task.sleep(for: .seconds(1.5))
            }
        }
        .onDisappear {
            WelcomeLaunch.finish()
        }
    }

    private var tryStep: WelcomeStep {
        WelcomeStep(
            id: "try",
            title: "Try It",
            detail: model.lastClean.map { "Removed \($0.removedParameters.joined(separator: ", "))" } ?? "Copy this link and watch the menu bar",
            actionTitle: "Copy Link",
            systemImage: "link",
            tint: .preen,
            isDone: model.cleanCount > 0
        ) {
            // Written as any other app would, so Preen cleans it like any other copy.
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(Self.example, forType: .string)
            try? await Task.sleep(for: .seconds(1))
        }
    }

    private var loginStep: WelcomeStep {
        WelcomeStep(
            id: "login",
            title: "Open at Login",
            detail: loginItem == .needsApproval
                ? "Allow Preen in System Settings > General > Login Items"
                : "So links are cleaned from the moment you start your Mac",
            actionTitle: loginItem == .needsApproval ? "Open Settings…" : "Turn On",
            systemImage: "power",
            tint: .preen,
            isDone: loginItem == .on
        ) {
            if loginItem == .needsApproval {
                SMAppService.openSystemSettingsLoginItems()
            } else {
                loginItem = LoginItem.set(true)
            }
        }
    }
}
