// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import SamKit
import SamKitUpdates

/// The menu bar item and its menu. The menu is rebuilt each time it opens and whenever the model
/// changes while it's open.
final class StatusItemController: NSObject, NSMenuDelegate {
    private let model: AppModel
    private let showSettings: (SettingsTab?) -> Void
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let menu = NSMenu()
    private var isMenuOpen = false
    private var shownCleanCount = 0
    private var tickReset: Task<Void, Never>?

    private static let pauseEnd: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        formatter.doesRelativeDateFormatting = true
        return formatter
    }()

    init(model: AppModel, showSettings: @escaping (SettingsTab?) -> Void) {
        self.model = model
        self.showSettings = showSettings
        super.init()
        statusItem.button?.image = StatusIcon.feather
        statusItem.button.map(DevelopmentBuild.mark)
        menu.delegate = self
        menu.autoenablesItems = false
        statusItem.menu = menu
        shownCleanCount = model.cleanCount
        observeModel()
    }

    private func observeModel() {
        withObservationTracking {
            refreshButton()
            _ = (model.history, model.pausedUntil, model.exceptedSites, model.clipboardAccess)
            _ = Updater.shared.waitingVersion
            if isMenuOpen { rebuildMenu() }
        } onChange: { [weak self] in
            Task { @MainActor in self?.observeModel() }
        }
    }

    private func refreshButton() {
        guard let button = statusItem.button else { return }
        button.appearsDisabled = model.isPaused
        button.setAccessibilityLabel(model.isPaused ? "Preen, paused" : "Preen")
        if model.cleanCount != shownCleanCount {
            shownCleanCount = model.cleanCount
            showTick()
        }
    }

    /// The feather turns into a tick for a moment, so a clean doesn't go unnoticed.
    private func showTick() {
        guard let button = statusItem.button else { return }
        setImage(StatusIcon.cleaned, on: button)
        tickReset?.cancel()
        tickReset = Task {
            try? await Task.sleep(for: .seconds(1.2))
            guard !Task.isCancelled else { return }
            setImage(StatusIcon.feather, on: button)
        }
    }

    private func setImage(_ image: NSImage, on button: NSStatusBarButton) {
        button.wantsLayer = true
        let fade = CATransition()
        fade.type = .fade
        fade.duration = 0.18
        fade.timingFunction = CAMediaTimingFunction(name: .easeOut)
        button.layer?.add(fade, forKey: "image")
        button.image = image
    }

    // MARK: - NSMenuDelegate

    func menuNeedsUpdate(_ menu: NSMenu) {
        rebuildMenu()
    }

    func menuWillOpen(_ menu: NSMenu) {
        isMenuOpen = true
        model.refreshClipboardAccess()
    }

    func menuDidClose(_ menu: NSMenu) {
        isMenuOpen = false
    }

    // MARK: - Menu

    private func rebuildMenu() {
        menu.removeAllItems()

        if let version = Updater.shared.waitingVersion {
            menu.addItem(updateItem("Update to Preen \(version)…"))
            menu.addItem(.separator())
        }

        if let notice = clipboardAccessNotice {
            let warning = item(notice, action: #selector(openClipboardSettings))
            warning.image = NSImage(systemSymbolName: "exclamationmark.triangle.fill", accessibilityDescription: "Warning")?
                .withSymbolConfiguration(.preferringMulticolor())
            menu.addItem(warning)
            menu.addItem(.separator())
        }

        if let event = model.lastClean {
            menu.addItem(.sectionHeader(title: "Last Cleaned"))
            menu.addItem(eventItem(event))
            let restore = item("Restore Original", action: #selector(restore(_:)))
            restore.representedObject = event.id
            menu.addItem(restore)
            if let site = event.site, !model.isExcepted(site: site) {
                let never = item("Never Clean Links from \(site)", action: #selector(neverClean(_:)))
                never.representedObject = event.id
                menu.addItem(never)
            }
            if model.history.count > 1 {
                menu.addItem(recentItem())
            }
        } else {
            menu.addItem(status("Links you copy are cleaned here"))
        }

        menu.addItem(.separator())
        if let pausedUntil = model.pausedUntil {
            menu.addItem(status(pausedUntil == .distantFuture ? "Paused" : "Paused until \(Self.pauseEnd.string(from: pausedUntil))"))
            menu.addItem(item("Resume Cleaning", action: #selector(resume)))
        } else {
            menu.addItem(pauseItem())
        }
        menu.addItem(item("Clean Clipboard Now", action: #selector(cleanNow)))

        menu.addItem(.separator())
        menu.addItem(item("Settings…", action: #selector(openSettings), key: ","))
        menu.addItem(updateItem("Check for Updates…"))
        menu.addItem(NSMenuItem(title: "Quit Preen", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
    }

    private var clipboardAccessNotice: String? {
        switch model.clipboardAccess {
        case .alwaysDeny: "Clipboard Access Is Off…"
        case .ask: "Allow Clipboard Access…"
        default: nil
        }
    }

    /// Choosing the link copies the clean version again.
    private func eventItem(_ event: CleanEvent) -> NSMenuItem {
        let item = item(Self.displayText(of: event), action: #selector(copyCleaned(_:)))
        item.subtitle = Self.summary(of: event)
        item.representedObject = event.id
        item.toolTip = event.cleaned
        return item
    }

    private func recentItem() -> NSMenuItem {
        let submenu = NSMenu()
        for event in model.history.dropFirst() {
            let options = NSMenu()
            let copyClean = item("Copy Clean Link", action: #selector(copyCleaned(_:)))
            copyClean.representedObject = event.id
            options.addItem(copyClean)
            let copyOriginal = item("Copy Original", action: #selector(restore(_:)))
            copyOriginal.representedObject = event.id
            options.addItem(copyOriginal)

            let entry = NSMenuItem(title: Self.displayText(of: event), action: nil, keyEquivalent: "")
            entry.subtitle = Self.summary(of: event)
            entry.submenu = options
            submenu.addItem(entry)
        }
        let recent = NSMenuItem(title: "Recent", action: nil, keyEquivalent: "")
        recent.submenu = submenu
        return recent
    }

    private func pauseItem() -> NSMenuItem {
        let submenu = NSMenu()
        for duration in AppModel.PauseDuration.allCases {
            let option = item(duration.title, action: #selector(pause(_:)))
            option.representedObject = duration
            submenu.addItem(option)
        }
        let pause = NSMenuItem(title: "Pause", action: nil, keyEquivalent: "")
        pause.submenu = submenu
        return pause
    }

    /// The clean link without its scheme, shortened in the middle so the site and the end both show.
    static func displayText(of event: CleanEvent) -> String {
        guard event.links.count == 1, let link = event.links.first else {
            return "\(event.links.count) links"
        }
        var text = link.cleaned
        for prefix in ["https://", "http://"] where text.lowercased().hasPrefix(prefix) {
            text = String(text.dropFirst(prefix.count))
        }
        if text.hasPrefix("www.") { text = String(text.dropFirst(4)) }
        guard text.count > 48 else { return text }
        return text.prefix(32) + "…" + text.suffix(15)
    }

    static func summary(of event: CleanEvent) -> String {
        var parts: [String] = []
        if let wrapper = event.unwrappedHosts.first {
            parts.append("Unwrapped from \(wrapper.hasPrefix("www.") ? String(wrapper.dropFirst(4)) : wrapper)")
        }
        let removed = event.removedParameters
        if !removed.isEmpty {
            let shown = removed.prefix(4).joined(separator: ", ")
            let more = removed.count > 4 ? " and \(removed.count - 4) more" : ""
            parts.append((parts.isEmpty ? "Removed " : "removed ") + shown + more)
        }
        return parts.joined(separator: ", ")
    }

    private func event(for sender: NSMenuItem) -> CleanEvent? {
        guard let id = sender.representedObject as? UUID else { return nil }
        return model.history.first { $0.id == id }
    }

    private func item(_ title: String, action: Selector, key: String = "") -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = self
        return item
    }

    /// The menu doesn't enable items itself, so the updater is asked here.
    private func updateItem(_ title: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: #selector(Updater.checkForUpdates(_:)), keyEquivalent: "")
        item.target = Updater.shared
        item.isEnabled = Updater.shared.validateMenuItem(item)
        return item
    }

    private func status(_ title: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        return item
    }

    // MARK: - Actions

    @objc private func copyCleaned(_ sender: NSMenuItem) {
        event(for: sender).map(model.copyCleaned)
    }

    @objc private func restore(_ sender: NSMenuItem) {
        event(for: sender).map(model.restore)
    }

    @objc private func neverClean(_ sender: NSMenuItem) {
        event(for: sender).map(model.neverClean)
    }

    @objc private func pause(_ sender: NSMenuItem) {
        guard let duration = sender.representedObject as? AppModel.PauseDuration else { return }
        model.pause(duration)
    }

    @objc private func resume() {
        model.resume()
    }

    @objc private func cleanNow() {
        model.cleanClipboardNow()
    }

    @objc private func openClipboardSettings() {
        showSettings(.general)
    }

    @objc private func openSettings() {
        showSettings(nil)
    }
}
