// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import PreenCore
import SamKit
import SwiftUI
import UniformTypeIdentifiers

struct ExceptionsSettingsPane: View {
    @Environment(AppModel.self) private var model
    @State private var selectedSites: Set<String> = []
    @State private var selectedApps: Set<ExcludedApp> = []
    @State private var isAddingSite = false

    var body: some View {
        Form {
            Section {
                List(model.exceptedSites, id: \.self, selection: $selectedSites) { site in
                    Text(site)
                }
                .frame(minHeight: 140)
                .overlay {
                    if model.exceptedSites.isEmpty {
                        Text("Links to these sites, and their subdomains, are left as they are.")
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .padding()
                    }
                }
                .onDeleteCommand { removeSites() }
            } header: {
                Text("Sites")
            } footer: {
                ListButtons(add: { isAddingSite = true }, addLabel: "Add a site", remove: removeSites, removeLabel: "Remove the selected sites", canRemove: !selectedSites.isEmpty)
            }

            Section {
                List(model.excludedApps, selection: $selectedApps) { app in
                    Label {
                        Text(app.name)
                    } icon: {
                        AppIcon(bundleIdentifier: app.bundleIdentifier)
                    }
                    .tag(app)
                }
                .frame(minHeight: 140)
                .onDeleteCommand { removeApps() }
            } header: {
                Text("Apps")
                Text("Links copied from these apps are left as they are.")
            } footer: {
                ListButtons(add: chooseApps, addLabel: "Add an app", remove: removeApps, removeLabel: "Remove the selected apps", canRemove: !selectedApps.isEmpty)
            }
        }
        .settingsPaneStyle()
        .sheet(isPresented: $isAddingSite) {
            AddSiteSheet()
        }
    }

    private func removeSites() {
        selectedSites.forEach(model.removeException)
        selectedSites = []
    }

    private func removeApps() {
        selectedApps.forEach(model.removeExcludedApp)
        selectedApps = []
    }

    private func chooseApps() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.application]
        panel.allowsMultipleSelection = true
        panel.directoryURL = URL(filePath: "/Applications")
        panel.prompt = "Leave Alone"
        guard panel.runModal() == .OK else { return }
        for url in panel.urls {
            guard let bundle = Bundle(url: url), let identifier = bundle.bundleIdentifier else { continue }
            let name = FileManager.default.displayName(atPath: url.path).replacing(/\.app$/, with: "")
            model.addExcludedApp(ExcludedApp(bundleIdentifier: identifier, name: name))
        }
    }
}

/// The + and − under a list, as in System Settings.
private struct ListButtons: View {
    let add: () -> Void
    let addLabel: String
    let remove: () -> Void
    let removeLabel: String
    let canRemove: Bool

    var body: some View {
        HStack(spacing: 0) {
            Button(action: add) {
                Image(systemName: "plus").frame(width: 24, height: 20)
            }
            .help(addLabel)
            .accessibilityLabel(addLabel)
            Divider().frame(height: 16)
            Button(action: remove) {
                Image(systemName: "minus").frame(width: 24, height: 20)
            }
            .disabled(!canRemove)
            .help(removeLabel)
            .accessibilityLabel(removeLabel)
            Spacer()
        }
        .buttonStyle(.borderless)
    }
}

private struct AppIcon: View {
    let bundleIdentifier: String

    var body: some View {
        Image(nsImage: icon)
            .resizable()
            .frame(width: 18, height: 18)
    }

    private var icon: NSImage {
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier) {
            return NSWorkspace.shared.icon(forFile: url.path)
        }
        return NSWorkspace.shared.icon(for: .applicationBundle)
    }
}

private struct AddSiteSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var input = ""

    private var site: String? { Self.site(from: input) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Form {
                Section {
                    TextField("Site", text: $input, prompt: Text("example.com"))
                        .disableAutocorrection(true)
                } footer: {
                    Text("Preen won’t change links to this site or its subdomains.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .settingsPaneStyle()
            .scrollDisabled(true)

            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Add Site") {
                    if let site { model.addException(site) }
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(site == nil)
            }
            .padding([.horizontal, .bottom], 20)
        }
        .frame(width: 400)
    }

    /// The site in what was typed, which can be a whole link.
    static func site(from input: String) -> String? {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let host = LinkCleaner.host(of: trimmed.contains("://") ? trimmed : "https://" + trimmed) ?? ""
        let site = host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
        guard site.contains("."), !site.hasPrefix("."), !site.hasSuffix("."),
              site.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "." || $0 == "-" })
        else { return nil }
        return site
    }
}
