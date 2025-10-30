// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "fdb-triple-layer",
    platforms: [
        .macOS(.v15),
    ],
    products: [
        .library(
            name: "TripleLayer",
            targets: ["TripleLayer"]
        ),
    ],
    dependencies: [
        .package(
            url: "https://github.com/apple/swift-log.git",
            from: "1.0.0"
        ),
        .package(
            url: "https://github.com/foundationdb/fdb-swift-bindings.git",
            branch: "main"
        ),
    ],
    targets: [
        .target(
            name: "TripleLayer",
            dependencies: [
                .product(name: "FoundationDB", package: "fdb-swift-bindings"),
                .product(name: "Logging", package: "swift-log")
            ],
            swiftSettings: [
                .unsafeFlags(["-Xfrontend", "-warn-concurrency"])
            ]
        ),
        .testTarget(
            name: "TripleLayerTests",
            dependencies: ["TripleLayer"],
            linkerSettings: [
                .unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "/usr/local/lib"])
            ]
        ),
    ],
    swiftLanguageModes: [.v5]
)
