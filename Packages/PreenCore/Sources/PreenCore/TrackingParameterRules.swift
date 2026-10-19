// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

/// The `$removeparam` rules of an AdGuard filter list, such as the URL Tracking filter, applied to
/// copied links instead of requests.
///
/// A link is treated as a page being opened, so rules that apply only to other kinds of request
/// (scripts, images and so on), or only to first-party requests, are skipped, as are rules with
/// options that don't make sense outside a browser. `$domain` is matched against the link's own
/// host, as AdGuard does for `$removeparam` rules on pages.
public struct TrackingParameterRules: Sendable {
    /// How many rules apply to links.
    public let ruleCount: Int
    /// Rules in the list that Preen doesn't apply.
    public let skippedCount: Int

    /// Plain names that apply to every link, the bulk of the list.
    private let everywhereNames: Set<String>
    private let rules: RuleIndex
    private let exceptions: RuleIndex

    public init(list: String) {
        var everywhereNames: Set<String> = []
        var rules = RuleIndex()
        var exceptions = RuleIndex()
        var ruleCount = 0
        var skippedCount = 0

        for line in list.split(whereSeparator: \.isNewline) {
            let line = line.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty, !line.hasPrefix("!"), !line.hasPrefix("[") else { continue }
            guard let parsed = Self.parse(line) else {
                skippedCount += 1
                continue
            }
            ruleCount += 1
            if parsed.isException {
                exceptions.add(parsed.rule)
            } else if case .name(let name) = parsed.rule.value, parsed.rule.url == nil, parsed.rule.domains == nil {
                everywhereNames.insert(name)
            } else {
                rules.add(parsed.rule)
            }
        }

        self.everywhereNames = everywhereNames
        self.rules = rules
        self.exceptions = exceptions
        self.ruleCount = ruleCount
        self.skippedCount = skippedCount
    }

    /// The indices of the query parameters to remove from a link.
    /// - Parameters:
    ///   - link: The whole link, which rules' URL patterns are matched against.
    ///   - host: The link's lowercased host.
    ///   - parameters: The query's parameters as written, such as `utm_source=mail`.
    func indicesToRemove(link: String, host: String, parameters: [String]) -> IndexSet {
        let exceptions = applicableExceptions(link: link, host: host)
        let excepted = Set(exceptions.map(\.valueText))
        // An exception without a value, or a $document or $urlblock exception, turns off every rule.
        if excepted.contains("") { return [] }

        let rules = rules.candidates(host: host).filter { $0.applies(to: link, host: host) && !excepted.contains($0.valueText) }
        var indices = IndexSet()
        for (index, parameter) in parameters.enumerated() where !parameter.isEmpty {
            let (name, pair) = Self.split(parameter)
            if everywhereNames.contains(String(name)), !excepted.contains(String(name)) {
                indices.insert(index)
                continue
            }
            if rules.contains(where: { $0.value.matches(name: name, pair: pair) }) {
                indices.insert(index)
            }
        }
        return indices
    }

    /// The indices of the parameters the list's exceptions keep on this link, usually because a
    /// site needs them to work. Removals from other sources are checked against these too.
    func indicesProtected(link: String, host: String, parameters: [String]) -> IndexSet {
        let exceptions = applicableExceptions(link: link, host: host)
        guard !exceptions.isEmpty else { return [] }
        if exceptions.contains(where: { $0.valueText.isEmpty }) { return IndexSet(parameters.indices) }
        var indices = IndexSet()
        for (index, parameter) in parameters.enumerated() where !parameter.isEmpty {
            let (name, pair) = Self.split(parameter)
            if exceptions.contains(where: { $0.value.matches(name: name, pair: pair) }) {
                indices.insert(index)
            }
        }
        return indices
    }

    private func applicableExceptions(link: String, host: String) -> [ParameterRule] {
        exceptions.candidates(host: host).filter { $0.applies(to: link, host: host) }
    }

    /// A parameter's name, and the `name=value` form regular expressions are matched against.
    private static func split(_ parameter: String) -> (name: Substring, pair: String) {
        (parameter.prefix { $0 != "=" }, parameter.contains("=") ? parameter : parameter + "=")
    }

    // MARK: - Parsing

    private static let otherTypes: Set<String> = [
        "xmlhttprequest", "xhr", "image", "script", "media", "subdocument", "frame", "font",
        "stylesheet", "css", "object", "other", "ping", "websocket",
    ]
    private static let ignoredOptions: Set<String> = ["important", "match-case"]
    /// Options that start a rule's option list. Those not handled when parsing make the rule skipped.
    private static let knownOptions: Set<String> = [
        "removeparam", "queryprune", "domain", "document", "doc", "urlblock", "third-party", "3p",
        "first-party", "1p", "app", "removeheader", "method", "header", "denyallow", "to", "redirect",
        "badfilter",
    ]

