// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import OSLog
import PreenCore
import SamKit

private let log = Logger(subsystem: "com.samunderwood.Preen", category: "Model")

/// A copy Preen cleaned. Kept in memory only, and only the last few.
struct CleanEvent: Identifiable {
    let id = UUID()
    let original: String
    let cleaned: String
    let links: [CleanedLink]
    let isSingleLink: Bool
    /// The clipboard's change count once the clean version was written, to tell whether it's
    /// still what's on the clipboard.
    let changeCount: Int

    var removedParameters: [String] {
        links.flatMap(\.removedParameters).reduce(into: []) { if !$0.contains($1) { $0.append($1) } }
    }

    var unwrappedHosts: [String] { links.flatMap(\.unwrappedHosts) }

    /// The site to offer leaving alone: the cleaned link's site, when there's one link.
    var site: String? {
        guard links.count == 1, let host = links.first?.host else { return nil }
        return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
    }
}

@Observable
final class AppModel {
    let loginItem = LoginItem()

    enum PauseDuration: CaseIterable {
        case hour, untilTomorrow, untilResumed

        var title: String {
            switch self {
            case .hour: "For 1 Hour"
            case .untilTomorrow: "Until Tomorrow"
            case .untilResumed: "Until I Resume"
            }
        }
    }

    enum RuleUpdateState: Equatable {
        case idle, updating, failed
    }

    struct RuleStatus {
        let ruleCount: Int
        /// When the rules in use were downloaded, or nil for the copy bundled with the app.
        let downloaded: Date?
    }

    static let historyLimit = 10

    private(set) var history: [CleanEvent] = []
    /// Bumped on each clean, for the menu bar icon's tick.
    private(set) var cleanCount = 0
    private(set) var pausedUntil: Date?
    private(set) var exceptedSites: [String]
    private(set) var excludedApps: [ExcludedApp]
    var updatesRulesAutomatically: Bool {
        didSet { UserDefaults.standard.set(updatesRulesAutomatically, forKey: PreferenceKey.updatesRules) }
    }

    private(set) var ruleStatus: [RuleSource: RuleStatus]
    private(set) var ruleUpdateState = RuleUpdateState.idle
    private(set) var clipboardAccess: NSPasteboard.AccessBehavior

    private var cleaner: LinkCleaner
    private let watcher = ClipboardWatcher()
    private let downloader: RuleDownloader
    private var resumeTimer: Timer?

    /// Rules are refreshed at most daily; both lists change slowly.
    private static let ruleMaximumAge: TimeInterval = 24 * 60 * 60

    init() {
        let defaults = UserDefaults.standard
        let exceptedSites = defaults.stringArray(forKey: PreferenceKey.exceptedSites) ?? []
        let downloader = RuleDownloader(directory: AppFiles.rules)
        self.exceptedSites = exceptedSites
        self.downloader = downloader
        (cleaner, ruleStatus) = Self.loadRules(from: downloader, exceptedSites: exceptedSites)
        excludedApps = (defaults.array(forKey: PreferenceKey.excludedApps) ?? []).compactMap(ExcludedApp.init(plist:))
        updatesRulesAutomatically = defaults.bool(forKey: PreferenceKey.updatesRules)
        pausedUntil = (defaults.object(forKey: PreferenceKey.pausedUntil) as? Date).flatMap { $0 > .now ? $0 : nil }
        clipboardAccess = PreenPasteboard.current.accessBehavior
    }

