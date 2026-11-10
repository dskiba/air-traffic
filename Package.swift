// swift-tools-version: 6.2
import PackageDescription

let size: [SwiftSetting] = [.unsafeFlags(["-Osize"], .when(configuration: .release))]

let package = Package(
    name: "AirTraffic",
    platforms: [.macOS(.v26)],
    targets: [
        // Pure logic: config, routing, URL cleanup. Foundation only, fully unit-tested.
        .target(name: "AirTrafficCore", swiftSettings: size),
        .testTarget(name: "AirTrafficCoreTests", dependencies: ["AirTrafficCore"]),
    ]
)
