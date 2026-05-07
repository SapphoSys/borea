// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "Borea",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "Borea", targets: ["Borea"])
    ],
    targets: [
        .executableTarget(
            name: "Borea",
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("IOBluetooth")
            ]
        )
    ],
    swiftLanguageVersions: [.v5]
)
