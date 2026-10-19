// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
@testable import PreenCore
import Testing

struct TrackingParameterRulesTests {
    func removed(_ list: String, from link: String) -> [String] {
        let rules = TrackingParameterRules(list: list)
        let query = link.split(separator: "?", maxSplits: 1).last.map(String.init) ?? ""
        let parameters = query.split(separator: "&", omittingEmptySubsequences: false).map(String.init)
        let indices = rules.indicesToRemove(link: link, host: Host.of(link)!, parameters: parameters)
        return indices.map { String(parameters[$0].prefix { $0 != "=" }) }
    }

    @Test func plainNamesApplyEverywhere() {
        #expect(removed("$removeparam=ref_src", from: "https://a.com/?ref_src=x&b=1") == ["ref_src"])
    }

    @Test func regexMatchesNameAndValue() {
        let list = "$removeparam=/^utm_source=campaign$/"
        #expect(removed(list, from: "https://a.com/?utm_source=campaign") == ["utm_source"])
        #expect(removed(list, from: "https://a.com/?utm_source=other").isEmpty)
        #expect(removed("$removeparam=/^ITM_/i", from: "https://a.com/?itm_x=1") == ["itm_x"])
    }

    @Test func hostRulesApplyToSubdomainsOnly() {
        let list = "||example.com^$removeparam=src"
        #expect(removed(list, from: "https://www.example.com/?src=1") == ["src"])
        #expect(removed(list, from: "https://notexample.com/?src=1").isEmpty)
    }

    @Test func pathPatterns() {
        let list = "||youtube.com/shorts/$removeparam=si"
        #expect(removed(list, from: "https://www.youtube.com/shorts/abc?si=1") == ["si"])
        #expect(removed(list, from: "https://www.youtube.com/watch?v=abc&si=1").isEmpty)
    }

    @Test func domainOption() {
        let list = "$removeparam=from,domain=a.com|~b.a.com"
        #expect(removed(list, from: "https://a.com/?from=x") == ["from"])
        #expect(removed(list, from: "https://b.a.com/?from=x").isEmpty)
        #expect(removed(list, from: "https://c.com/?from=x").isEmpty)
        #expect(removed("$removeparam=ref,domain=amazon.*", from: "https://www.amazon.co.uk/?ref=1") == ["ref"])
    }

    @Test func exceptions() {
        let list = """
        $removeparam=utm_source
        $removeparam=gclid
        @@||keep.com^$removeparam=utm_source
        @@||all.com^$removeparam
        @@||site.com^$document
        """
        #expect(removed(list, from: "https://keep.com/?utm_source=a&gclid=b") == ["gclid"])
        #expect(removed(list, from: "https://all.com/?utm_source=a&gclid=b").isEmpty)
        #expect(removed(list, from: "https://site.com/?utm_source=a&gclid=b").isEmpty)
    }

    @Test func removesEverythingOnlyForTargetedRules() {
        #expect(removed("||track.com^$removeparam", from: "https://track.com/?a=1&b=2") == ["a", "b"])
        let generic = TrackingParameterRules(list: "$removeparam")
        #expect(generic.ruleCount == 0)
        #expect(generic.skippedCount == 1)
    }

    @Test func skipsRulesForOtherRequestTypes() {
        let rules = TrackingParameterRules(list: """
        $removeparam=a,xmlhttprequest
        $removeparam=b,~third-party
        $removeparam=c,app=chrome.exe
        $removeparam=~d
        ||x.com^$removeheader=request:referer
        $removeparam=e,document
        $removeparam=f,~image
        """)
        #expect(rules.ruleCount == 2)
        #expect(rules.skippedCount == 5)
    }

    @Test func wildcardHosts() {
        let list = """
        ||google.*/search$removeparam=sclient
        @@||archive.*^$removeparam
        $removeparam=utm_source
        """
        #expect(removed(list, from: "https://www.google.com/search?q=a&sclient=gws") == ["sclient"])
        #expect(removed(list, from: "https://www.google.co.uk/search?q=a&sclient=gws") == ["sclient"])
        #expect(removed(list, from: "https://archive.ph/abc?utm_source=x").isEmpty)
    }

    @Test func escapedCommasInRegex() {
        #expect(removed(#"$removeparam=/^__s=[a-z]{3\,}/"#, from: "https://a.com/?__s=abcd&__s2=x") == ["__s"])
    }

    @Test func parsesTheWholeList() throws {
        let fixtures = try #require(Bundle.module.url(forResource: "Fixtures", withExtension: nil))
        let list = try String(contentsOf: fixtures.appending(path: "adguard-url-tracking.txt"), encoding: .utf8)
        let rules = TrackingParameterRules(list: list)
        #expect(rules.ruleCount > 2_500)
        #expect(rules.skippedCount < 150)
    }
}
