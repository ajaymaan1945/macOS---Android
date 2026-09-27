// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "MAANMac",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "MAAN", targets: ["MAAN"])
    ],
    targets: [
        .executableTarget(
            name: "MAAN",
            path: "Sources/MAAN",
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("Foundation"),
                .linkedFramework("Network"),
                .linkedFramework("AVFoundation"),
                .linkedFramework("UniformTypeIdentifiers"),
                .linkedFramework("UserNotifications")
            ]
        )
    ]
)