    static func parse(_ line: String) -> (rule: ParameterRule, isException: Bool)? {
        var line = Substring(line)
        let isException = line.hasPrefix("@@")
        if isException { line = line.dropFirst(2) }
        guard let (patternText, optionsText) = split(line) else { return nil }

        var value: ParameterValue?
        var valueText = ""
        var domains: DomainList?
        var hasRemoveParam = false
        var appliesToDocuments = false
        var appliesToOtherTypes = false
        var turnsOffEverything = false

        for option in splitOptions(optionsText) {
            let negated = option.hasPrefix("~")
            let body = negated ? option.dropFirst() : option[...]
            let name = body.prefix { $0 != "=" }.lowercased()
            let argument = body.contains("=") ? String(body.drop { $0 != "=" }.dropFirst()) : nil

            switch name {
            case "removeparam", "queryprune":
                guard !negated else { return nil }
                hasRemoveParam = true
                let text = (argument ?? "").replacingOccurrences(of: "\\,", with: ",")
                guard let parsed = ParameterValue(text) else { return nil }
                value = parsed
                valueText = text
            case "domain":
                guard !negated, let argument, let list = DomainList(argument) else { return nil }
                domains = list
            case "third-party", "3p":
                // A link pasted somewhere else is opened from another site, so only "first-party
                // only" rules are skipped.
                if negated { return nil }
            case "first-party", "1p":
                if !negated { return nil }
            case "document", "doc", "urlblock":
                if !negated {
                    appliesToDocuments = true
                    turnsOffEverything = isException
                }
            case _ where otherTypes.contains(name):
                if !negated { appliesToOtherTypes = true }
            case _ where ignoredOptions.contains(name):
                break
            default:
                return nil
            }
        }

        if appliesToOtherTypes && !appliesToDocuments { return nil }
        if isException && turnsOffEverything && !hasRemoveParam {
            value = .all
            valueText = ""
        }
        guard let value else { return nil }

        let url: URLPattern?
        if patternText.isEmpty || patternText == "*" {
            url = nil
        } else {
            guard let parsed = URLPattern(patternText) else { return nil }
            url = parsed
        }

        // Removing every parameter from every link would break links.
        if !isException, url == nil, domains == nil {
            if case .all = value { return nil }
        }

        return (ParameterRule(value: value, valueText: valueText, url: url, domains: domains), isException)
    }

    /// Splits a rule at the `$` that starts its options. A regular expression pattern can contain
    /// `$`, so the split is at the first `$` followed by a known option.
    private static func split(_ line: Substring) -> (Substring, Substring)? {
        var searchStart = line.startIndex
        while let dollar = line[searchStart...].firstIndex(of: "$") {
            let options = line[line.index(after: dollar)...]
            let name = options.drop { $0 == "~" }.prefix { $0.isLetter || $0.isNumber || $0 == "-" }.lowercased()
            if knownOptions.contains(name) || otherTypes.contains(name) || ignoredOptions.contains(name) {
                return (line[..<dollar], options)
            }
            searchStart = line.index(after: dollar)
        }
        return nil
    }

    /// Splits options at commas not escaped with a backslash.
    private static func splitOptions(_ text: Substring) -> [Substring] {
        var options: [Substring] = []
        var start = text.startIndex
        var index = text.startIndex
        while index < text.endIndex {
            if text[index] == "\\" {
                index = text.index(index, offsetBy: 2, limitedBy: text.endIndex) ?? text.endIndex
                continue
            }
            if text[index] == "," {
                options.append(text[start..<index])
                start = text.index(after: index)
            }
            index = text.index(after: index)
        }
        options.append(text[start...])
        return options.filter { !$0.isEmpty }
    }
}

// MARK: - Rule parts

enum ParameterValue: Sendable {
    case name(String)
    /// Matched against `name=value`, as AdGuard does.
    case regex(Pattern)
    case all

    init?(_ text: String) {
        if text.isEmpty {
            self = .all
        } else if text.hasPrefix("~") {
            // "Every parameter but these" rules are rare and risky on links.
            return nil
        } else if text.hasPrefix("/"), let end = text.lastIndex(of: "/"), end > text.startIndex {
            let source = String(text[text.index(after: text.startIndex)..<end])
            let flags = text[text.index(after: end)...]
            guard flags.allSatisfy({ $0 == "i" }), let pattern = try? Pattern(source, caseInsensitive: flags.contains("i")) else {
                return nil
            }
            self = .regex(pattern)
        } else {
            self = .name(text)
        }
    }

