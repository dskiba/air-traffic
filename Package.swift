// swift-tools-version: 6.2
import PackageDescription

let size: [SwiftSetting] = [.unsafeFlags(["-Osize"], .when(configuration: .release))]

let package = Package(
    name: "AirTraffic",
    platforms: [.macOS(.v26)],
    targets: [
        // Pure logic: config, routing, URL cleanup. Foundation only, fully unit-tested.
        .target(name: "AirTrafficCore", swiftSettings: size),
        // The app: AppKit shell, picker panel, browser launching, settings.
        .executableTarget(
            name: "AirTraffic",
            dependencies: ["AirTrafficCore"],
            swiftSettings: size + [.defaultIsolation(MainActor.self)],
            linkerSettings: [.unsafeFlags(["-Xlinker", "-dead_strip"])]
        ),
        .testTarget(name: "AirTrafficCoreTests", dependencies: ["AirTrafficCore"]),
    ]
)
