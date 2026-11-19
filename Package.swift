// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Contxt",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "Contxt",
            path: "Sources/Contxt"
        )
    ]
)
