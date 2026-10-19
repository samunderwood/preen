// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

struct Pattern: Sendable {
    let regex: NSRegularExpression

    init(_ source: String, caseInsensitive: Bool = true) throws {
        regex = try NSRegularExpression(pattern: source, options: caseInsensitive ? [.caseInsensitive] : [])
    }

    func matches(_ string: String) -> Bool {
        regex.firstMatch(in: string, range: NSRange(string.startIndex..., in: string)) != nil
    }

    /// The first capture group of the first match, and the character just before it.
    func capture(in string: String) -> (text: String, preceding: Character?)? {
        guard let match = regex.firstMatch(in: string, range: NSRange(string.startIndex..., in: string)),
              match.numberOfRanges > 1,
              let range = Range(match.range(at: 1), in: string)
        else { return nil }
        let preceding = range.lowerBound > string.startIndex ? string[string.index(before: range.lowerBound)] : nil
        return (String(string[range]), preceding)
    }
}

enum Host {
    /// The lowercased host of an http(s) link, read from the text itself so links that
    /// `URLComponents` would reject, such as ones with spaces or unencoded characters, still have one.
    static func of(_ link: String) -> String? {
        guard let schemeEnd = link.range(of: "://") else { return nil }
        let scheme = link[..<schemeEnd.lowerBound].lowercased()
        guard scheme == "http" || scheme == "https" else { return nil }
        var authority = link[schemeEnd.upperBound...].prefix { !"/?#".contains($0) }
        if let at = authority.lastIndex(of: "@") {
            authority = authority[authority.index(after: at)...]
        }
        let host = authority.hasPrefix("[") ? authority : authority.prefix { $0 != ":" }
        return host.isEmpty ? nil : host.lowercased()
    }

    /// Whether `host` is `domain` or one of its subdomains. A domain ending in `.*` matches any
    /// top-level domain, as in AdGuard's `example.*`.
    static func host(_ host: String, isWithin domain: String) -> Bool {
        if domain.hasSuffix(".*") {
            let base = domain.dropLast(2)
            let labels = host.split(separator: ".")
            let baseLabels = base.split(separator: ".")
            guard labels.count > baseLabels.count else { return false }
            for start in 0...(labels.count - baseLabels.count - 1) {
                let suffixCount = labels.count - start - baseLabels.count
                if suffixCount <= 2, Array(labels[start..<(start + baseLabels.count)]) == baseLabels {
                    return true
                }
            }
            return false
        }
        return host == domain || host.hasSuffix("." + domain)
    }

    /// The host and each parent domain, such as `a.b.com`, `b.com` and `com`.
    static func suffixes(of host: String) -> [Substring] {
        var suffixes: [Substring] = [Substring(host)]
        var rest = Substring(host)
        while let dot = rest.firstIndex(of: ".") {
            rest = rest[rest.index(after: dot)...]
            suffixes.append(rest)
        }
        return suffixes
    }
}
