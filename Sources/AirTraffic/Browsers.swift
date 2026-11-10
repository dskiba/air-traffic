import AppKit
import SQLite3
import AirTrafficCore

/// One tile in the picker: a browser, or one profile of a browser.
struct Choice: Identifiable {
    let target: Target
    /// "Safari", "Brave · Work".
    let name: String
    let icon: NSImage
    /// Profile initial + color, drawn on the icon so two profiles of one browser are told apart.
    let badge: (letter: String, color: NSColor)?
    var id: String { target.app + "/" + (target.profile ?? "") }
}

struct Browser: Identifiable {
    let id: String
    let name: String
    let icon: NSImage
    let choices: [Choice]
}

private struct Profile {
    let id: String
    let name: String
    var color: NSColor?
}

enum Browsers {
    /// Chromium family: bundle id → folder in ~/Library/Application Support (profiles in "Local State").
    static let chromium: [String: String] = [
        "com.google.Chrome": "Google/Chrome",
        "com.google.Chrome.beta": "Google/Chrome Beta",
        "com.google.Chrome.dev": "Google/Chrome Dev",
        "com.google.Chrome.canary": "Google/Chrome Canary",
        "com.google.chrome.for.testing": "Google/Chrome for Testing",
        "com.brave.Browser": "BraveSoftware/Brave-Browser",
        "com.brave.Browser.beta": "BraveSoftware/Brave-Browser-Beta",
        "com.brave.Browser.nightly": "BraveSoftware/Brave-Browser-Nightly",
        "com.microsoft.edgemac": "Microsoft Edge",
        "com.microsoft.edgemac.Beta": "Microsoft Edge Beta",
        "com.microsoft.edgemac.Dev": "Microsoft Edge Dev",
        "com.microsoft.edgemac.Canary": "Microsoft Edge Canary",
        "com.vivaldi.Vivaldi": "Vivaldi",
        "org.chromium.Chromium": "Chromium",
    ]
    /// Firefox family: bundle id → data folder (profiles.ini and "Profile Groups").
    static let firefox: [String: String] = [
        "org.mozilla.firefox": "Firefox",
        "org.mozilla.firefoxdeveloperedition": "Firefox",
        "org.mozilla.nightly": "Firefox",
        "app.zen-browser.zen": "zen",
    ]

    static let support = FileManager.default.homeDirectoryForCurrentUser.appending(path: "Library/Application Support")
    private static let palette: [NSColor] = [.systemBlue, .systemOrange, .systemGreen, .systemPink, .systemPurple, .systemTeal, .systemIndigo]

    /// Set when macOS (27+) blocks reading a browser's profile list; Settings offers to fix it.
    static var profilesBlocked = false

    static func discover() -> [Browser] {
        let me = Bundle.main.bundleIdentifier
        // Real browsers open web pages *and* HTML files; apps that merely grab links (ChatGPT, editors) don't.
        let html = Set(NSWorkspace.shared.urlsForApplications(toOpen: .html))
        profilesBlocked = false
        var seen = Set<String>()
        return NSWorkspace.shared.urlsForApplications(toOpen: URL(string: "https://example.com")!)
            .compactMap { url -> Browser? in
                guard html.contains(url), let id = Bundle(url: url)?.bundleIdentifier, id != me, seen.insert(id).inserted else { return nil }
                let name = FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: "")
                let short = name.replacingOccurrences(of: "^(Google|Microsoft) | Browser$", with: "", options: .regularExpression)
                let icon = NSWorkspace.shared.icon(forFile: url.path)
                let profiles = profiles(for: id)
                let choices = profiles.count > 1
                    ? profiles.enumerated().map { i, p in
                        Choice(target: Target(app: id, profile: p.id), name: "\(short) · \(p.name)", icon: icon,
                               badge: (String(p.name.prefix(1)).uppercased(), p.color ?? palette[i % palette.count]))
                    }
                    : [Choice(target: Target(app: id), name: short, icon: icon, badge: nil)]
                return Browser(id: id, name: name, icon: icon, choices: choices)
            }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    private static func profiles(for id: String) -> [Profile] {
        if let dir = chromium[id] { return chromiumProfiles(support.appending(path: dir)) }
        if let dir = firefox[id] { return firefoxProfiles(support.appending(path: dir)) }
        return []
    }

