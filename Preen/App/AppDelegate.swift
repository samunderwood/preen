// SPDX-License-Identifier: GPL-3.0-or-later

import AppIntents
import AppKit
import SamKit
import SamKitUpdates
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let model = AppModel()
    private var statusItemController: StatusItemController?
    private var settingsWindow: SettingsWindowController!
    private var serviceProvider: ServiceProvider?
    private var showsWelcome = false

    override init() {
        super.init()
        // Registered before launching finishes, for a Shortcuts action that launches Preen.
        let model = model
        AppDependencyManager.shared.add(dependency: model)
    }

    func applicationWillFinishLaunching(_ notification: Notification) {
        SingleInstance.handOffToRunningCopy()
        NSApp.setActivationPolicy(.accessory)
        // Before the menu starts the updater, which writes preferences and would make a first
        // install look like an update.
        OnboardingWindow.showWhatsNewIfNeeded(appName: "Preen", tint: .preen)
        showsWelcome = WelcomeLaunch.isPending()
        NSApp.mainMenu = MainMenu.make(target: self)
        settingsWindow = SettingsWindowController(width: 680, height: 520, minHeight: 420) { [model] in
            SettingsView().environment(model)
        }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        model.start()
        statusItemController = StatusItemController(model: model) { [weak self] tab in
            self?.showSettings(tab)
        }
        serviceProvider = ServiceProvider(model: model)
        NSApp.servicesProvider = serviceProvider
        Updater.shared.tint = .preen
        Feedback.prepare()

        if showsWelcome {
            PreenWelcome.show(model: model)
        }
    }

    /// Opening Preen again from Finder or Spotlight shows Settings.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        settingsWindow.handleReopen()
    }

    @objc func openSettings(_ sender: Any?) {
        showSettings()
    }

    @objc func showAbout(_ sender: Any?) {
        showSettings(.about)
    }

    private func showSettings(_ tab: SettingsTab? = nil) {
        if let tab {
            SettingsNavigation.shared.selectedTab = tab
        }
        settingsWindow.show()
    }
}

/// The menu bar shown while a Preen window, such as Settings, is frontmost.
private enum MainMenu {
    static func make(target: AppDelegate) -> NSMenu {
        let main = NSMenu()

        let app = NSMenu()
        app.addItem(withTitle: "About Preen", action: #selector(AppDelegate.showAbout(_:)), keyEquivalent: "").target = target
        app.addItem(withTitle: "Check for Updates…", action: #selector(Updater.checkForUpdates(_:)), keyEquivalent: "").target = Updater.shared
        app.addItem(.separator())
        app.addItem(withTitle: "Settings…", action: #selector(AppDelegate.openSettings(_:)), keyEquivalent: ",").target = target
        app.addItem(.separator())
        let services = NSMenu()
        app.addItem(submenu: services, title: "Services")
        NSApp.servicesMenu = services
        app.addItem(.separator())
        app.addItem(withTitle: "Hide Preen", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        app.addItem(.separator())
        app.addItem(withTitle: "Quit Preen", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        main.addItem(submenu: app, title: "Preen")

        let edit = NSMenu(title: "Edit")
        edit.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        edit.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "Z")
        edit.addItem(.separator())
        edit.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        main.addItem(submenu: edit, title: "Edit")

        let window = NSMenu(title: "Window")
        window.addItem(withTitle: "Close", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        window.addItem(withTitle: "Minimize", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        main.addItem(submenu: window, title: "Window")
        NSApp.windowsMenu = window

        return main
    }
}

private extension NSMenu {
    func addItem(submenu: NSMenu, title: String) {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.submenu = submenu
        addItem(item)
    }
}
