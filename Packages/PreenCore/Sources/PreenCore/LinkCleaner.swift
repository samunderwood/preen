// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

/// A link Preen changed.
public struct CleanedLink: Sendable, Hashable {
    public let original: String
    public let cleaned: String
    /// The names of the parameters removed, decoded for display, in the order they appeared.
    public let removedParameters: [String]
    /// The hosts of the redirect wrappers taken off, outermost first.
    public let unwrappedHosts: [String]
    /// The cleaned link's host.
    public let host: String
    /// Where the link was in the text cleaned, in UTF-16 units, as `NSString` and attributed
    /// strings count.
    public let range: NSRange
}

public struct CleanResult: Sendable, Hashable {
    public let text: String
    /// The links that changed.
    public let links: [CleanedLink]

    public var changed: Bool { !links.isEmpty }

    public init(text: String, links: [CleanedLink]) {
        self.text = text
        self.links = links
    }
}

/// Cleans the http(s) links in some text, leaving everything else exactly as it was.
public struct LinkCleaner: Sendable {
    public let parameters: TrackingParameterRules
    public let clearURLs: ClearURLsRules
    /// Sites whose links are left alone, including their subdomains.
    public var exceptedSites: Set<String>

    /// Wrappers inside wrappers are unusual; this stops a pathological chain.
    private static let maximumUnwraps = 5

    /// Creating a detector only fails for an unknown checking type.
    private static let linkDetector = try! NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)

    public init(parameters: TrackingParameterRules, clearURLs: ClearURLsRules, exceptedSites: Set<String> = []) {
        self.parameters = parameters
        self.clearURLs = clearURLs
        self.exceptedSites = exceptedSites
    }

    public func clean(_ text: String) -> CleanResult {
        let matches = Self.linkDetector.matches(in: text, range: NSRange(text.startIndex..., in: text))
        var result = text
        var links: [CleanedLink] = []
        // Replaced from the end, so earlier ranges stay valid.
        for match in matches.reversed() {
            guard let range = Range(match.range, in: text) else { continue }
            let link = String(text[range])
            guard let cleaned = cleanLink(link, range: match.range) else { continue }
            let resultRange = Range(match.range, in: result)!
            result.replaceSubrange(resultRange, with: cleaned.cleaned)
            links.insert(cleaned, at: 0)
        }
        return CleanResult(text: result, links: links)
    }

    /// The cleaned link, or nil when there's nothing to clean, the link isn't http(s), or its site
    /// is an exception.
    public func cleanLink(_ link: String) -> CleanedLink? {
        cleanLink(link, range: NSRange(link.startIndex..., in: link))
    }

    private func cleanLink(_ link: String, range: NSRange) -> CleanedLink? {
        guard Host.of(link) != nil else { return nil }
        var current = link
        var unwrappedHosts: [String] = []

        for _ in 0..<Self.maximumUnwraps {
            guard let host = Host.of(current), !isExcepted(host), let target = clearURLs.target(of: current), target != current else { break }
            unwrappedHosts.append(host)
            current = target
        }

        guard let host = Host.of(current) else { return nil }
        var removed: [String] = []
        if !isExcepted(host) {
            (current, removed) = removeParameters(from: current, host: host)
        }
        guard current != link else { return nil }
        return CleanedLink(original: link, cleaned: current, removedParameters: removed, unwrappedHosts: unwrappedHosts, host: host, range: range)
    }

    /// Whether some text, leading and trailing whitespace aside, is one http(s) link and nothing else.
    public static func isSingleLink(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard Host.of(trimmed) != nil else { return false }
        let whole = NSRange(trimmed.startIndex..., in: trimmed)
        let matches = linkDetector.matches(in: trimmed, range: whole)
        return matches.count == 1 && matches[0].range == whole
    }

    /// The lowercased host of an http(s) link.
    public static func host(of link: String) -> String? {
        Host.of(link)
    }

    public func isExcepted(_ host: String) -> Bool {
        exceptedSites.contains { Host.host(host, isWithin: $0) }
    }

    /// Works on the link as written, so the parameters that stay keep their order and encoding.
    private func removeParameters(from link: String, host: String) -> (String, [String]) {
        let hash = link.firstIndex(of: "#") ?? link.endIndex
        let main = link[..<hash]
        let fragment = link[hash...]
        guard let question = main.firstIndex(of: "?") else { return (link, []) }

        let base = main[..<question]
        let parameters = main[main.index(after: question)...]
            .split(separator: "&", omittingEmptySubsequences: false)
            .map(String.init)
        let protected = self.parameters.indicesProtected(link: link, host: host, parameters: parameters)
        let indices = self.parameters.indicesToRemove(link: link, host: host, parameters: parameters)
            .union(clearURLs.indicesToRemove(link: link, parameters: parameters).subtracting(protected))
        guard !indices.isEmpty else { return (link, []) }

        var removed: [String] = []
        var kept: [String] = []
        for (index, parameter) in parameters.enumerated() {
            if indices.contains(index) {
                let name = String(parameter.prefix { $0 != "=" })
                let displayName = name.removingPercentEncoding ?? name
                if !removed.contains(displayName) { removed.append(displayName) }
            } else {
                kept.append(parameter)
            }
        }
        let query = kept.allSatisfy(\.isEmpty) ? "" : "?" + kept.joined(separator: "&")
        return (base + query + fragment, removed)
    }
}
