import Foundation
import Observation
import AirTrafficCore

/// The config file (~/.config/air-traffic/config.json) plus discovered browsers.
/// Edits in Settings save immediately; hand edits are picked up on the next link (one stat call).
@Observable
final class Store {
    static let fileURL = FileManager.default.homeDirectoryForCurrentUser.appending(path: ".config/air-traffic/config.json")

    var config: Config {
        didSet {
            guard config != oldValue else { return }
            if !loading { save() }
            onChange?()
        }
    }
    var browsers: [Browser] = []
    /// No config file existed at launch.
    @ObservationIgnored let firstRun: Bool

    @ObservationIgnored var onChange: (() -> Void)?
    @ObservationIgnored private var modified: Date?
    /// Applying a hand-edited file must not rewrite it (that would drop unknown or misspelled keys).
    @ObservationIgnored private var loading = false

    var choices: [Choice] { browsers.filter { !config.hide.contains($0.id) }.flatMap(\.choices) }

    init() {
        config = Config()
        firstRun = !FileManager.default.fileExists(atPath: Self.fileURL.path)
        if let c = read() { config = c } else if !FileManager.default.fileExists(atPath: Self.fileURL.path) { save() }
    }

    func reloadIfChanged() {
        guard modificationDate() != modified, let c = read(), c != config else { return }
        loading = true
        config = c
        loading = false
    }

    private func read() -> Config? {
        guard let data = try? Data(contentsOf: Self.fileURL) else { return nil }
        modified = modificationDate()
        do { return try Config.decode(data) } catch {
            NSLog("Air Traffic: config.json is invalid, keeping previous settings: \(error)")
            return nil
        }
    }

    private func save() {
        do {
            try FileManager.default.createDirectory(at: Self.fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try config.encoded().write(to: Self.fileURL, options: .atomic)
            modified = modificationDate()
        } catch {
            NSLog("Air Traffic: could not save config: \(error)")
        }
    }

    private func modificationDate() -> Date? {
        (try? FileManager.default.attributesOfItem(atPath: Self.fileURL.path))?[.modificationDate] as? Date
    }
}
