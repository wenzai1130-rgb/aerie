// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Aerie",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "Aerie",
            path: "Sources/Aerie"
        )
    ]
)
