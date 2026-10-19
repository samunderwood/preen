// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
@testable import PreenCore
import Testing

/// Real links run through the rule snapshots in Fixtures, which match the ones bundled with the app.
struct LinkCleanerTests {
    static let cleaner: LinkCleaner = {
        let fixtures = Bundle.module.url(forResource: "Fixtures", withExtension: nil)!
        let list = try! String(contentsOf: fixtures.appending(path: "adguard-url-tracking.txt"), encoding: .utf8)
        let clearURLs = try! Data(contentsOf: fixtures.appending(path: "clearurls.json"))
        return LinkCleaner(parameters: TrackingParameterRules(list: list), clearURLs: try! ClearURLsRules(data: clearURLs))
    }()

    func clean(_ text: String) -> String {
        Self.cleaner.clean(text).text
    }

    @Test(arguments: [
        ("https://example.com/article?utm_source=newsletter&utm_medium=email&id=42", "https://example.com/article?id=42"),
        ("https://example.com/?fbclid=IwAR0abc", "https://example.com/"),
        ("https://shop.example/item?gclid=Cj0KCQ&colour=red", "https://shop.example/item?colour=red"),
        ("https://example.org/page?msclkid=abc123#section", "https://example.org/page#section"),
        ("https://example.org/news?mc_eid=1a2b3c&mc_cid=9z", "https://example.org/news"),
        ("https://www.instagram.com/p/C1abcDEF/?igsh=MWQ1ZGUxMzBkMA==", "https://www.instagram.com/p/C1abcDEF/"),
        ("https://open.spotify.com/track/4cOdK2wGLETKBW3PvgPWqT?si=2c1a7e8f4b2d4c3a", "https://open.spotify.com/track/4cOdK2wGLETKBW3PvgPWqT"),
        ("https://youtu.be/dQw4w9WgXcQ?si=abcDEF123", "https://youtu.be/dQw4w9WgXcQ"),
        ("https://www.youtube.com/watch?v=dQw4w9WgXcQ&pp=ygUJcmljayByb2xs&t=42", "https://www.youtube.com/watch?v=dQw4w9WgXcQ&t=42"),
    ])
    func removesTrackingParameters(link: String, expected: String) {
        #expect(clean(link) == expected)
    }

    @Test(arguments: [
        "https://www.youtube.com/watch?v=dQw4w9WgXcQ&t=42",
        "https://www.google.com/search?q=preen+app",
        "https://www.amazon.co.uk/dp/B0CHX1W1XY",
        "https://example.com/download?X-Amz-Signature=abc&X-Amz-Expires=300&token=xyz",
        "https://github.com/samunderwood/preen/pull/1?diff=split",
        "https://example.com/search?q=a%20b&page=2#results",
        "https://maps.apple.com/?ll=51.5,-0.12&q=London",
    ])
    func leavesLinksThatNeedTheirParameters(link: String) {
        #expect(Self.cleaner.cleanLink(link) == nil)
    }

    @Test(arguments: [
        (
            "https://www.google.com/url?sa=t&source=web&rct=j&url=https%3A%2F%2Fexample.com%2Fpage%3Fid%3D1%26utm_source%3Dgoogle&ved=2ah",
            "https://example.com/page?id=1"
        ),
        (
            "https://l.facebook.com/l.php?u=https%3A%2F%2Fexample.com%2Fstory%3Ffbclid%3DIwAR1&h=AT0abc",
            "https://example.com/story"
        ),
        (
            "https://eur03.safelinks.protection.outlook.com/?url=https%3A%2F%2Fexample.com%2Finvoice%3Fref%3D7&data=05%7C01&sdata=abc&reserved=0",
            "https://example.com/invoice?ref=7"
        ),
        (
            "https://www.linkedin.com/redir/redirect?url=https%3A%2F%2Fexample.com%2Fjobs&urlhash=abc&trk=public_post",
            "https://example.com/jobs"
        ),
        (
            "https://www.youtube.com/redirect?event=video_description&redir_token=QUFF&q=https%3A%2F%2Fexample.com%2F",
            "https://example.com/"
        ),
        (
            "https://slack-redir.net/link?url=https%3A%2F%2Fexample.com%2Fdocs",
            "https://example.com/docs"
        ),
    ])
    func unwrapsRedirects(link: String, expected: String) {
        #expect(clean(link) == expected)
    }

    @Test func unwrapsNestedWrappers() throws {
        let inner = "https://www.google.com/url?q=https%3A%2F%2Fexample.com%2F%3Futm_source%3Dx"
        let outer = "https://eur03.safelinks.protection.outlook.com/?url=" + inner.addingPercentEncoding(withAllowedCharacters: .alphanumerics)! + "&data=1"
        let cleaned = try #require(Self.cleaner.cleanLink(outer))
        #expect(cleaned.cleaned == "https://example.com/")
        #expect(cleaned.unwrappedHosts == ["eur03.safelinks.protection.outlook.com", "www.google.com"])
    }