    func start() {
        watcher.shouldInspect = { [weak self] apps in self?.shouldInspect(copyFromAnyOf: apps) ?? false }
        watcher.onCopy = { [weak self] copy in self?.clean(copy) }
        applyPause()

        Timer.scheduledTimer(withTimeInterval: 60 * 60, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.updateRulesIfDue() }
        }
        updateRulesIfDue()
    }

    var lastClean: CleanEvent? { history.first }

    // MARK: - Cleaning

    /// Copies that could have come from an excluded app are left alone.
    private func shouldInspect(copyFromAnyOf apps: [NSRunningApplication]) -> Bool {
        guard !isPaused else { return false }
        return !apps.contains { app in excludedApps.contains { $0.bundleIdentifier == app.bundleIdentifier } }
    }

    private func clean(_ copy: Copy) {
        refreshClipboardAccess()
        // Images, files and apps' own data would be lost, and so would the formatting of rich text
        // with words around its links.
        if copy.hasLossyContent || (copy.hasRichText && !copy.isSingleLink) { return }
        let result = cleaner.clean(copy.text)
        let title = copy.urlName.map { cleaner.clean($0).text }
        guard result.changed, let changeCount = watcher.write(result, title: title, replacing: copy) else { return }

        history.insert(CleanEvent(original: copy.text, cleaned: result.text, links: result.links, isSingleLink: copy.isSingleLink, changeCount: changeCount), at: 0)
        history = Array(history.prefix(Self.historyLimit))
        cleanCount += 1
    }

    /// Cleans whatever is on the clipboard, even while paused or copied from an excluded app.
    func cleanClipboardNow() {
        Task {
            guard let copy = await watcher.readNow() else { return }
            clean(copy)
        }
    }

    /// Cleans text from Services or Shortcuts, which don't involve the clipboard.
    func cleanText(_ text: String) -> CleanResult {
        cleaner.clean(text)
    }

    /// The clean version of one link, or nil if there's nothing to clean.
    func cleanLink(_ link: String) -> String? {
        cleaner.cleanLink(link)?.cleaned
    }

    func restore(_ event: CleanEvent) {
        watcher.write(text: event.original, isSingleLink: event.isSingleLink)
        Feedback.play(.snap)
    }

    func copyCleaned(_ event: CleanEvent) {
        watcher.write(text: event.cleaned, isSingleLink: event.isSingleLink)
    }

    // MARK: - Pausing

    var isPaused: Bool { pausedUntil != nil }

    func pause(_ duration: PauseDuration) {
        switch duration {
        case .hour: pausedUntil = .now.addingTimeInterval(60 * 60)
        case .untilTomorrow:
            let calendar = Calendar.current
            pausedUntil = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: .now))
        case .untilResumed: pausedUntil = .distantFuture
        }
        UserDefaults.standard.set(pausedUntil, forKey: PreferenceKey.pausedUntil)
        applyPause()
    }

    func resume() {
        pausedUntil = nil
        UserDefaults.standard.removeObject(forKey: PreferenceKey.pausedUntil)
        applyPause()
    }

    private func applyPause() {
        resumeTimer?.invalidate()
        resumeTimer = nil
        guard let pausedUntil else {
            watcher.start()
            return
        }
        watcher.stop()
        if pausedUntil != .distantFuture {
            let timer = Timer(fire: pausedUntil, interval: 0, repeats: false) { [weak self] _ in
                MainActor.assumeIsolated { self?.resume() }
            }
            // Not in the nested run loop of a clipboard approval prompt.
            RunLoop.main.add(timer, forMode: .default)
            resumeTimer = timer
        }
    }

    // MARK: - Exceptions

    func isExcepted(site: String) -> Bool {
        cleaner.isExcepted(site)
    }

    func addException(_ site: String) {
        guard !exceptedSites.contains(site) else { return }
        exceptedSites.append(site)
        exceptedSites.sort()
        saveExceptions()
    }

    func removeException(_ site: String) {
        exceptedSites.removeAll { $0 == site }
        saveExceptions()
    }

    /// Leaves a site's links alone from now on, and puts back the original if the clean version is
    /// still what's on the clipboard.
    func neverClean(_ event: CleanEvent) {
        guard let site = event.site else { return }
        addException(site)
        if watcher.changeCount == event.changeCount { restore(event) }
    }

    private func saveExceptions() {
        UserDefaults.standard.set(exceptedSites, forKey: PreferenceKey.exceptedSites)
        cleaner.exceptedSites = Set(exceptedSites)
    }

    func addExcludedApp(_ app: ExcludedApp) {
        guard !excludedApps.contains(app) else { return }
        excludedApps.append(app)
        excludedApps.sort { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        saveExcludedApps()
    }

    func removeExcludedApp(_ app: ExcludedApp) {
        excludedApps.removeAll { $0 == app }
        saveExcludedApps()
    }

    private func saveExcludedApps() {
        UserDefaults.standard.set(excludedApps.map(\.plist), forKey: PreferenceKey.excludedApps)
    }

    // MARK: - Clipboard access

    /// Reads macOS's clipboard access setting for Preen, which matters only where macOS asks
    /// before apps read the clipboard.
    func refreshClipboardAccess() {
        if let access = watcher.accessBehavior { clipboardAccess = access }
    }

    // MARK: - Rules

    /// Uses the downloaded rules where they're good, and the bundled ones otherwise. Downloads are
    /// checked before they're saved, and the bundled copies are part of the build, so rules that
    /// don't load mean a broken build.
    private static func loadRules(from downloader: RuleDownloader, exceptedSites: [String]) -> (LinkCleaner, [RuleSource: RuleStatus]) {
        func load(_ source: RuleSource) -> (data: Data, downloaded: Date?) {
            if let saved = downloader.saved(source) { return (saved.data, saved.date) }
            return (try! Data(contentsOf: AppFiles.bundledRules(source.fileName)), nil)
        }
        let list = load(.adGuard)
        let clearURLsFile = load(.clearURLs)
        let parameters = TrackingParameterRules(list: String(decoding: list.data, as: UTF8.self))
        let clearURLs = try! ClearURLsRules(data: clearURLsFile.data)
        let cleaner = LinkCleaner(parameters: parameters, clearURLs: clearURLs, exceptedSites: Set(exceptedSites))
        return (cleaner, [
            .adGuard: RuleStatus(ruleCount: parameters.ruleCount, downloaded: list.downloaded),
            .clearURLs: RuleStatus(ruleCount: clearURLs.parameterRuleCount + clearURLs.redirectRuleCount, downloaded: clearURLsFile.downloaded),
        ])
    }

    private func updateRulesIfDue() {
        guard updatesRulesAutomatically else { return }
        let oldest = RuleSource.allCases.map { ruleStatus[$0]?.downloaded ?? .distantPast }.min() ?? .distantPast
        if Date.now.timeIntervalSince(oldest) >= Self.ruleMaximumAge {
            updateRules()
        }
    }

    func updateRules() {
        guard ruleUpdateState != .updating else { return }
        ruleUpdateState = .updating
        Task {
            var failed = false
            for source in RuleSource.allCases {
                do {
                    _ = try await downloader.download(source)
                } catch {
                    log.error("Couldn't update \(source.rawValue): \(error.localizedDescription)")
                    failed = true
                }
            }
            (cleaner, ruleStatus) = Self.loadRules(from: downloader, exceptedSites: exceptedSites)
            ruleUpdateState = failed ? .failed : .idle
        }
    }

    var rulesLastUpdated: Date? {
        RuleSource.allCases.compactMap { ruleStatus[$0]?.downloaded }.min()
    }
}
