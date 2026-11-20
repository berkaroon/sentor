// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Sentor",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(
            name: "Sentor",
            targets: ["Sentor"]
        )
    ],
    targets: [
        .executableTarget(
            name: "Sentor",
            path: "Sources/Sentor"
        )
    ]
)
