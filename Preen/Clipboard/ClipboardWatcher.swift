// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import PreenCore
import UniformTypeIdentifiers

enum PreenPasteboard {
    static let current: NSPasteboard = {
#if DEBUG
        // Keeps automatic monitoring and Welcome's sample off the person's clipboard in GUI checks.
        if ProcessInfo.processInfo.arguments.contains("--verify-ui") {
            return NSPasteboard.withUniqueName()
        }
#endif
        return .general
    }()
}

/// Text copied with a link in it, read from the clipboard.
struct Copy {
    let text: String
    let changeCount: Int
    /// The stretch of watching the copy was found in, or nil for one read on request.
    let watch: Int?
    /// Whether the text is one link and nothing else, as from Copy Link or an address bar.
    let isSingleLink: Bool
    /// The link's title, kept when Preen writes the clean link.
    let urlName: String?
    /// Whether the copy holds forms other than plain text, such as rich text, which Preen rewrites
    /// only around a single link.
    let hasRichText: Bool
    /// Whether the copy holds an image, a file or attachments, which writing text back would lose.
    let hasLossyContent: Bool
}

/// Watches the clipboard for copied links.
///
/// macOS doesn't announce clipboard changes, so the watcher checks the change count twice a
/// second, which doesn't read anything. It reads a copy only once the system's data detection says
/// it holds a link, so other copies, such as messages and passwords, are never read, and where
/// macOS asks before an app reads the clipboard, the question only comes up for links.
final class ClipboardWatcher {
    private let pasteboard: NSPasteboard
    private let detectsLink: @MainActor (NSPasteboard) async -> Bool
    private var timer: Timer?
    private var lastChangeCount: Int
    /// The change count after Preen's own last write, so it doesn't clean what it just wrote.
    private var ownChangeCount: Int?
    private var inspecting = false
    private(set) var inspection: Task<Void, Never>?
    /// Changes each time watching stops, so a copy found before then is never written.
    private var watch = 0
    /// The apps that were frontmost since the last check, any of which could have made a copy.
    private var recentApps: [NSRunningApplication] = []
    private var activationObserver: NSObjectProtocol?

    /// Asked first, with every app the copy could have come from, before anything about the copy
    /// is looked at.
    var shouldInspect: (_ possibleSources: [NSRunningApplication]) -> Bool = { _ in true }
    var onCopy: (Copy) -> Void = { _ in }

    /// - Parameter detectsLink: Asks whether a copy holds a link without reading it. Tests replace it
    ///   to hold an inspection in flight.
    init(pasteboard: NSPasteboard = PreenPasteboard.current, detectsLink: @escaping @MainActor (NSPasteboard) async -> Bool = ClipboardWatcher.detectsLink) {
        self.pasteboard = pasteboard
        self.detectsLink = detectsLink
        lastChangeCount = pasteboard.changeCount
    }

    /// Nil while a read waits for macOS's approval, when the pasteboard mustn't be touched.
    var changeCount: Int? { inspecting ? nil : pasteboard.changeCount }

