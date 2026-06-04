// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "typesati",
    platforms: [
        // MenuBarExtra needs macOS 13+
        .macOS(.v13)
    ],
    dependencies: [
        .package(url: "https://github.com/groue/GRDB.swift.git", from: "7.0.0")
    ],
    targets: [
        .executableTarget(
            name: "typesati",
            dependencies: [
                .product(name: "GRDB", package: "GRDB.swift")
            ]
        ),
        .testTarget(
            name: "typesatiTests",
            dependencies: ["typesati"]
        )
    ]
)
