// SPDX-License-Identifier: GPL-3.0-or-later

import PreenCore
import SamKit
import SwiftUI

struct RulesSettingsPane: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model

        Form {
            Section {
                ForEach(RuleSource.allCases) { source in
                    LabeledContent {
                        Link(destination: source.homepage) {
                            Image(systemName: "arrow.up.forward.square")
                        }
                        .help("Open the \(source.title) project")
                        .accessibilityLabel("Open the \(source.title) project")
                    } label: {
                        Text(source.title)
                        Text(detail(for: source))
                    }
                }
            } footer: {
                Text("Preen removes the tracking parameters these community lists name, and unwraps the redirect links they know. Cleaning happens on your Mac.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                Toggle(isOn: $model.updatesRulesAutomatically) {
                    Text("Update rules automatically")
                    Text("Checks once a day")
                }
                LabeledContent {
                    Button("Update Now", action: model.updateRules)
                        .disabled(model.ruleUpdateState == .updating)
                } label: {
                    Text(updateStatus)
                }
            }
        }
        .settingsPaneStyle()
    }

    private func detail(for source: RuleSource) -> String {
        guard let status = model.ruleStatus[source] else { return "" }
        let count = "\(status.ruleCount.formatted()) rules"
        guard let downloaded = status.downloaded else { return "\(count), the copy that came with Preen" }
        return "\(count), updated \(downloaded.formatted(.relative(presentation: .named)))"
    }

    private var updateStatus: String {
        switch model.ruleUpdateState {
        case .updating: "Updating…"
        case .failed: "Couldn’t update. Preen is using the rules it already had."
        case .idle: model.rulesLastUpdated.map { "Last updated \($0.formatted(.relative(presentation: .named)))" } ?? "Using the rules that came with Preen"
        }
    }
}
