// swift-tools-version: 5.10

import PackageDescription

let package = Package(
    name: "WallhavenDownloader",
    defaultLocalization: "zh-Hans",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "WallhavenDownloader", targets: ["WallhavenDownloader"])
    ],
    targets: [
        .executableTarget(
            name: "WallhavenDownloader",
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("Security"),
                .linkedFramework("SwiftUI"),
                .linkedFramework("WebKit")
            ]
        )
    ]
)
