import Foundation

public enum Decision: Equatable, Sendable {
    case open(URL, Target)
    case pick(URL)
}

/// The hot path. Pure and synchronous: clean → rules → native app → fallback → picker.
public func route(
    _ url: URL,
    from source: String?,
    forcePicker: Bool,
    config: Config,
    isInstalled: (String) -> Bool
) -> Decision {
    let url = config.cleanURLs ? Links.clean(url) : url
    if forcePicker { return .pick(url) }
    if let rule = config.rules.first(where: { $0.matches(url, from: source) && isInstalled($0.target.app) }) {
        return .open(url, rule.target)
    }
    if config.openInApps, let (app, appURL) = Links.nativeApp(for: url), isInstalled(app) {
        return .open(appURL, Target(app: app))
    }
    if let fallback = config.fallback, isInstalled(fallback.app) {
        return .open(url, fallback)
    }
    return .pick(url)
}
