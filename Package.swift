// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "Aries",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "Aries",
            path: "Sources/Aries",
            linkerSettings: [
                .linkedFramework("CoreMediaIO"),
                .linkedFramework("CoreAudio"),
                .linkedFramework("IOKit"),
                .linkedFramework("Network"),
            ]
        )
    ]
)
