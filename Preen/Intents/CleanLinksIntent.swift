// SPDX-License-Identifier: GPL-3.0-or-later

import AppIntents

/// The Shortcuts action, for cleaning links in any text a shortcut has.
struct CleanLinksIntent: AppIntent {
    static let title: LocalizedStringResource = "Clean Links"
    static let description = IntentDescription("Removes tracking parameters and redirect wrappers from the links in some text, leaving the rest as it is.")

    @Parameter(title: "Text")
    var text: String

    @Dependency
    private var model: AppModel

    static var parameterSummary: some ParameterSummary {
        Summary("Clean links in \(\.$text)")
    }

    func perform() async throws -> some IntentResult & ReturnsValue<String> {
        .result(value: await model.cleanText(text).text)
    }
}
