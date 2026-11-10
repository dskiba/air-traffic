import Foundation

public enum Links {
    /// Lowercased host without a leading "www.".
    public static func host(_ url: URL) -> String? {
        guard let h = url.host(percentEncoded: false)?.lowercased(), !h.isEmpty else { return nil }
        return h.hasPrefix("www.") ? String(h.dropFirst(4)) : h
    }

    public static func clean(_ url: URL) -> URL { strip(unwrap(url)) }

    // MARK: Redirect unwrapping

    /// Outlook SafeLinks, Google, Facebook, Instagram, YouTube and LinkedIn redirect wrappers.
    public static func unwrap(_ url: URL) -> URL {
        guard let c = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let host = c.host?.lowercased(), let items = c.queryItems else { return url }
        let path = c.path
        let keys: [String]
        if host.hasSuffix("safelinks.protection.outlook.com") {
            keys = ["url"]
        } else if (host.hasPrefix("www.google.") || host.hasPrefix("google.")) && path == "/url" {
            keys = ["q", "url"]
        } else if ["l.facebook.com", "lm.facebook.com", "l.messenger.com", "l.instagram.com"].contains(host) {
            keys = ["u"]
        } else if host.hasSuffix("youtube.com") && path == "/redirect" {
            keys = ["q"]
        } else if host.hasSuffix("linkedin.com") && path.hasPrefix("/redir/redirect") {
            keys = ["url"]
        } else {
            return url
        }
        for key in keys {
            if let value = items.first(where: { $0.name == key })?.value,
               let inner = URL(string: value), ["http", "https"].contains(inner.scheme?.lowercased()) {
                return unwrap(inner)
            }
        }
        return url
    }

    // MARK: Tracker removal

    static let trackers: Set<String> = [
        "fbclid", "gclid", "dclid", "gbraid", "wbraid", "msclkid", "yclid", "twclid", "ttclid",
        "igshid", "igsh", "mc_cid", "mc_eid", "_hsenc", "_hsmi", "mkt_tok", "oly_anon_id", "oly_enc_id",
        "vero_id", "vero_conv", "s_cid", "ref_src", "ref_url", "si", "_ga", "_gl",
    ]

    public static func strip(_ url: URL) -> URL {
        guard var c = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let items = c.percentEncodedQueryItems, !items.isEmpty else { return url }
        let kept = items.filter {
            let n = $0.name.lowercased()
            return !(n.hasPrefix("utm_") || trackers.contains(n))
        }
        guard kept.count != items.count else { return url }
        c.percentEncodedQueryItems = kept.isEmpty ? nil : kept
        return c.url ?? url
    }

    // MARK: Native app handoff

    /// Links that belong in a desktop app. Returns the app's bundle id and the URL to give it.
    public static func nativeApp(for url: URL) -> (app: String, url: URL)? {
        guard ["http", "https"].contains(url.scheme?.lowercased()), let host = host(url) else { return nil }
        let parts = Array(url.pathComponents.dropFirst())
        let rest = url.absoluteString.replacingOccurrences(of: "^https?://", with: "", options: .regularExpression)

        if host == "zoom.us" || host.hasSuffix(".zoom.us"), parts.count >= 2, parts[0] == "j" {
            var c = URLComponents()
            c.scheme = "zoommtg"
            c.host = "zoom.us"
            c.path = "/join"
            c.queryItems = [URLQueryItem(name: "action", value: "join"), URLQueryItem(name: "confno", value: parts[1])]
            if let pwd = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first(where: { $0.name == "pwd" }) {
                c.queryItems?.append(pwd)
            }
            return c.url.map { ("us.zoom.xos", $0) }
        }
        if host == "open.spotify.com" {
            let p = parts.first?.hasPrefix("intl-") == true ? Array(parts.dropFirst()) : parts
            if p.count >= 2 { return URL(string: "spotify:\(p[0]):\(p[1])").map { ("com.spotify.client", $0) } }
        }
        if host == "teams.microsoft.com", parts.first == "l" {
            return URL(string: "msteams://" + rest).map { ("com.microsoft.teams2", $0) }
        }
        if host == "figma.com", let kind = parts.first, ["file", "design", "board", "proto", "slides"].contains(kind) {
            return ("com.figma.Desktop", url)
        }
        if host == "notion.so" {
            return URL(string: "notion://" + rest).map { ("notion.id", $0) }
        }
        if host == "linear.app", parts.count >= 2 {
            return URL(string: "linear://" + rest.dropFirst("linear.app/".count)).map { ("com.linear", $0) }
        }
        return nil
    }

    // MARK: Typed input

    /// A web URL if the text is one ("github.com", "localhost:3000", "https://…"), else nil.
    public static func webURL(_ text: String) -> URL? {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty, !t.contains(where: \.isWhitespace) else { return nil }
        if let r = t.range(of: "://") {
            return t[..<r.lowerBound].allSatisfy(\.isLetter) ? URL(string: t) : nil
        }
        let hostPart = t.prefix { $0 != "/" && $0 != ":" && $0 != "?" && $0 != "#" }.lowercased()
        let isLocal = hostPart == "localhost" || hostPart.allSatisfy { $0.isNumber || $0 == "." } && hostPart.contains(".")
        let tld = hostPart.split(separator: ".").last ?? ""
        let isDomain = hostPart.contains(".") && tld.count >= 2 && tld.allSatisfy(\.isLetter)
        guard isLocal || isDomain else { return nil }
        return URL(string: (isLocal ? "http://" : "https://") + t)
    }

    /// What the launcher opens: a URL, or a search for anything else.
    public static func fromInput(_ text: String, search: String) -> URL? {
        if let url = webURL(text) { return url }
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return nil }
        let allowed = CharacterSet.urlQueryAllowed.subtracting(CharacterSet(charactersIn: "&+=?#"))
        guard let q = t.addingPercentEncoding(withAllowedCharacters: allowed) else { return nil }
        return URL(string: search.replacingOccurrences(of: "%s", with: q))
    }
}
