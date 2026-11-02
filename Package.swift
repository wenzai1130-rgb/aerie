// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Nest",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "Nest",
            path: "Sources/Nest"
        )
    ]
)
