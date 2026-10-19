// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

/// ClearURLs' rules: per-site tracking parameters, which fill gaps in AdGuard's list such as
/// Instagram's `igsh`, and redirect wrappers, such as Google's `/url?q=` and Facebook's `l.php?u=`.
/// A few wrappers ClearURLs doesn't cover are built in. Its referral marketing rules, which would
/// remove affiliate tags, and its raw rules, which rewrite paths, aren't used.
public struct ClearURLsRules: Sendable {
    struct Provider: Sendable {
        let urlPattern: Pattern
        let exceptions: [Pattern]
        let redirections: [Pattern]
        /// Matched against whole parameter names.
        let parameters: [Pattern]
    }

    public let parameterRuleCount: Int
    public let redirectRuleCount: Int
    private let providers: [Provider]

    /// - Parameter data: ClearURLs' `data.minify.json`.
    public init(data: Data) throws {
        let file = try JSONDecoder().decode(ClearURLsFile.self, from: data)
        var providers = Self.builtIn
        for (name, provider) in file.providers where !name.hasPrefix("ClearURLsTest") {
            // A site whose exceptions don't all compile is skipped, so its links are never cleaned
            // where ClearURLs says they shouldn't be.
            guard let urlPattern = try? Pattern(provider.urlPattern),
                  let exceptions = try? (provider.exceptions ?? []).map({ try Pattern($0) })
            else { continue }
            let redirections = (provider.redirections ?? []).compactMap { try? Pattern($0) }
            let parameters = (provider.rules ?? []).compactMap { try? Pattern("^(?:" + $0 + ")$") }
            guard !redirections.isEmpty || !parameters.isEmpty else { continue }
            providers.append(Provider(
                urlPattern: urlPattern,
                exceptions: exceptions,
                redirections: redirections,
                parameters: parameters
            ))
        }
        self.providers = providers
        redirectRuleCount = providers.reduce(0) { $0 + $1.redirections.count }
        parameterRuleCount = providers.reduce(0) { $0 + $1.parameters.count }
    }

    private func providers(for link: String) -> some Sequence<Provider> {
        providers.lazy.filter { provider in
            provider.urlPattern.matches(link) && !provider.exceptions.contains { $0.matches(link) }
        }
    }

    /// The link a wrapper points to, or nil if the link isn't a known wrapper.
    func target(of link: String) -> String? {
        for provider in providers(for: link) {
            for redirection in provider.redirections {
                guard let captured = redirection.capture(in: link),
                      let target = Self.decoded(captured.text, isParameterValue: captured.preceding == "="),
                      Host.of(target) != nil
                else { continue }
                return target
            }
        }
        return nil
    }

    /// The indices of the query parameters whose names match a rule for the link's site.
    func indicesToRemove(link: String, parameters: [String]) -> IndexSet {
        let rules = providers(for: link).flatMap(\.parameters)
        guard !rules.isEmpty else { return [] }
        var indices = IndexSet()
        for (index, parameter) in parameters.enumerated() where !parameter.isEmpty {
            let name = String(parameter.prefix { $0 != "=" })
            if rules.contains(where: { $0.matches(name) }) { indices.insert(index) }
        }
        return indices
    }

    /// A link carried in a parameter's value is percent-encoded once, sometimes only partly, as in
    /// `?q=https://example.com/a%3Fb%3D1`, so it's decoded once. A link carried as it is, such as
    /// the rest of the address after `?` or in the path, keeps its own escapes. A value that doesn't
    /// decode cleanly, such as one with a stray `%`, leaves the wrapper in place rather than guess.
    /// `+` is left alone, since it means a space in the link's own query too.
    static func decoded(_ captured: String, isParameterValue: Bool) -> String? {
        let lowered = captured.lowercased()
        let hasLiteralScheme = lowered.hasPrefix("http://") || lowered.hasPrefix("https://")
        guard isParameterValue || !hasLiteralScheme else { return captured }
        guard let decoded = captured.removingPercentEncoding else { return nil }
        // Decoded, a space would end the link wherever it's pasted, a line break or a character
        // links can't contain, such as a backtick, could run a command when it's pasted into
        // Terminal, and direction marks and invisible characters could disguise the address, so
        // they stay escaped.
        var target = ""
        for scalar in decoded.unicodeScalars {
            let properties = scalar.properties
            if properties.isWhitespace || properties.isDefaultIgnorableCodePoint
                || [.control, .format].contains(properties.generalCategory)
                || #""<>^`{|}"#.unicodeScalars.contains(scalar) {
                target += String(scalar).utf8.map { String(format: "%%%02X", $0) }.joined()
            } else {
                target.unicodeScalars.append(scalar)
            }
        }
        return target
    }

    private static func wrapper(_ prefix: String, link: String) -> Provider {
        // Written here, so a pattern that doesn't compile is a programming error.
        Provider(
            urlPattern: try! Pattern(#"^https?://"# + prefix),
            exceptions: [],
            redirections: [try! Pattern(#"^https?://"# + prefix + link)],
            parameters: []
        )
    }

    /// Wrappers ClearURLs doesn't cover, checked before its own.
    static let builtIn: [Provider] = [
        // Outlook and Microsoft 365 Safe Links, in mail and in Teams.
        wrapper(#"[a-z0-9-]+\.safelinks\.protection\.outlook\.com/"#, link: #".*?[?&]url=([^&]+)"#),
        wrapper(#"statics\.teams\.cdn\.office\.net/evergreen-assets/safelinks/"#, link: #".*?[?&]url=([^&]+)"#),
        wrapper(#"(?:www\.)?linkedin\.com/redir/[a-z-]+"#, link: #"\?(?:.*?&)?url=([^&]+)"#),
        wrapper(#"slack-redir\.net/link"#, link: #"\?(?:.*?&)?url=([^&]+)"#),
        wrapper(#"(?:[a-z0-9-]+\.)?medium\.com/r/"#, link: #"\?(?:.*?&)?url=([^&]+)"#),
        wrapper(#"t\.umblr\.com/redirect"#, link: #"\?(?:.*?&)?z=([^&]+)"#),
    ]
}

private struct ClearURLsFile: Decodable {
    struct Provider: Decodable {
        let urlPattern: String
        let rules: [String]?
        let exceptions: [String]?
        let redirections: [String]?
    }

    let providers: [String: Provider]
}
