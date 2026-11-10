import Foundation
import Testing
@testable import AirTrafficCore

private func u(_ s: String) -> URL { URL(string: s)! }
private let brave = Target(app: "com.brave.Browser", profile: "Profile 1")
private let safari = Target(app: "com.apple.Safari")
private let all: @Sendable (String) -> Bool = { _ in true }

@Test func ruleMatchesDomainAndSubdomains() {
    let r = Rule(match: "figma.com", target: brave)
    #expect(r.matches(u("https://figma.com/x"), from: nil))
    #expect(r.matches(u("https://www.figma.com/x"), from: nil))
    #expect(r.matches(u("https://help.figma.com"), from: nil))
    #expect(!r.matches(u("https://notfigma.com"), from: nil))
}

@Test func ruleMatchesPathPrefixAndSource() {
    let r = Rule(match: "github.com/acme", from: "com.tinyspeck.slackmacgap", target: brave)
    #expect(r.matches(u("https://github.com/acme/repo"), from: "com.tinyspeck.slackmacgap"))
    #expect(!r.matches(u("https://github.com/other"), from: "com.tinyspeck.slackmacgap"))
    #expect(!r.matches(u("https://github.com/acme/repo"), from: "com.apple.mail"))
}

@Test func routeOrder() {
    var c = Config()
    c.rules = [Rule(match: "zoom.us", target: safari)]
    // Rule beats native-app handoff.
    #expect(route(u("https://acme.zoom.us/j/123"), from: nil, forcePicker: false, config: c, isInstalled: all)
        == .open(u("https://acme.zoom.us/j/123"), safari))
    // Modifier forces the picker even when a rule matches.
    #expect(route(u("https://zoom.us/j/1"), from: nil, forcePicker: true, config: c, isInstalled: all) == .pick(u("https://zoom.us/j/1")))
    // No rule, no fallback → picker.
    #expect(route(u("https://example.com"), from: nil, forcePicker: false, config: c, isInstalled: all) == .pick(u("https://example.com")))
    // Fallback.
    c.fallback = brave
    #expect(route(u("https://example.com"), from: nil, forcePicker: false, config: c, isInstalled: all) == .open(u("https://example.com"), brave))
    // Rule pointing at an uninstalled app is skipped.
    #expect(route(u("https://zoom.us/x"), from: nil, forcePicker: false, config: c, isInstalled: { $0 != safari.app })
        == .open(u("https://zoom.us/x"), brave))
}

@Test func stripsTrackersKeepsRest() {
    #expect(Links.strip(u("https://a.com/p?utm_source=x&id=7&fbclid=y#top")) == u("https://a.com/p?id=7#top"))
    #expect(Links.strip(u("https://a.com/p?utm_source=x")) == u("https://a.com/p"))
    #expect(Links.strip(u("https://a.com/p?q=a%2Fb")) == u("https://a.com/p?q=a%2Fb"))
}

@Test func unwrapsRedirects() {
    let inner = "https://example.com/doc?id=1"
    let enc = inner.addingPercentEncoding(withAllowedCharacters: .alphanumerics)!
    #expect(Links.unwrap(u("https://eur01.safelinks.protection.outlook.com/?url=\(enc)&data=x")) == u(inner))
    #expect(Links.unwrap(u("https://www.google.com/url?q=\(enc)&sa=D")) == u(inner))
    #expect(Links.unwrap(u("https://l.facebook.com/l.php?u=\(enc)&h=x")) == u(inner))
    #expect(Links.unwrap(u("https://www.google.com/search?q=cats")) == u("https://www.google.com/search?q=cats"))
}

@Test func nativeApps() {
    #expect(Links.nativeApp(for: u("https://acme.zoom.us/j/123?pwd=abc"))?.url
        == u("zoommtg://zoom.us/join?action=join&confno=123&pwd=abc"))
    #expect(Links.nativeApp(for: u("https://open.spotify.com/intl-de/track/42?si=x"))?.url == u("spotify:track:42"))
    #expect(Links.nativeApp(for: u("https://linear.app/acme/issue/ENG-1"))?.url == u("linear://acme/issue/ENG-1"))
    #expect(Links.nativeApp(for: u("https://www.figma.com/design/abc"))?.app == "com.figma.Desktop")
    #expect(Links.nativeApp(for: u("https://figma.com/pricing")) == nil)
}

@Test func typedInput() {
    let s = "https://duckduckgo.com/?q=%s"
    #expect(Links.fromInput("github.com", search: s) == u("https://github.com"))
    #expect(Links.fromInput("localhost:3000/a", search: s) == u("http://localhost:3000/a"))
    #expect(Links.fromInput("192.168.1.1", search: s) == u("http://192.168.1.1"))
    #expect(Links.fromInput("  https://x.dev/p  ", search: s) == u("https://x.dev/p"))
    #expect(Links.fromInput("swift concurrency", search: s) == u("https://duckduckgo.com/?q=swift%20concurrency"))
    #expect(Links.fromInput("v1.2", search: s) == u("https://duckduckgo.com/?q=v1.2"))
    #expect(Links.webURL("hello") == nil)
}

@Test func configRoundTripsAndDefaults() throws {
    let json = #"{"rules":[{"match":"figma.com","app":"com.brave.Browser","profile":"Profile 1","private":true}]}"#
    let c = try Config.decode(Data(json.utf8))
    #expect(c.rules.first?.target == Target(app: "com.brave.Browser", profile: "Profile 1", isPrivate: true))
    #expect(c.hotkey == "ctrl+opt+space" && c.cleanURLs && c.fallback == nil)
    #expect(try Config.decode(c.encoded()) == c)
}

@Test func pathMatchesWholeSegmentsOnly() {
    let r = Rule(match: "github.com/acme", target: brave)
    #expect(r.matches(u("https://github.com/acme"), from: nil))
    #expect(r.matches(u("https://github.com/Acme/repo"), from: nil))
    #expect(!r.matches(u("https://github.com/acme-evil/repo"), from: nil))
    #expect(!r.matches(u("https://github.com/acmecorp"), from: nil))
}

@Test func savedRuleGoesFirstAndReplaces() {
    var c = Config()
    c.rules = [Rule(match: "github.com", target: safari)]
    c.setRule(match: "gist.github.com", target: brave)
    #expect(route(u("https://gist.github.com/x"), from: nil, forcePicker: false, config: c, isInstalled: all) == .open(u("https://gist.github.com/x"), brave))
    c.setRule(match: "gist.github.com", target: safari)
    #expect(c.rules.count == 2 && c.rules[0].target == safari)
}
