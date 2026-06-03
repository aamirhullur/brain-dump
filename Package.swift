// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "BrainDump",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "BrainDump", targets: ["BrainDump"])
    ],
    targets: [
        .systemLibrary(
            name: "CSQLite",
            path: "CSQLite",
            pkgConfig: "sqlite3",
            providers: [
                .brew(["sqlite"])
            ]
        ),
        .executableTarget(
            name: "BrainDump",
            dependencies: ["CSQLite"],
            path: "BrainDump",
            resources: [
                .process("Persistence/Migrations")
            ],
            linkerSettings: [
                .linkedLibrary("sqlite3")
            ]
        ),
        .testTarget(
            name: "BrainDumpTests",
            dependencies: ["BrainDump"],
            path: "Tests/BrainDumpTests"
        )
    ]
)
