// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "FolderHop",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "FolderHop", targets: ["FolderHop"])],
    targets: [
        .target(name: "FolderCore"),
        .executableTarget(name: "FolderHop", dependencies: ["FolderCore"]),
        .testTarget(name: "FolderCoreTests", dependencies: ["FolderCore"])
    ]
)
