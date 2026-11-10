import AppKit
import SwiftUI
import AirTrafficCore

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let store = Store()
    private let picker = Picker()
    private var hotKey: HotKey?
    private var hotKeySpec = ""
    private var statusItem: NSStatusItem?
    private var settings: NSWindow?

    /// The browser last picked per host, so ↵ in the picker repeats your habit.
    private var lastPick: [String: String] {
        get { UserDefaults.standard.dictionary(forKey: "lastPick") as? [String: String] ?? [:] }
        set { UserDefaults.standard.set(newValue, forKey: "lastPick") }
    }

    // Not didFinishLaunching: on a cold launch by a link, AppKit delivers the link before that.
    func applicationWillFinishLaunching(_ notification: Notification) {
        store.browsers = Browsers.discover()
        store.onChange = { [weak self] in self?.apply() }
        picker.parse = { [weak self] in Links.fromInput($0, search: self?.store.config.search ?? "") }
        picker.preselect = { [weak self] in self?.suggestion(for: $0) }
        picker.onChoose = { [weak self] in self?.picked($0, $1, save: $2, priv: $3) }
        apply()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        if store.firstRun { showSettings() }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
        showSettings()
        return false
    }

    // MARK: Links in

    func application(_ application: NSApplication, open urls: [URL]) {
        let source = senderBundleID()
        let force = NSEvent.modifierFlags.contains(.option)
        store.reloadIfChanged()
        var unmatched: [URL] = []
        for url in urls.compactMap(resolveWebloc) {
            switch route(url, from: source, forcePicker: force, config: store.config, isInstalled: Browsers.isInstalled) {
            case let .open(url, target): Browsers.open(url, target)
            case let .pick(url): unmatched.append(url)
            }
        }
        // Several links at once (Mail, Finder): one pick sends them all.
        if !unmatched.isEmpty { picker.show(unmatched, choices: store.choices) }
    }

    /// The app that sent the link (Slack, Mail, …), for `from` rules.
    private func senderBundleID() -> String? {
        guard let event = NSAppleEventManager.shared().currentAppleEvent,
              let pid = event.attributeDescriptor(forKeyword: AEKeyword(keySenderPIDAttr))?.int32Value, pid > 0
        else { return nil }
        return NSRunningApplication(processIdentifier: pid)?.bundleIdentifier
    }

    private func resolveWebloc(_ url: URL) -> URL? {
        guard url.isFileURL, url.pathExtension == "webloc" else { return url }
        let plist = (try? Data(contentsOf: url)).flatMap { try? PropertyListSerialization.propertyList(from: $0, format: nil) }
        return ((plist as? [String: Any])?["URL"] as? String).flatMap(URL.init(string:))
    }

    // MARK: Picker

    private func suggestion(for url: URL) -> Target? {
        if let rule = store.config.rules.first(where: { $0.matches(url, from: nil) }) { return rule.target }
        if let host = Links.host(url), let id = lastPick[host], let c = store.choices.first(where: { $0.id == id }) { return c.target }
        return store.config.fallback
    }

    private func picked(_ urls: [URL], _ choice: Choice, save: Bool, priv: Bool) {
        var target = choice.target
        if priv { target.isPrivate = true }
        for url in urls {
            Browsers.open(url, target)
            guard let host = Links.host(url) else { continue }
            lastPick[host] = choice.id
            if save { store.config.setRule(match: host, target: target) }
        }
    }

    @objc private func showLauncher() {
        store.reloadIfChanged()
        let clip = NSPasteboard.general.string(forType: .string) ?? ""
        let prefill = Links.webURL(clip) != nil ? clip.trimmingCharacters(in: .whitespacesAndNewlines) : ""
        picker.showLauncher(prefill: prefill, choices: store.choices)
    }

    // MARK: Config-driven bits

    private func apply() {
        if store.config.hotkey != hotKeySpec {
            hotKeySpec = store.config.hotkey
            hotKey?.unregister()
            hotKey = HotKey(hotKeySpec) { [weak self] in self?.showLauncher() }
            if hotKey == nil { NSLog("Air Traffic: could not register hotkey \(hotKeySpec)") }
        }

        if store.config.menuBarIcon, statusItem == nil {
            let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
            item.button?.image = NSImage(systemSymbolName: "airplane", accessibilityDescription: "Air Traffic")
            let menu = NSMenu()
            menu.addItem(withTitle: "Open Link…", action: #selector(showLauncher), keyEquivalent: "").target = self
            menu.addItem(withTitle: "Settings…", action: #selector(showSettings), keyEquivalent: ",").target = self
            menu.addItem(.separator())
            menu.addItem(withTitle: "Quit Air Traffic", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
            item.menu = menu
            statusItem = item
        } else if !store.config.menuBarIcon, let item = statusItem {
            NSStatusBar.system.removeStatusItem(item)
            statusItem = nil
        }
    }

    @objc private func showSettings() {
        store.reloadIfChanged()
        store.browsers = Browsers.discover()
        if settings == nil {
            let window = NSWindow(contentViewController: NSHostingController(rootView: SettingsView(store: store)))
            window.title = "Air Traffic"
            window.styleMask = [.titled, .closable]
            window.isReleasedWhenClosed = false
            window.center()
            settings = window
        }
        NSApp.activate()
        settings?.makeKeyAndOrderFront(nil)
    }
}
