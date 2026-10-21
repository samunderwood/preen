// SPDX-License-Identifier: GPL-3.0-or-later

import CryptoKit
import Foundation
@testable import PreenCore
import Testing

struct RuleSourceTests {
    static let fixtures = Bundle.module.url(forResource: "Fixtures", withExtension: nil)!

    @Test(arguments: RuleSource.allCases)
    func acceptsTheRealFiles(source: RuleSource) throws {
        let data = try Data(contentsOf: Self.fixtures.appending(path: source.fileName))
        #expect(source.isValid(data))
    }

    @Test func rejectsAListCutShort() throws {
        let list = try String(contentsOf: Self.fixtures.appending(path: RuleSource.adGuard.fileName), encoding: .utf8)
        let cut = list.split(whereSeparator: \.isNewline).prefix(2_000).joined(separator: "\n")
        #expect(TrackingParameterRules(list: cut).ruleCount >= 1_000)
        #expect(!RuleSource.adGuard.isValid(Data(cut.utf8)))
        #expect(RuleSource.hasValidChecksum(Data(list.utf8)))
    }

    /// Lists checksummed by Adblock Plus's script with a byte order mark, or a blank line after the
    /// checksum, are valid too.
    @Test func checksumFollowsTheReferenceScript() {
        let rules = "[Adblock Plus 2.0]\n! Title: Test\n\n$removeparam=utm_source\n"
        func checksummed(_ text: String, bom: Bool) -> Data {
            var normalized = text.replacingOccurrences(of: "\r", with: "")
            while normalized.contains("\n\n") { normalized = normalized.replacingOccurrences(of: "\n\n", with: "\n") }
            let digest = Data(Insecure.MD5.hash(data: Data(((bom ? "\u{FEFF}" : "") + normalized).utf8))).base64EncodedString()
                .trimmingCharacters(in: CharacterSet(charactersIn: "="))
            let withLine = text.replacingOccurrences(of: "[Adblock Plus 2.0]\n", with: "[Adblock Plus 2.0]\n! Checksum: \(digest)\n\n")
            return (bom ? Data([0xEF, 0xBB, 0xBF]) : Data()) + Data(withLine.utf8)
        }
        #expect(RuleSource.hasValidChecksum(checksummed(rules, bom: false)))
        #expect(RuleSource.hasValidChecksum(checksummed(rules, bom: true)))
        #expect(!RuleSource.hasValidChecksum(checksummed(rules, bom: false) + Data("$removeparam=x\n".utf8)))
    }

    @Test func rejectsEmptyAndTruncatedFiles() {
        #expect(!RuleSource.adGuard.isValid(Data("! Title: x\n$removeparam=".utf8)))
        #expect(!RuleSource.adGuard.isValid(Data("<html>Not found</html>".utf8)))
        #expect(!RuleSource.clearURLs.isValid(Data(#"{"providers":{}}"#.utf8)))
        #expect(!RuleSource.clearURLs.isValid(Data("not json".utf8)))
    }
}

struct RuleLoadingTests {
    let saved = FileManager.default.temporaryDirectory.appending(path: "PreenRuleLoading-\(UUID().uuidString)")

    private func save(_ source: RuleSource, _ data: Data? = nil) throws {
        try FileManager.default.createDirectory(at: saved, withIntermediateDirectories: true)
        let data = try data ?? Data(contentsOf: RuleSourceTests.fixtures.appending(path: source.fileName))
        try data.write(to: saved.appending(path: source.fileName))
    }

    @Test func usesTheBundledRulesBeforeAnyDownload() async throws {
        let rules = try await RuleDownloader(directory: saved).load(bundled: RuleSourceTests.fixtures)
        #expect(rules.downloaded.isEmpty)
        #expect(rules.parameters.ruleCount >= 1_000)
        #expect(rules.clearURLs.parameterRuleCount >= 200)
    }

    @Test func usesGoodDownloadsAndSaysWhen() async throws {
        defer { try? FileManager.default.removeItem(at: saved) }
        for source in RuleSource.allCases { try save(source) }
        let rules = try await RuleDownloader(directory: saved).load(bundled: RuleSourceTests.fixtures)
        #expect(Set(rules.downloaded.keys) == Set(RuleSource.allCases))
        #expect(rules.parameters.ruleCount >= 1_000)
    }

    /// A damaged download falls back to the bundled copy of that list only.
    @Test func fallsBackToTheBundledCopyOfABadDownload() async throws {
        defer { try? FileManager.default.removeItem(at: saved) }
        try save(.adGuard, Data("<html>Not found</html>".utf8))
        try save(.clearURLs)
        let rules = try RuleDownloader(directory: saved).loadNow(bundled: RuleSourceTests.fixtures)
        #expect(rules.downloaded[.adGuard] == nil)
        #expect(rules.downloaded[.clearURLs] != nil)
        #expect(rules.parameters.ruleCount >= 1_000)
    }
}