    /// `Local State` → profile.info_cache, in the browser's own order. Profile id = directory ("Profile 1").
    private static func chromiumProfiles(_ root: URL) -> [Profile] {
        guard let data = read(root.appending(path: "Local State")),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let profile = json["profile"] as? [String: Any],
              let cache = profile["info_cache"] as? [String: [String: Any]] else { return [] }
        let order = (profile["profiles_order"] as? [String])?.filter { cache[$0] != nil } ?? cache.keys.sorted()
        return order.map { dir in
            let info = cache[dir] ?? [:]
            let color = (info["profile_highlight_color"] as? Int).map { argb -> NSColor in
                let v = UInt32(truncatingIfNeeded: argb)
                return NSColor(srgbRed: CGFloat(v >> 16 & 0xFF) / 255, green: CGFloat(v >> 8 & 0xFF) / 255, blue: CGFloat(v & 0xFF) / 255, alpha: 1)
            }
            return Profile(id: dir, name: info["name"] as? String ?? dir, color: color)
        }
    }

    /// New profile system (Profile Groups/*.sqlite, table Profiles) plus legacy profiles.ini.
    /// Profile id = absolute profile folder, opened with `--profile`.
    private static func firefoxProfiles(_ root: URL) -> [Profile] {
        func absolute(_ path: String) -> String { path.hasPrefix("/") ? path : root.appending(path: path).path }
        var list: [Profile] = []

        let groups = root.appending(path: "Profile Groups")
        let dbs = (try? FileManager.default.contentsOfDirectory(at: groups, includingPropertiesForKeys: nil)) ?? []
        for db in dbs where db.pathExtension == "sqlite" {
            var handle: OpaquePointer?
            var statement: OpaquePointer?
            defer { sqlite3_finalize(statement); sqlite3_close(handle) }
            guard sqlite3_open_v2(db.path, &handle, SQLITE_OPEN_READONLY, nil) == SQLITE_OK,
                  sqlite3_prepare_v2(handle, "SELECT path, name FROM Profiles", -1, &statement, nil) == SQLITE_OK else { continue }
            while sqlite3_step(statement) == SQLITE_ROW {
                guard let path = sqlite3_column_text(statement, 0), let name = sqlite3_column_text(statement, 1) else { continue }
                list.append(Profile(id: absolute(String(cString: path)), name: String(cString: name)))
            }
        }

        if let data = read(root.appending(path: "profiles.ini")), let ini = String(data: data, encoding: .utf8) {
            var sections: [[String: String]] = []
            for line in ini.split(whereSeparator: \.isNewline).map({ $0.trimmingCharacters(in: .whitespaces) }) {
                if line.hasPrefix("[") {
                    sections.append(line.hasPrefix("[Profile") ? [:] : ["skip": ""])
                } else if let eq = line.firstIndex(of: "="), !sections.isEmpty {
                    sections[sections.count - 1][String(line[..<eq])] = String(line[line.index(after: eq)...])
                }
            }
            for keys in sections where keys["skip"] == nil {
                guard let name = keys["Name"], let path = keys["Path"] else { continue }
                let id = keys["IsRelative"] == "0" ? path : absolute(path)
                if !list.contains(where: { $0.id == id }) { list.append(Profile(id: id, name: name)) }
            }
        }
        return list
    }

    private static func read(_ url: URL) -> Data? {
        do { return try Data(contentsOf: url) } catch {
            if (error as? CocoaError)?.code == .fileReadNoPermission { profilesBlocked = true }
            return nil
        }
    }

    /// Only browsers we can pass a private-window flag to.
    static func supportsPrivate(_ app: String) -> Bool { chromium[app] != nil || firefox[app] != nil }

    static func isInstalled(_ id: String) -> Bool {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) != nil
    }

    static func open(_ url: URL, _ target: Target) {
        guard let app = NSWorkspace.shared.urlForApplication(withBundleIdentifier: target.app) else {
            NSSound.beep()
            return
        }
        let config = NSWorkspace.OpenConfiguration()
        let priv = target.isPrivate == true
        var args: [String] = []
        if chromium[target.app] != nil {
            if let p = target.profile { args.append("--profile-directory=\(p)") }
            if priv { args.append("--incognito") }
        } else if firefox[target.app] != nil {
            if let p = target.profile { args += ["--profile", p] }
            if priv { args.append("--private-window") }
        }
        if args.isEmpty {
            NSWorkspace.shared.open([url], withApplicationAt: app, configuration: config)
        } else {
            // A second instance with arguments hands them to the running browser and exits.
            config.createsNewApplicationInstance = true
            config.arguments = args + [url.isFileURL ? url.path : url.absoluteString]
            NSWorkspace.shared.openApplication(at: app, configuration: config)
        }
    }

    static var isDefault: Bool {
        guard let handler = NSWorkspace.shared.urlForApplication(toOpen: URL(string: "https://example.com")!) else { return false }
        return Bundle(url: handler)?.bundleIdentifier == Bundle.main.bundleIdentifier
    }

    /// macOS asks the user to confirm.
    static func makeDefault() async {
        for scheme in ["http", "https"] where !isDefault {
            try? await NSWorkspace.shared.setDefaultApplication(at: Bundle.main.bundleURL, toOpenURLsWithScheme: scheme)
        }
    }
}