    func start() {
        guard timer == nil else { return }
        // Changes made while stopped, such as during a pause, are left alone.
        if !inspecting { lastChangeCount = pasteboard.changeCount }
        recentApps = NSWorkspace.shared.frontmostApplication.map { [$0] } ?? []
        activationObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { [weak self] notification in
            guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
            MainActor.assumeIsolated { self?.recentApps.append(app) }
        }
        let timer = Timer(timeInterval: 0.5, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.check() }
        }
        timer.tolerance = 0.25
        // Only in the default mode, so it never fires inside the nested run loop of a system prompt.
        RunLoop.main.add(timer, forMode: .default)
        self.timer = timer
    }

    func stop() {
        watch += 1
        // Leaves `inspecting` as it is: a read waiting for macOS's approval still holds the pasteboard.
        inspection?.cancel()
        inspection = nil
        timer?.invalidate()
        timer = nil
        activationObserver.map(NSWorkspace.shared.notificationCenter.removeObserver)
        activationObserver = nil
    }

    func check() {
        // Where macOS asks before an app reads the clipboard, the read waits for an answer in a
        // nested run loop holding the pasteboard, and touching it again from there crashes.
        guard !inspecting else { return }
        // The frontmost app nearly always made the copy, but someone can switch apps between a copy
        // and the next check, so every app frontmost since the last check counts. The
        // nspasteboard.org source marker would be more precise, but reading it reads the clipboard.
        let possibleSources = recentApps
        recentApps = NSWorkspace.shared.frontmostApplication.map { [$0] } ?? []

        let changeCount = pasteboard.changeCount
        guard changeCount != lastChangeCount else { return }
        lastChangeCount = changeCount
        guard changeCount != ownChangeCount else { return }
        guard shouldInspect(possibleSources + recentApps), Self.mayHoldCleanableText(pasteboard) else { return }

        inspecting = true
        let watch = watch
        inspection = Task {
            let copy = await read(changeCount: changeCount, watch: watch)
            // Cleared before the copy is handled, since handling it writes to the clipboard.
            inspecting = false
            guard watch == self.watch else { return }
            copy.map(onCopy)
        }
    }

    /// Reads the clipboard for "Clean Clipboard Now", whatever was copied and whenever.
    func readNow() async -> Copy? {
        guard !inspecting else { return nil }
        let changeCount = pasteboard.changeCount
        guard Self.mayHoldCleanableText(pasteboard) else { return nil }
        inspecting = true
        defer { inspecting = false }
        return await read(changeCount: changeCount, watch: nil)
    }

    private func read(changeCount: Int, watch: Int?) async -> Copy? {
        guard await detectsLink(pasteboard),
              pasteboard.changeCount == changeCount,
              let item = pasteboard.pasteboardItems?.first,
              let text = item.string(forType: .string),
              text.utf8.count <= Self.maximumLength
        else { return nil }

        let types = Set(item.types)
        return Copy(
            text: text,
            changeCount: changeCount,
            watch: watch,
            isSingleLink: LinkCleaner.isSingleLink(text),
            urlName: types.contains(.urlName) ? item.string(forType: .urlName) : nil,
            hasRichText: !types.isSubset(of: Self.plainTypes),
            hasLossyContent: types.contains(where: Self.isLossy)
        )
    }

    private static func detectsLink(_ pasteboard: NSPasteboard) async -> Bool {
        // NSPasteboard isn't marked Sendable, but the general pasteboard is safe to use from any thread.
        nonisolated(unsafe) let general = pasteboard
        guard let found = try? await general.detectedPatterns(for: [\.probableWebURL, \.links]) else { return false }
        return !found.isEmpty
    }

    /// Writes cleaned text in place of a copy, unless something newer has been copied since or the
    /// copy was found before watching last stopped, as it does for a pause. A single link keeps its
    /// title, cleaned too, since browsers often use the address as the title. Rich text forms such as
    /// HTML are left out rather than rewritten, since HTML can write a link in too many ways to be
    /// sure none still holds the tracked one. Returns the clipboard's change count after the write.
    func write(_ cleaned: CleanResult, title: String?, replacing copy: Copy) -> Int? {
        if let watch = copy.watch, watch != self.watch { return nil }
        let item = NSPasteboardItem()
        item.setString(cleaned.text, forType: .string)
        if copy.isSingleLink {
            item.setString(cleaned.text.trimmingCharacters(in: .whitespacesAndNewlines), forType: .URL)
            if let title { item.setString(title, forType: .urlName) }
        }
        return writeOwn(item, expecting: copy.changeCount)
    }

    /// Puts text on the clipboard, such as an original link being restored. Returns the clipboard's
    /// change count after the write.
    @discardableResult
    func write(text: String, isSingleLink: Bool) -> Int? {
        let item = NSPasteboardItem()
        item.setString(text, forType: .string)
        if isSingleLink { item.setString(text.trimmingCharacters(in: .whitespacesAndNewlines), forType: .URL) }
        return writeOwn(item, expecting: nil)
    }

    /// - Parameter expecting: The change count the clipboard must still have, checked as late as
    ///   possible so a newer copy is never replaced.
    private func writeOwn(_ item: NSPasteboardItem, expecting: Int?) -> Int? {
        // While a read waits for macOS's approval, the pasteboard mustn't be touched.
        guard !inspecting else { return nil }
        item.setString(Bundle.main.bundleIdentifier!, forType: .source)
        if let expecting, pasteboard.changeCount != expecting { return nil }
        pasteboard.clearContents()
        guard pasteboard.writeObjects([item]) else { return nil }
        ownChangeCount = pasteboard.changeCount
        lastChangeCount = pasteboard.changeCount
        return ownChangeCount
    }

    /// Nil while a read waits for macOS's approval, when the pasteboard mustn't be touched.
    var accessBehavior: NSPasteboard.AccessBehavior? { inspecting ? nil : pasteboard.accessBehavior }

    // MARK: - Types

    /// Long text, such as a whole document, isn't worth holding up the clipboard for.
    private static let maximumLength = 32_000

    /// Whether the copy is text that isn't marked private and isn't a mix of items. Reading the
    /// types doesn't read what was copied.
    private static func mayHoldCleanableText(_ pasteboard: NSPasteboard) -> Bool {
        guard pasteboard.pasteboardItems?.count == 1, let types = pasteboard.types, types.contains(.string) else { return false }
        return types.allSatisfy { !privateTypes.contains($0) }
    }

    /// The markers password managers and other apps put on copies that shouldn't be kept or changed.
    /// See nspasteboard.org.
    private static let privateTypes: Set<NSPasteboard.PasteboardType> = [
        .init("org.nspasteboard.ConcealedType"),
        .init("org.nspasteboard.TransientType"),
        .init("org.nspasteboard.AutoGeneratedType"),
        .init("com.agilebits.onepassword"),
        .init("de.petermaurer.TransientPasteboardType"),
    ]

    /// Forms of plain text and links. Anything else, such as rich text, images or files, counts as
    /// other content.
    private static let plainTypes: Set<NSPasteboard.PasteboardType> = [
        .string, .URL, .urlName, .source,
        .init("public.utf16-external-plain-text"),
        .init("public.utf16-plain-text"),
        .init("public.plain-text"),
        .init("NSStringPboardType"),
        .init("Apple URL pasteboard type"),
        .init("com.apple.traditional-mac-plain-text"),
        .init("com.apple.is-remote-clipboard"),
        .init("org.chromium.source-url"),
        .init("org.chromium.internal-source-rfh-token"),
    ]

    /// Images, files, promised files and documents with attachments, which rewriting a copy as
    /// text would lose. Other forms of a single link, such as a browser's own link and title
    /// types, are dropped.
    private static func isLossy(_ type: NSPasteboard.PasteboardType) -> Bool {
        if promisedFileTypes.contains(type) { return true }
        guard let uti = UTType(type.rawValue) else { return false }
        // Old pasteboard type names, such as a file list, appear as dynamic identifiers tagged with
        // the old name.
        if let names = uti.tags[UTTagClass(rawValue: "com.apple.nspboard-type")], !legacyFileTypeNames.isDisjoint(with: names) {
            return true
        }
        return [.image, .pdf, .audiovisualContent, .fileURL, .rtfd, .flatRTFD, .webArchive].contains { uti.conforms(to: $0) }
    }

    private static let promisedFileTypes: Set<NSPasteboard.PasteboardType> = [
        .init("com.apple.pasteboard.promised-file-url"),
        .init("com.apple.pasteboard.promised-file-content-type"),
        .init("com.apple.NSFilePromiseItemMetaData"),
    ]

    private static let legacyFileTypeNames: Set<String> = [
        "NSFilenamesPboardType", "NSFilesPromisePboardType", "NSPromiseContentsPboardType",
        "Apple files promise pasteboard type", "NSTIFFPboardType", "NSPICTPboardType", "NSPDFPboardType",
    ]
}

extension NSPasteboard.PasteboardType {
    static let urlName = Self("public.url-name")
    static let source = Self("org.nspasteboard.source")
}
