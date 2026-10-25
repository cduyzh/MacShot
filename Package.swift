// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "cduyzhShot",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "cduyzhShot", targets: ["cduyzhShot"])
    ],
    dependencies: [],
    targets: [
        .executableTarget(
            name: "cduyzhShot",
            dependencies: [],
            path: "Sources/cduyzhShot",
            resources: [.copy("Resources/ReleaseHistory.json")]
        )
    ]
)
