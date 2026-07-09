// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "TodoCapsule",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "TodoCapsule",
            path: "Sources/TodoCapsule"
        )
    ]
)
