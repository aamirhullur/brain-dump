import Foundation
import GRDB

enum AppDatabaseError: LocalizedError {
    case missingMigrationResource

    var errorDescription: String? {
        "Could not locate bundled migration resources."
    }
}

final class AppDatabase {
    let writer: any DatabaseWriter

    init(path: String) throws {
        var configuration = Configuration()
        configuration.busyMode = .timeout(5)
        if path == ":memory:" {
            writer = try DatabaseQueue(configuration: configuration)
        } else {
            writer = try DatabasePool(path: path, configuration: configuration)
        }
    }

    func migrate() throws {
        guard let migrationsURL = Bundle.module.url(forResource: "Migrations", withExtension: nil) ?? Bundle.module.resourceURL else {
            throw AppDatabaseError.missingMigrationResource
        }
        let migrationFiles = try FileManager.default.contentsOfDirectory(at: migrationsURL, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "sql" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
        guard !migrationFiles.isEmpty else {
            throw AppDatabaseError.missingMigrationResource
        }

        var migrator = DatabaseMigrator()
        for file in migrationFiles {
            let version = file.deletingPathExtension().lastPathComponent
            let sql = try String(contentsOf: file, encoding: .utf8)
            migrator.registerMigration(version) { db in
                try db.execute(sql: sql)
            }
        }
        try migrator.migrate(writer)
    }

    func read<T>(_ block: (GRDB.Database) throws -> T) throws -> T {
        try writer.read(block)
    }

    func write<T>(_ block: (GRDB.Database) throws -> T) throws -> T {
        try writer.write(block)
    }
}
