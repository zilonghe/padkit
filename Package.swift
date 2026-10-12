// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "PadKit",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "PadKit",
            path: "Sources/PadKit",
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("ApplicationServices"),
                .linkedFramework("ServiceManagement"),
                .linkedFramework("SwiftUI"),
            ]
        )
    ]
)
