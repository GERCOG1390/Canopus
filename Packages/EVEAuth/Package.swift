// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "EVEAuth",
    platforms: [.iOS(.v18), .macOS(.v15)],
    products: [
        .library(name: "EVEAuth", targets: ["EVEAuth"]),
    ],
    dependencies: [
        .package(name: "Domain", path: "../Domain"),
    ],
    targets: [
        .target(
            name: "EVEAuth",
            dependencies: ["Domain"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .testTarget(
            name: "EVEAuthTests",
            dependencies: ["EVEAuth"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
    ]
)
