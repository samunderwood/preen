// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
@testable import PreenCore
import Testing

struct LinkDetectionTests {
    let cleaner = LinkCleanerTests.cleaner

    @Test func singleLinks() {
        #expect(LinkCleaner.isSingleLink("https://example.com/?a=1"))
        #expect(LinkCleaner.isSingleLink("  https://example.com/\n"))
        #expect(!LinkCleaner.isSingleLink("see https://example.com/"))
        #expect(!LinkCleaner.isSingleLink("https://example.com/\u{FFFC}"))
        #expect(!LinkCleaner.isSingleLink("https://a.com/ https://b.com/"))
        #expect(!LinkCleaner.isSingleLink("example.com"))
    }

    /// The ranges are where each link was, so Services can replace links in rich text in place.
    @Test func reportsRangesInTheOriginalText() {
        let text = "é https://example.com/?utm_source=x then https://example.org/?keep=https://example.com/?utm_source=x"
        let result = cleaner.clean(text)
        #expect(result.links.count == 1)
        let range = try! #require(result.links.first?.range)
        #expect((text as NSString).substring(with: range) == "https://example.com/?utm_source=x")
        #expect(range.location == 2)
    }

    /// A carried link that doesn't decode cleanly keeps its wrapper rather than risk a different
    /// destination.
    @Test func keepsWrappersThatDontDecodeCleanly() {
        #expect(cleaner.cleanLink("https://www.google.com/url?q=https://example.com/50%off%3Fid%3D7&sa=D")?.unwrappedHosts.isEmpty ?? true)
        #expect(cleaner.cleanLink("https://www.google.com/url?q=https://example.com/50%off&sa=D")?.unwrappedHosts.isEmpty ?? true)
    }
}
