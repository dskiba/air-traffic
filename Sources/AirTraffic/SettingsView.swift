import SwiftUI
import ServiceManagement
import AirTrafficCore

/// The only real window. Opened on first launch, by reopening the app, or from the menu bar icon.
struct SettingsView: View {
    @Bindable var store: Store
    @State private var isDefault = Browsers.isDefault
    @State private var login = SMAppService.mainApp.status == .enabled
    @State private var newMatch = ""
    @State private var newTarget = ""

    var body: some View {
        Form {
            Section {
                HStack(spacing: 12) {
                    Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 44, height: 44)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Air Traffic").font(.title3.weight(.semibold))
                        Text("Every link, cleared for the right browser.").foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text("v\(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev")")
                        .foregroundStyle(.tertiary).monospacedDigit()
                }
            }
            Section {
                LabeledContent("Default browser") {
                    if isDefault {
                        Label("Air Traffic", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                    } else {
                        Button("Make Default") { Task { await Browsers.makeDefault(); isDefault = Browsers.isDefault } }
                            .buttonStyle(.borderedProminent)
                    }
                }
                if Browsers.profilesBlocked {
                    LabeledContent {
                        Button("Allow Access…") {
                            NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_FilesAndFolders")!)
                        }
                    } label: {
                        Text("Browser profiles")
                        Text("macOS blocks reading profile lists until you allow Air Traffic in Files & Folders.")
                    }
                }
                Toggle("Open at login", isOn: $login)
                    .onChange(of: login) { _, on in
                        if on { try? SMAppService.mainApp.register() } else { try? SMAppService.mainApp.unregister() }
                        login = SMAppService.mainApp.status == .enabled
                    }
                Toggle("Show in menu bar", isOn: $store.config.menuBarIcon)
                SwiftUI.Picker("When no rule matches", selection: fallback) {
                    Text("Ask").tag("")
                    Divider()
                    ForEach(store.choices) { Text($0.name).tag($0.id) }
                }
            }
            Section {
                Toggle("Remove trackers and unwrap redirect links", isOn: $store.config.cleanURLs)
                Toggle("Open Zoom, Teams, Figma, Spotify, Notion and Linear links in their apps", isOn: $store.config.openInApps)
                LabeledContent("Open-link shortcut", value: Self.pretty(store.config.hotkey))
            } header: {
                Text("Links")
            }
            Section {
                ForEach(Array(store.config.rules.enumerated()), id: \.offset) { i, rule in
                    HStack {
                        Text(rule.match ?? "Any link").fontWeight(.medium)
                        if let from = rule.from { Text("from \(from)").foregroundStyle(.secondary) }
                        Spacer()
                        Text(name(of: rule.target)).foregroundStyle(.secondary)
                        Button("Remove", systemImage: "minus.circle.fill") { store.config.rules.remove(at: i) }
                            .labelStyle(.iconOnly).buttonStyle(.borderless).foregroundStyle(.secondary)
                    }
                }
                HStack {
                    TextField("Add rule", text: $newMatch, prompt: Text("example.com or example.com/path"))
                        .labelsHidden()
                        .onSubmit(addRule)
                    SwiftUI.Picker("Open in", selection: $newTarget) {
                        ForEach(store.choices) { Text($0.name).tag($0.id) }
                    }
                    .labelsHidden().fixedSize()
                    Button("Add", action: addRule).disabled(cleaned(newMatch).isEmpty)
                }
            } header: {
                Text("Rules")
            } footer: {
                Text("Tip: in the picker, hold ⌘ while choosing to add a rule. Hold ⌥ while clicking any link to always see the picker.")
                    .foregroundStyle(.secondary)
            }
            Section("Browsers in picker") {
                ForEach(store.browsers) { b in
                    Toggle(isOn: visible(b.id)) {
                        Label { Text(b.name) } icon: { Image(nsImage: b.icon).resizable().frame(width: 18, height: 18) }
                    }
                }
            }
            HStack {
                Button("Edit config.json…") { NSWorkspace.shared.open(Store.fileURL) }
                Spacer()
                Button("Quit Air Traffic") { NSApp.terminate(nil) }
            }
        }
        .formStyle(.grouped)
        .frame(width: 520, height: 660)
        .onAppear { if newTarget.isEmpty { newTarget = store.choices.first?.id ?? "" } }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) { note in
            guard !(note.object is NSPanel) else { return }
            isDefault = Browsers.isDefault
            login = SMAppService.mainApp.status == .enabled
        }
    }

    private func addRule() {
        let match = cleaned(newMatch)
        guard !match.isEmpty, let choice = store.choices.first(where: { $0.id == newTarget }) else { return }
        store.config.setRule(match: match, target: choice.target)
        newMatch = ""
    }

    /// "https://www.Figma.com/" → "figma.com".
    private func cleaned(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            .replacingOccurrences(of: "^[a-z]+://(www\\.)?", with: "", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    }

    private var fallback: Binding<String> {
        Binding(
            get: { store.config.fallback.map { $0.app + "/" + ($0.profile ?? "") } ?? "" },
            set: { id in store.config.fallback = store.choices.first { $0.id == id }?.target }
        )
    }

    private func visible(_ id: String) -> Binding<Bool> {
        Binding(
            get: { !store.config.hide.contains(id) },
            set: { on in if on { store.config.hide.removeAll { $0 == id } } else { store.config.hide.append(id) } }
        )
    }

    private func name(of target: Target) -> String {
        let name = store.browsers.flatMap(\.choices)
            .first { $0.target.app == target.app && $0.target.profile == target.profile }?.name
            ?? store.browsers.first { $0.id == target.app }?.name ?? target.app
        return target.isPrivate == true ? "\(name) (private)" : name
    }

    /// "ctrl+opt+space" → "⌃⌥Space".
    static func pretty(_ hotkey: String) -> String {
        let symbols = ["cmd": "⌘", "command": "⌘", "opt": "⌥", "option": "⌥", "alt": "⌥", "ctrl": "⌃", "control": "⌃", "shift": "⇧"]
        return hotkey.lowercased().split(separator: "+").map { part in
            symbols[String(part)] ?? (part == "space" ? "Space" : part.uppercased())
        }.joined()
    }
}