    func matches(name: Substring, pair: String) -> Bool {
        switch self {
        case .name(let wanted): name == wanted
        case .regex(let pattern): pattern.matches(pair)
        case .all: true
        }
    }
}

struct DomainList: Sendable {
    let included: [String]
    let excluded: [String]

    init?(_ text: String) {
        var included: [String] = []
        var excluded: [String] = []
        for entry in text.split(separator: "|") {
            let negated = entry.hasPrefix("~")
            let domain = (negated ? entry.dropFirst() : entry).lowercased()
            // Regular expression domains are rare, and skipped rather than half supported.
            guard !domain.isEmpty, !domain.hasPrefix("/") else { return nil }
            if negated { excluded.append(domain) } else { included.append(domain) }
        }
        self.included = included
        self.excluded = excluded
    }

    func matches(_ host: String) -> Bool {
        if excluded.contains(where: { Host.host(host, isWithin: $0) }) { return false }
        return included.isEmpty || included.contains { Host.host(host, isWithin: $0) }
    }
}

/// A rule's URL pattern in AdGuard's basic syntax (`||example.com^`, `|https://`, `*` wildcards) or
/// a `/regular expression/`.
struct URLPattern: Sendable {
    /// For `||host…` patterns, the host, which indexes the rule.
    let host: String?
    /// Nil when the pattern is just `||host^`, which the host alone decides.
    let regex: Pattern?

    init?(_ text: Substring) {
        if text.hasPrefix("/"), text.hasSuffix("/"), text.count > 2 {
            guard let regex = try? Pattern(String(text.dropFirst().dropLast())) else { return nil }
            self.host = nil
            self.regex = regex
            return
        }

        var host: String?
        if text.hasPrefix("||") {
            // A host with a wildcard, such as `google.*`, is matched by the regular expression instead.
            let candidate = text.dropFirst(2).prefix { !"^/:|?".contains($0) }.lowercased()
            if !candidate.isEmpty, !candidate.contains("*"), !candidate.hasSuffix(".") {
                host = candidate
            }
        }
        self.host = host

        let rest = text.dropFirst(2 + (host?.count ?? 0))
        if host != nil, rest == "^" || rest == "^*" || rest.isEmpty {
            regex = nil
        } else {
            guard let regex = try? Pattern(Self.regexSource(for: text)) else { return nil }
            self.regex = regex
        }
    }

    func matches(link: String, host: String) -> Bool {
        if let ruleHost = self.host, !Host.host(host, isWithin: ruleHost) { return false }
        return regex?.matches(link) ?? true
    }

    static func regexSource(for pattern: Substring) -> String {
        var text = pattern
        var source = ""
        if text.hasPrefix("||") {
            source = #"^[a-z][a-z0-9+.-]*://(?:[^/?#]*\.)?"#
            text = text.dropFirst(2)
        } else if text.hasPrefix("|") {
            source = "^"
            text = text.dropFirst()
        }
        var suffix = ""
        if text.hasSuffix("|") {
            suffix = "$"
            text = text.dropLast()
        }
        for character in text {
            switch character {
            case "*": source += ".*"
            case "^": source += #"(?:[^\w.%-]|$)"#
            default: source += NSRegularExpression.escapedPattern(for: String(character))
            }
        }
        return source + suffix
    }
}

struct ParameterRule: Sendable {
    let value: ParameterValue
    /// The value as written, which an exception names to turn the rule off.
    let valueText: String
    let url: URLPattern?
    let domains: DomainList?

    /// The hosts the rule can only apply within, or none when it could apply to any link.
    var indexHosts: [String] {
        if let host = url?.host { return [host] }
        if url == nil, let domains, !domains.included.isEmpty, domains.included.allSatisfy({ !$0.hasSuffix(".*") }) {
            return domains.included
        }
        return []
    }

    func applies(to link: String, host: String) -> Bool {
        (url?.matches(link: link, host: host) ?? true) && (domains?.matches(host) ?? true)
    }
}

/// Rules grouped by host, so a link is checked only against rules for its host and its parent
/// domains, plus the few rules that could apply anywhere.
struct RuleIndex: Sendable {
    private var byHost: [String: [ParameterRule]] = [:]
    private var anywhere: [ParameterRule] = []

    mutating func add(_ rule: ParameterRule) {
        let hosts = rule.indexHosts
        if hosts.isEmpty {
            anywhere.append(rule)
        } else {
            for host in hosts { byHost[host, default: []].append(rule) }
        }
    }

    func candidates(host: String) -> [ParameterRule] {
        anywhere + Host.suffixes(of: host).flatMap { byHost[String($0)] ?? [] }
    }
}
