// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "BrainDump",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "BrainDump", targets: ["BrainDump"])
    ],
    dependencies: [
        .package(url: "https://github.com/groue/GRDB.swift.git", from: "7.0.0")
    ],
    targets: [
        .executableTarget(
            name: "BrainDump",
            dependencies: [
                .product(name: "GRDB", package: "GRDB.swift")
            ],
            path: "BrainDump",
            resources: [
                .process("Persistence/Migrations")
            ],
            swiftSettings: [
                .swiftLanguageMode(.v5)
            ]
        ),
        .testTarget(
            name: "BrainDumpTests",
            dependencies: ["BrainDump"],
            path: "Tests/BrainDumpTests",
            swiftSettings: [
                .swiftLanguageMode(.v5)
            ]
        )
    ]
)
