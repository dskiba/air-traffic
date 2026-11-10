import Foundation

/// Where a link goes: an app (bundle id), optionally a browser profile and/or a private window.
public struct Target: Codable, Hashable, Sendable {
    public var app: String
    /// Chromium: profile directory ("Default", "Profile 1"). Firefox/Zen: profile name.
    public var profile: String?
    public var isPrivate: Bool?

    enum CodingKeys: String, CodingKey { case app, profile, isPrivate = "private" }

    public init(app: String, profile: String? = nil, isPrivate: Bool? = nil) {
        self.app = app
        self.profile = profile
        self.isPrivate = isPrivate
    }
}

/// `{"match": "figma.com", "from": "com.tinyspeck.slackmacgap", "app": "com.brave.Browser", "profile": "Profile 1"}`
/// Every condition given must hold. `match` is a domain (subdomains included) or a domain + path prefix.
public struct Rule: Codable, Equatable, Sendable {
    public var match: String?
    public var from: String?
    public var target: Target

    enum CodingKeys: String, CodingKey { case match, from }

    public init(match: String? = nil, from: String? = nil, target: Target) {
        self.match = match
        self.from = from
        self.target = target
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        match = try c.decodeIfPresent(String.self, forKey: .match)
        from = try c.decodeIfPresent(String.self, forKey: .from)
        target = try Target(from: decoder)
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encodeIfPresent(match, forKey: .match)
        try c.encodeIfPresent(from, forKey: .from)
        try target.encode(to: encoder)
    }

    public func matches(_ url: URL, from source: String?) -> Bool {
        if let from, from != source { return false }
        guard let match = match?.lowercased(), !match.isEmpty else { return true }
        guard let host = Links.host(url) else { return false }
        let (domain, path) = match.firstIndex(of: "/").map { (String(match[..<$0]), String(match[$0...])) } ?? (match, "/")
        let d = domain.hasPrefix("www.") ? String(domain.dropFirst(4)) : domain
        guard host == d || host.hasSuffix("." + d) else { return false }
        // Whole segments only: "github.com/acme" matches /acme and /acme/x, not /acme-evil.
        let p = url.path(percentEncoded: false).lowercased()
        return path == "/" || p == path || p.hasPrefix(path.hasSuffix("/") ? path : path + "/")
    }
}

public struct Config: Codable, Equatable, Sendable {
    /// Used when no rule matches. `nil` shows the picker.
    public var fallback: Target?
    public var rules: [Rule] = []
    /// Bundle ids hidden from the picker.
    public var hide: [String] = []
    public var cleanURLs = true
    public var openInApps = true
    public var hotkey = "ctrl+opt+space"
    public var search = "https://duckduckgo.com/?q=%s"
    public var menuBarIcon = false

    public init() {}

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = Config()
        fallback = try c.decodeIfPresent(Target.self, forKey: .fallback)
        rules = try c.decodeIfPresent([Rule].self, forKey: .rules) ?? d.rules
        hide = try c.decodeIfPresent([String].self, forKey: .hide) ?? d.hide
        cleanURLs = try c.decodeIfPresent(Bool.self, forKey: .cleanURLs) ?? d.cleanURLs
        openInApps = try c.decodeIfPresent(Bool.self, forKey: .openInApps) ?? d.openInApps
        hotkey = try c.decodeIfPresent(String.self, forKey: .hotkey) ?? d.hotkey
        search = try c.decodeIfPresent(String.self, forKey: .search) ?? d.search
        menuBarIcon = try c.decodeIfPresent(Bool.self, forKey: .menuBarIcon) ?? d.menuBarIcon
    }

    /// "Always open <match> here": replaces a rule for the same match and puts it first,
    /// so it wins over broader rules further down.
    public mutating func setRule(match: String, target: Target) {
        rules.removeAll { $0.match == match && $0.from == nil }
        rules.insert(Rule(match: match, target: target), at: 0)
    }

    public static func decode(_ data: Data) throws -> Config {
        try JSONDecoder().decode(Config.self, from: data)
    }

    public func encoded() throws -> Data {
        let e = JSONEncoder()
        e.outputFormatting = [.prettyPrinted, .withoutEscapingSlashes]
        return try e.encode(self)
    }
}
