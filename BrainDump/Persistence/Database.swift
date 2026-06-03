import CSQLite
import Foundation

private let sqliteTransient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

enum DatabaseError: Error, LocalizedError {
    case openFailed(String)
    case prepareFailed(String)
    case stepFailed(String)
    case missingMigrationResource

    var errorDescription: String? {
        switch self {
        case .openFailed(let message), .prepareFailed(let message), .stepFailed(let message):
            return message
        case .missingMigrationResource:
            return "Could not locate bundled migration resources."
        }
    }
}

final class Database {
    private let path: String
    private var handle: OpaquePointer?

    init(path: String) throws {
        self.path = path
        try open()
        try execute("PRAGMA foreign_keys = ON;")
        try execute("PRAGMA journal_mode = WAL;")
        try execute("PRAGMA busy_timeout = 5000;")
        try createMigrationTable()
    }

    deinit {
        sqlite3_close(handle)
    }

    func execute(_ sql: String) throws {
        var error: UnsafeMutablePointer<CChar>?
        if sqlite3_exec(handle, sql, nil, nil, &error) != SQLITE_OK {
            let message = error.map { String(cString: $0) } ?? lastError
            sqlite3_free(error)
            throw DatabaseError.stepFailed(message)
        }
    }

    func query<T>(_ sql: String, bind: ((OpaquePointer?) throws -> Void)? = nil, map: (OpaquePointer?) throws -> T) throws -> [T] {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(handle, sql, -1, &statement, nil) == SQLITE_OK else {
            throw DatabaseError.prepareFailed(lastError)
        }
        defer { sqlite3_finalize(statement) }

        try bind?(statement)

        var values: [T] = []
        while true {
            let result = sqlite3_step(statement)
            if result == SQLITE_ROW {
                values.append(try map(statement))
            } else if result == SQLITE_DONE {
                break
            } else {
                throw DatabaseError.stepFailed(lastError)
            }
        }
        return values
    }

    func write(_ sql: String, bind: ((OpaquePointer?) throws -> Void)? = nil) throws {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(handle, sql, -1, &statement, nil) == SQLITE_OK else {
            throw DatabaseError.prepareFailed(lastError)
        }
        defer { sqlite3_finalize(statement) }

        try bind?(statement)

        guard sqlite3_step(statement) == SQLITE_DONE else {
            throw DatabaseError.stepFailed(lastError)
        }
    }

    func migrate() throws {
        let migrationFiles: [URL]
        if let migrationsURL = Bundle.module.url(forResource: "Migrations", withExtension: nil) {
            migrationFiles = try FileManager.default.contentsOfDirectory(at: migrationsURL, includingPropertiesForKeys: nil)
                .filter { $0.pathExtension == "sql" }
                .sorted { $0.lastPathComponent < $1.lastPathComponent }
        } else if let bundledSQL = Bundle.module.urls(forResourcesWithExtension: "sql", subdirectory: nil) {
            migrationFiles = bundledSQL.sorted { $0.lastPathComponent < $1.lastPathComponent }
        } else {
            throw DatabaseError.missingMigrationResource
        }

        for file in migrationFiles {
            let version = file.deletingPathExtension().lastPathComponent
            if try appliedMigrations().contains(version) {
                continue
            }
            let sql = try String(contentsOf: file, encoding: .utf8)
            try execute("BEGIN TRANSACTION;")
            do {
                try execute(sql)
                try write(
                    "INSERT INTO schema_migrations (version, applied_at) VALUES (?, ?);",
                    bind: {
                        bindText(version, to: $0, at: 1)
                        bindText(DateFormatting.string(from: Date()), to: $0, at: 2)
                    }
                )
                try execute("COMMIT;")
            } catch {
                try? execute("ROLLBACK;")
                throw error
            }
        }
    }

    private func open() throws {
        guard sqlite3_open(path, &handle) == SQLITE_OK else {
            throw DatabaseError.openFailed(lastError)
        }
    }

    private func createMigrationTable() throws {
        try execute("""
        CREATE TABLE IF NOT EXISTS schema_migrations (
          version TEXT PRIMARY KEY NOT NULL,
          applied_at TEXT NOT NULL
        );
        """)
    }

    private func appliedMigrations() throws -> Set<String> {
        let versions = try query("SELECT version FROM schema_migrations;") { statement in
            columnText(statement, at: 0)
        }
        return Set(versions)
    }

    private var lastError: String {
        if let handle, let error = sqlite3_errmsg(handle) {
            return String(cString: error)
        }
        return "Unknown SQLite error"
    }
}

func bindText(_ value: String?, to statement: OpaquePointer?, at index: Int32) {
    guard let value else {
        sqlite3_bind_null(statement, index)
        return
    }
    sqlite3_bind_text(statement, index, value, -1, sqliteTransient)
}

func bindInt64(_ value: Int64, to statement: OpaquePointer?, at index: Int32) {
    sqlite3_bind_int64(statement, index, value)
}

func columnText(_ statement: OpaquePointer?, at index: Int32) -> String {
    guard let pointer = sqlite3_column_text(statement, index) else {
        return ""
    }
    return String(cString: pointer)
}

func columnOptionalText(_ statement: OpaquePointer?, at index: Int32) -> String? {
    guard sqlite3_column_type(statement, index) != SQLITE_NULL else {
        return nil
    }
    return columnText(statement, at: index)
}

func columnInt64(_ statement: OpaquePointer?, at index: Int32) -> Int64 {
    sqlite3_column_int64(statement, index)
}
