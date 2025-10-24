#if canImport(SQLiteNIO)
import DependenciesTestSupport
import Foundation
import SQLiteData
import SQLiteDataTestSupport
import SQLiteNIO
import SnapshotTesting
import Testing

@MainActor
@Suite(
  .dependency(\.defaultSQLiteConnection, try await .nioConnection()),
  .snapshots(record: .failed),
)
struct AssertQueryNIOTests {
  @available(iOS 17, macOS 14, tvOS 17, watchOS 10, *)
  @Test func assertQueryBasic() async throws {
    await assertQueryNIO(
      Record.all.select(\.id)
    ) {
      """
      ┌───┐
      │ 1 │
      │ 2 │
      │ 3 │
      └───┘
      """
    }
  }

  @available(iOS 17, macOS 14, tvOS 17, watchOS 10, *)
  @Test func assertQueryRecord() async throws {
    await assertQueryNIO(
      Record.where { $0.id == 1 }
    ) {
      """
      ┌────────────────────────────────────────┐
      │ Record(                                │
      │   id: 1,                               │
      │   date: Date(1970-01-01T00:00:42.000Z) │
      │ )                                      │
      └────────────────────────────────────────┘
      """
    }
  }

  @available(iOS 17, macOS 14, tvOS 17, watchOS 10, *)
  @Test func assertQueryBasicUpdate() async throws {
    await assertQueryNIO(
      Record.all
        .update { $0.date = Date(timeIntervalSince1970: 45) }
        .returning { ($0.id, $0.date) }
    ) {
      """
      ┌───┬────────────────────────────────┐
      │ 1 │ Date(1970-01-01T00:00:45.000Z) │
      │ 2 │ Date(1970-01-01T00:00:45.000Z) │
      │ 3 │ Date(1970-01-01T00:00:45.000Z) │
      └───┴────────────────────────────────┘
      """
    }
  }

  @available(iOS 17, macOS 14, tvOS 17, watchOS 10, *)
  @Test func assertQueryRecordUpdate() async throws {
    await assertQueryNIO(
      Record
        .where { $0.id == 1 }
        .update { $0.date = Date(timeIntervalSince1970: 45) }
        .returning(\.self)
    ) {
      """
      ┌────────────────────────────────────────┐
      │ Record(                                │
      │   id: 1,                               │
      │   date: Date(1970-01-01T00:00:45.000Z) │
      │ )                                      │
      └────────────────────────────────────────┘
      """
    }
  }
}

@Table
private struct Record: Equatable, Sendable {
  let id: Int
  let date: Date = Date(timeIntervalSince1970: 42)
}

extension SQLiteConnection {
  fileprivate static func nioConnection() async throws -> SQLiteConnection {
    let connection = try await SQLiteConnection.open(storage: .memory)
    
    // Create table
    try await connection.query("""
      CREATE TABLE "Record" (
        "id" INTEGER PRIMARY KEY,
        "date" TEXT NOT NULL
      )
      """, [])
    
    // Insert test data
    try await connection.transaction { conn in
      for id in 1...3 {
        try await conn.query(
          "INSERT INTO \"Record\" (id, date) VALUES (?, ?)",
          [.integer(id), .text(Date(timeIntervalSince1970: 42).iso8601String)]
        )
      }
    }
    
    return connection
  }
}
#endif
