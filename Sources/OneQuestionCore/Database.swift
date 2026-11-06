import Foundation
import CSQLite

public final class Database {
    private var handle: OpaquePointer?
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    public let url: URL

    public init(url: URL) throws {
        self.url = url
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        guard sqlite3_open(url.path, &handle) == SQLITE_OK else {
            if let handle { sqlite3_close(handle) }; handle = nil
            throw AppFailure("无法打开本地数据库。")
        }
        try execute("PRAGMA journal_mode=WAL")
        try execute("PRAGMA busy_timeout=3000")
        try execute("CREATE TABLE IF NOT EXISTS questions (id TEXT PRIMARY KEY, payload TEXT NOT NULL)")
        try execute("CREATE TABLE IF NOT EXISTS attempts (id TEXT PRIMARY KEY, payload TEXT NOT NULL)")
        try execute("CREATE TABLE IF NOT EXISTS preferences (id TEXT PRIMARY KEY, payload TEXT NOT NULL)")
    }
    deinit { sqlite3_close(handle) }

    private func execute(_ sql: String) throws {
        guard sqlite3_exec(handle, sql, nil, nil, nil) == SQLITE_OK else {
            throw AppFailure("本地数据库操作失败：\(String(cString: sqlite3_errmsg(handle)))")
        }
    }
    private func write<T: Encodable>(_ value: T, id: String, table: String) throws {
        let data = try encoder.encode(value)
        guard let payload = String(data: data, encoding: .utf8) else { throw AppFailure("数据编码失败。") }
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(handle, "INSERT OR REPLACE INTO \(table) (id,payload) VALUES (?,?)", -1, &stmt, nil) == SQLITE_OK else { throw AppFailure("无法准备本地保存。") }
        defer { sqlite3_finalize(stmt) }
        let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        sqlite3_bind_text(stmt, 1, id, -1, transient)
        sqlite3_bind_text(stmt, 2, payload, -1, transient)
        guard sqlite3_step(stmt) == SQLITE_DONE else { throw AppFailure("本地保存失败。") }
    }
    private func read<T: Decodable>(_ type: T.Type, table: String, id: String? = nil) throws -> [T] {
        var stmt: OpaquePointer?
        let sql = "SELECT payload FROM \(table)" + (id == nil ? "" : " WHERE id=?")
        guard sqlite3_prepare_v2(handle, sql, -1, &stmt, nil) == SQLITE_OK else { throw AppFailure("读取本地数据失败。") }
        defer { sqlite3_finalize(stmt) }
        if let id { sqlite3_bind_text(stmt, 1, id, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self)) }
        var result: [T] = []
        while true {
            let status = sqlite3_step(stmt)
            if status == SQLITE_DONE { break }
            guard status == SQLITE_ROW, let ptr = sqlite3_column_text(stmt, 0) else { throw AppFailure("读取本地数据失败。") }
            result.append(try decoder.decode(type, from: Data(String(cString: ptr).utf8)))
        }
        return result
    }
    public func questions() throws -> [Question] {
        try read(Question.self, table: "questions").sorted { ($0.deck, $0.category, $0.title) < ($1.deck, $1.category, $1.title) }
    }
    public func attempts() throws -> [Attempt] {
        try read(Attempt.self, table: "attempts").sorted { $0.createdAt > $1.createdAt }
    }
    public func save(questions: [Question]) throws {
        try execute("BEGIN IMMEDIATE")
        do {
            for question in questions { try write(question, id: question.id, table: "questions") }
            try execute("COMMIT")
        } catch { try? execute("ROLLBACK"); throw error }
    }
    public func save(attempt: Attempt) throws { try write(attempt, id: attempt.id, table: "attempts") }
    public func set<T: Encodable>(_ value: T, for key: String) throws { try write(value, id: key, table: "preferences") }
    public func get<T: Decodable>(_ type: T.Type, for key: String) throws -> T? { try read(type, table: "preferences", id: key).first }
    public func deleteQuestion(id: String) throws {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(handle, "DELETE FROM questions WHERE id=?", -1, &stmt, nil) == SQLITE_OK else { throw AppFailure("删除题目失败。") }
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_text(stmt, 1, id, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
        guard sqlite3_step(stmt) == SQLITE_DONE else { throw AppFailure("删除题目失败。") }
    }
}
