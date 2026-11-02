// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "SFinder",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(name: "SFinderCore", targets: ["SFinderCore"]),
        .executable(name: "SFinderHost", targets: ["SFinderHost"]),
        .library(name: "SFinderSync", type: .dynamic, targets: ["SFinderSync"])
    ],
    dependencies: [],
    targets: [
        .target(
            name: "SFinderCore",
            dependencies: [],
            path: "Sources/SFinderCore"
        ),
        .executableTarget(
            name: "SFinderHost",
            dependencies: ["SFinderCore"],
            path: "Sources/SFinderHost"
        ),
        .target(
            name: "SFinderSync",
            dependencies: ["SFinderCore"],
            path: "Sources/SFinderSync"
        )
    ]
)
