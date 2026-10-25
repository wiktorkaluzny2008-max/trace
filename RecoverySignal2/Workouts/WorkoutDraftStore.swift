import Foundation
import SQLite3

/// One synchronous transaction stores the complete session and timer together.
/// Separate from completed SwiftData logs so a failed log save retains the draft.
@MainActor
final class WorkoutDraftStore {
    private var database: OpaquePointer?
    struct Failure: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }

    init(url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        guard sqlite3_open_v2(url.path, &database, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX, nil) == SQLITE_OK else {
            let message = database.map { String(cString: sqlite3_errmsg($0)) } ?? "Cannot open workout storage"
            sqlite3_close(database)
            database = nil
            throw Failure(message: message)
        }
        do {
            try execute("PRAGMA journal_mode=WAL; PRAGMA synchronous=FULL; PRAGMA fullfsync=ON; PRAGMA busy_timeout=1500;")
            try execute("CREATE TABLE IF NOT EXISTS draft (id INTEGER PRIMARY KEY CHECK(id=1), payload BLOB NOT NULL)")
        } catch {
            sqlite3_close(database)
            database = nil
            throw error
        }
    }

    deinit { sqlite3_close(database) }

    func read() throws -> Data? {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, "SELECT payload FROM draft WHERE id=1", -1, &statement, nil) == SQLITE_OK else { throw failure() }
        defer { sqlite3_finalize(statement) }
        let result = sqlite3_step(statement)
        if result == SQLITE_DONE { return nil }
        guard result == SQLITE_ROW, let bytes = sqlite3_column_blob(statement, 0) else { throw failure() }
        return Data(bytes: bytes, count: Int(sqlite3_column_bytes(statement, 0)))
    }

    func write(_ data: Data) throws {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, "INSERT OR REPLACE INTO draft(id,payload) VALUES(1,?)", -1, &statement, nil) == SQLITE_OK else { throw failure() }
        defer { sqlite3_finalize(statement) }
        let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        let binding = data.withUnsafeBytes { sqlite3_bind_blob(statement, 1, $0.baseAddress, Int32($0.count), transient) }
        guard binding == SQLITE_OK, sqlite3_step(statement) == SQLITE_DONE else { throw failure() }
    }

    private func execute(_ sql: String) throws {
        guard sqlite3_exec(database, sql, nil, nil, nil) == SQLITE_OK else { throw failure() }
    }
    private func failure() -> Failure {
        Failure(message: database.map { String(cString: sqlite3_errmsg($0)) } ?? "Workout storage unavailable")
    }
}
