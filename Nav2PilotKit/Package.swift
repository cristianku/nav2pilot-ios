// swift-tools-version:5.10

import PackageDescription

// Everything that is not UI: parsing, resolving, comma transport, storage and the view model.
// macOS is listed only so that `swift test` runs on a Mac without a simulator.
let package = Package(
    name: "Nav2PilotKit",
    platforms: [
        .iOS(.v17),
        .macOS(.v14),
    ],
    products: [
        .library(name: "Nav2PilotKit", targets: ["Nav2PilotKit"]),
    ],
    targets: [
        .target(name: "Nav2PilotKit"),
        .testTarget(name: "Nav2PilotKitTests", dependencies: ["Nav2PilotKit"]),
    ],
    swiftLanguageVersions: [.v5]
)