    /// AdGuard keeps `utm_source` on eneba.com because removing it breaks the site's verification,
    /// and ClearURLs' general rules mustn't remove it anyway.
    @Test func adGuardExceptionsApplyToClearURLsToo() {
        #expect(Self.cleaner.cleanLink("https://www.eneba.com/?utm_source=x") == nil)
        #expect(clean("https://www.eneba.com/?utm_source=x&gclid=y") == "https://www.eneba.com/?utm_source=x")
        // Archived addresses are left whole, or they'd open a different page.
        #expect(Self.cleaner.cleanLink("https://wayback.archive-it.org/1234/20200101000000/https://example.com/?utm_source=news&id=1") == nil)
        #expect(Self.cleaner.cleanLink("https://web.archive.org/web/2024/https://example.com/?utm_source=x") == nil)
    }

    @Test func keepsTheEncodingOfUnwrappedLinks() {
        // Carried in a parameter, encoded once.
        #expect(clean("https://www.google.com/url?q=https://example.com/search?q%3Da%2526b%26id%3D1&sa=D") == "https://example.com/search?q=a%26b&id=1")
        #expect(clean("https://www.google.com/url?q=https%3A%2F%2Fexample.com%2Fa%2520b&sa=D") == "https://example.com/a%20b")
        #expect(clean("https://www.google.com/url?q=https%3A%2F%2Fexample.com%2F%3Fq%3Da%2Bb&sa=D") == "https://example.com/?q=a+b")
    }

    @Test func keepsEscapesInLinksCarriedAsTheyAre() throws {
        let json = #"{"providers":{"hrefli":{"urlPattern":"^https?://href\\.li","redirections":["^https?://href\\.li/\\?(.*)"]}}}"#
        let cleaner = LinkCleaner(parameters: TrackingParameterRules(list: ""), clearURLs: try ClearURLsRules(data: Data(json.utf8)))
        #expect(cleaner.cleanLink("https://href.li/?https://example.com/search?q=a%26b")?.cleaned == "https://example.com/search?q=a%26b")
    }

    @Test func keepsTheRestOfTheText() {
        let text = "Have a look at https://example.com/a?utm_source=x&id=1, and (https://example.org/?fbclid=y).\nThanks!"
        #expect(clean(text) == "Have a look at https://example.com/a?id=1, and (https://example.org/).\nThanks!")
    }

    @Test func reportsWhatWasRemoved() throws {
        let result = Self.cleaner.clean("https://example.com/?utm_source=a&utm_medium=b&utm_source=c&q=1")
        let link = try #require(result.links.first)
        #expect(link.removedParameters == ["utm_source", "utm_medium"])
        #expect(link.host == "example.com")
        #expect(result.text == "https://example.com/?q=1")
    }

    @Test func keepsTheEncodingAndOrderOfOtherParameters() {
        #expect(clean("https://example.com/?b=%2Fx+y&utm_campaign=z&a=%E2%9C%93") == "https://example.com/?b=%2Fx+y&a=%E2%9C%93")
    }

    @Test func leavesTextWithoutLinksAlone() {
        let text = "utm_source=not-a-link and example dot com"
        #expect(Self.cleaner.clean(text) == CleanResult(text: text, links: []))
    }

    @Test func ignoresNonWebLinks() {
        #expect(Self.cleaner.cleanLink("ftp://example.com/?utm_source=x") == nil)
        #expect(Self.cleaner.cleanLink("mailto:someone@example.com?utm_source=x") == nil)
    }

    @Test func leavesExceptedSitesAlone() {
        var cleaner = Self.cleaner
        cleaner.exceptedSites = ["example.com"]
        #expect(cleaner.cleanLink("https://news.example.com/?utm_source=x") == nil)
        #expect(cleaner.cleanLink("https://example.org/?utm_source=x")?.cleaned == "https://example.org/")
        // A wrapper around an excepted site is still taken off, but the site's parameters stay.
        #expect(cleaner.cleanLink("https://www.google.com/url?q=https%3A%2F%2Fexample.com%2F%3Futm_source%3Dx")?.cleaned == "https://example.com/?utm_source=x")
    }

    @Test func appliesTheWholeListQuickly() {
        let text = Array(repeating: "https://example.com/a?utm_source=x&id=1 ", count: 200).joined()
        let start = ContinuousClock.now
        _ = Self.cleaner.clean(text)
        #expect(ContinuousClock.now - start < .seconds(1))
    }
}
