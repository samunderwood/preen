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
