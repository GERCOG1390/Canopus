// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "EVEStaticData",
    platforms: [.iOS(.v18), .macOS(.v15)],
    products: [
        .library(name: "EVEStaticData", targets: ["EVEStaticData"]),
    ],
    dependencies: [
        .package(url: "https://github.com/groue/GRDB.swift.git", from: "7.0.0"),
        .package(name: "Domain", path: "../Domain"),
    ],
    targets: [
        .target(
            name: "EVEStaticData",
            dependencies: [
                .product(name: "GRDB", package: "GRDB.swift"),
                .product(name: "Domain", package: "Domain"),
            ]
        ),
        .testTarget(
            name: "EVEStaticDataTests",
            dependencies: ["EVEStaticData"]
        ),
    ]
)
