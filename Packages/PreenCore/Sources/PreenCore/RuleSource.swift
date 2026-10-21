// SPDX-License-Identifier: GPL-3.0-or-later

import CryptoKit
import Foundation

/// Where Preen's rules come from. Both are bundled with the app and refreshed while it runs.
public enum RuleSource: String, CaseIterable, Sendable, Identifiable {
    case adGuard
    case clearURLs

    public var id: Self { self }

    public var title: String {
        switch self {
        case .adGuard: "AdGuard URL Tracking filter"
        case .clearURLs: "ClearURLs rules"
        }
    }

    public var url: URL {
        switch self {
        case .adGuard: URL(string: "https://filters.adtidy.org/extension/ublock/filters/17.txt")!
        case .clearURLs: URL(string: "https://rules2.clearurls.xyz/data.minify.json")!
        }
    }

    public var homepage: URL {
        switch self {
        case .adGuard: URL(string: "https://github.com/AdguardTeam/AdguardFilters")!
        case .clearURLs: URL(string: "https://github.com/ClearURLs/Rules")!
        }
    }

    /// The bundled copy's name, and the downloaded copy's.
    public var fileName: String {
        switch self {
        case .adGuard: "adguard-url-tracking.txt"
        case .clearURLs: "clearurls.json"
        }
    }

    /// Whether a file holds a usable set of rules, judged by what it compiles to, so an error page,
    /// an empty list or a truncated download never replaces a good copy. Both real files have far
    /// more rules than these minimums.
    func isValid(_ data: Data) -> Bool {
        switch self {
        case .adGuard: Self.parameterRules(data) != nil
        case .clearURLs: Self.clearURLsRules(data) != nil
        }
    }

    /// The AdGuard rules a file holds, or nil if it isn't a usable set.
    static func parameterRules(_ data: Data) -> TrackingParameterRules? {
        guard hasValidChecksum(data), let text = String(data: data, encoding: .utf8) else { return nil }
        let rules = TrackingParameterRules(list: text)
        return rules.ruleCount >= 1_000 ? rules : nil
    }

    /// The ClearURLs rules a file holds, or nil if it isn't a usable set.
    static func clearURLsRules(_ data: Data) -> ClearURLsRules? {
        guard let rules = try? ClearURLsRules(data: data),
              rules.parameterRuleCount >= 200, rules.redirectRuleCount >= ClearURLsRules.builtIn.count + 30
        else { return nil }
        return rules
    }
}

extension RuleSource {
    private static let checksumLine = try! NSRegularExpression(pattern: #"^\s*!\s*checksum[\s\-:]+([\w+/=]+).*\n"#, options: [.caseInsensitive, .anchorsMatchLines])
    private static let newlines = try! NSRegularExpression(pattern: #"\n+"#)

    /// Whether an AdGuard list matches its `! Checksum:` line, so a download cut short, which
    /// would lose the exceptions near the end, is caught. The checksum is Adblock Plus's
    /// (`addChecksum.py`): with `\r` removed, runs of newlines collapsed and then the checksum line
    /// removed, the MD5 of the UTF-8 text, including any byte order mark, in Base64 without padding.
    static func hasValidChecksum(_ data: Data) -> Bool {
        // `String(decoding:)` keeps a byte order mark, which the checksum covers.
        var body = String(decoding: data, as: UTF8.self).replacingOccurrences(of: "\r", with: "")
        body = newlines.stringByReplacingMatches(in: body, range: NSRange(body.startIndex..., in: body), withTemplate: "\n")
        guard let match = checksumLine.firstMatch(in: body, range: NSRange(body.startIndex..., in: body)),
              let declaredRange = Range(match.range(at: 1), in: body),
              let lineRange = Range(match.range, in: body)
        else { return false }
        let declared = body[declaredRange].trimmingCharacters(in: CharacterSet(charactersIn: "="))
        body.removeSubrange(lineRange)
        let digest = Data(Insecure.MD5.hash(data: Data(body.utf8))).base64EncodedString()
        return digest.trimmingCharacters(in: CharacterSet(charactersIn: "=")) == declared
    }
}

/// Downloads the rules, keeping the last good copy of each so a failed download never leaves
/// Preen without them.
public struct RuleDownloader: Sendable {
    public enum Failure: Error, Equatable {
        case badStatus(Int)
        case notRules
        case tooLarge
    }

    public static let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 30
        configuration.timeoutIntervalForResource = 120
        configuration.httpCookieAcceptPolicy = .never
        configuration.httpShouldSetCookies = false
        return URLSession(configuration: configuration)
    }()

    /// Both files are well under a megabyte.
    public static let maximumSize = 10_000_000

    private let directory: URL
    private let session: URLSession

    public init(directory: URL, session: URLSession = Self.session) {
        self.directory = directory
        self.session = session
    }

    /// Compiles the downloaded rules where they're good, and the bundled ones otherwise. Compiling
    /// both takes tens of milliseconds, so this runs off the caller's actor.
    /// - Parameter bundled: The folder holding the copies bundled with the app.
    @concurrent
    public func load(bundled: URL) async throws -> RuleSet {
        try loadNow(bundled: bundled)
    }

    /// `load(bundled:)` on the caller's thread, for a caller that has to answer straight away.
    public func loadNow(bundled: URL) throws -> RuleSet {
        func bundledFile(_ source: RuleSource) throws -> Data {
            try Data(contentsOf: bundled.appending(path: source.fileName))
        }
        var downloaded: [RuleSource: Date] = [:]

        // Checking a downloaded file compiles it, so a good one is compiled only once.
        let parameters: TrackingParameterRules
        if let saved = saved(.adGuard), let rules = RuleSource.parameterRules(saved.data) {
            parameters = rules
            downloaded[.adGuard] = saved.date
        } else {
            parameters = TrackingParameterRules(list: String(decoding: try bundledFile(.adGuard), as: UTF8.self))
        }
        let clearURLs: ClearURLsRules
        if let saved = saved(.clearURLs), let rules = RuleSource.clearURLsRules(saved.data) {
            clearURLs = rules
            downloaded[.clearURLs] = saved.date
        } else {
            clearURLs = try ClearURLsRules(data: bundledFile(.clearURLs))
        }
        return RuleSet(parameters: parameters, clearURLs: clearURLs, downloaded: downloaded)
    }

    /// The downloaded copy, not yet checked, and when it was saved, if there is one.
    private func saved(_ source: RuleSource) -> (data: Data, date: Date)? {
        let url = directory.appending(path: source.fileName)
        guard let data = try? Data(contentsOf: url),
              let date = try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
        else { return nil }
        return (data, date)
    }

    @concurrent
    public func download(_ source: RuleSource) async throws -> Data {
        let (data, response) = try await session.data(from: source.url)
        if let response = response as? HTTPURLResponse, !(200..<300).contains(response.statusCode) {
            throw Failure.badStatus(response.statusCode)
        }
        guard data.count <= Self.maximumSize else { throw Failure.tooLarge }
        guard source.isValid(data) else { throw Failure.notRules }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try data.write(to: directory.appending(path: source.fileName), options: .atomic)
        return data
    }
}

/// Both sets of rules, compiled and ready to clean with.
public struct RuleSet: Sendable {
    public let parameters: TrackingParameterRules
    public let clearURLs: ClearURLsRules
    /// When each set in use was downloaded. Sets missing here are the copies bundled with the app.
    public let downloaded: [RuleSource: Date]
}
