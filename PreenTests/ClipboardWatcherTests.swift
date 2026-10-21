// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import PreenCore
import Testing

/// Every test uses its own named pasteboard, never the clipboard.
@MainActor
struct ClipboardWatcherTests {
    private static let link = "https://example.com/?utm_source=newsletter"
    private static let cleaned = CleanResult(text: "https://example.com/", links: [])

    private let pasteboard = NSPasteboard.withUniqueName()

    private func copy(_ text: String) {
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }

    @Test func cleansACopiedLink() async throws {
        defer { pasteboard.releaseGlobally() }
        let watcher = ClipboardWatcher(pasteboard: pasteboard, detectsLink: { _ in true })
        var delivered: [Copy] = []
        watcher.onCopy = { delivered.append($0) }

        copy(Self.link)
        watcher.check()
        await watcher.inspection?.value
        let copy = try #require(delivered.first)
        #expect(watcher.write(Self.cleaned, title: nil, replacing: copy) != nil)
        #expect(pasteboard.string(forType: .string) == Self.cleaned.text)
    }

    /// Pausing while macOS is still looking for a link in a copy stops Preen cleaning it, even if
    /// Preen is resumed before the answer comes.
    @Test func pausingStopsAnInspectionInFlight() async throws {
        defer { pasteboard.releaseGlobally() }
        let detection = HeldDetection()
        let watcher = ClipboardWatcher(pasteboard: pasteboard, detectsLink: detection.detect)
        var delivered: [Copy] = []
        watcher.onCopy = { delivered.append($0) }

        copy(Self.link)
        watcher.check()
        let inspection = try #require(watcher.inspection)
        await detection.waitUntilAsked()
        watcher.stop()
        watcher.start()
        detection.answer()
        await inspection.value
        watcher.stop()

        #expect(delivered.isEmpty)
        #expect(pasteboard.string(forType: .string) == Self.link)
    }

    /// A copy handed over before a pause, such as one waiting for the rules to load, isn't
    /// written after it.
    @Test func aCopyFromBeforeAPauseIsNeverWritten() async throws {
        defer { pasteboard.releaseGlobally() }
        let watcher = ClipboardWatcher(pasteboard: pasteboard, detectsLink: { _ in true })
        var delivered: [Copy] = []
        watcher.onCopy = { delivered.append($0) }

        copy(Self.link)
        watcher.check()
        await watcher.inspection?.value
        let copy = try #require(delivered.first)
        watcher.stop()

        #expect(watcher.write(Self.cleaned, title: nil, replacing: copy) == nil)
        #expect(pasteboard.string(forType: .string) == Self.link)
    }

    @Test func cleaningNowStillWorksWhilePaused() async throws {
        defer { pasteboard.releaseGlobally() }
        let watcher = ClipboardWatcher(pasteboard: pasteboard, detectsLink: { _ in true })
        watcher.stop()

        copy(Self.link)
        let copy = try #require(await watcher.readNow())
        #expect(watcher.write(Self.cleaned, title: nil, replacing: copy) != nil)
        #expect(pasteboard.string(forType: .string) == Self.cleaned.text)
    }

    @Test func neverReplacesANewerCopy() async throws {
        defer { pasteboard.releaseGlobally() }
        let watcher = ClipboardWatcher(pasteboard: pasteboard, detectsLink: { _ in true })
        var delivered: [Copy] = []
        watcher.onCopy = { delivered.append($0) }

        copy(Self.link)
        watcher.check()
        await watcher.inspection?.value
        let copy = try #require(delivered.first)
        self.copy("Something newer")

        #expect(watcher.write(Self.cleaned, title: nil, replacing: copy) == nil)
        #expect(pasteboard.string(forType: .string) == "Something newer")
    }
}

/// Link detection that waits for the test to answer, as it can while macOS works.
@MainActor
private final class HeldDetection {
    private var asked: CheckedContinuation<Void, Never>?
    private var answered: CheckedContinuation<Void, Never>?
    private var wasAsked = false

    func detect(_: NSPasteboard) async -> Bool {
        wasAsked = true
        asked?.resume()
        asked = nil
        // Ignores cancellation, as a system call can.
        await withCheckedContinuation { answered = $0 }
        return true
    }

    func waitUntilAsked() async {
        guard !wasAsked else { return }
        await withCheckedContinuation { asked = $0 }
    }

    func answer() {
        answered?.resume()
        answered = nil
    }
}
