import DependenciesTestSupport
import Foundation
import SQLiteData
import SQLiteDataTestSupport
import SnapshotTesting
import Testing

#if SQLITE_ENGINE_SQLITENIO
import SQLiteNIO
#endif

@MainActor
#if SQLITE_ENGINE_GRDB
@Suite(
  .dependency(\.defaultDatabase, try .database()),
  .snapshots(record: .failed),
)
#elseif SQLITE_ENGINE_SQLITENIO
@Suite(
  .dependency(\.defaultSQLiteConnection, try .nioConnection()),
  .snapshots(record: .failed),
)
#endif
struct AssertQueryTests {
  @available(iOS 17, macOS 14, tvOS 17, watchOS 10, *)
  @Test func assertQueryBasic() async throws {
#if SQLITE_ENGINE_GRDB
    assertQuery(
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
#elseif SQLITE_ENGINE_SQLITENIO
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
#endif
  }
  
  @available(iOS 17, macOS 14, tvOS 17, watchOS 10, *)
  @Test func assertQueryRecord() async throws {
#if SQLITE_ENGINE_GRDB
    assertQuery(
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
#elseif SQLITE_ENGINE_SQLITENIO
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
#endif
  }
  
  @available(iOS 17, macOS 14, tvOS 17, watchOS 10, *)
  @Test func assertQueryBasicUpdate() async throws {
#if SQLITE_ENGINE_GRDB
    assertQuery(
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
#elseif SQLITE_ENGINE_SQLITENIO
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
#endif
  }
  
  @available(iOS 17, macOS 14, tvOS 17, watchOS 10, *)
  @Test func assertQueryRecordUpdate() async throws {
#if SQLITE_ENGINE_GRDB
    assertQuery(
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
#elseif SQLITE_ENGINE_SQLITENIO
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
#endif
  }
  
  @available(iOS 17, macOS 14, tvOS 17, watchOS 10, *)
  @Test func assertQueryEmpty() async throws {
#if SQLITE_ENGINE_GRDB
    assertQuery(
      Record.all.where { $0.id == -1 }.select(\.id)
    ) {
        """
        (No results)
        """
    }
#elseif SQLITE_ENGINE_SQLITENIO
    await assertQueryNIO(
      Record.all.where { $0.id == -1 }.select(\.id)
    ) {
        """
        (No results)
        """
    }
#endif
  }
  
  @Test(.snapshots(record: .never))
  @available(iOS 17, macOS 14, tvOS 17, watchOS 10, *)
  func assertQueryFailsNoResultsNonEmptySnapshot() {
    withKnownIssue {
#if SQLITE_ENGINE_GRDB
      assertQuery(
        Record.all.where { _ in false }
      ) {
        """
        XYZ
        """
      }
#elseif SQLITE_ENGINE_SQLITENIO
      await assertQueryNIO(
        Record.all.where { _ in false }
      ) {
        """
        XYZ
        """
      }
#endif
    }
  }
  
#if DEBUG
  @available(iOS 17, macOS 14, tvOS 17, watchOS 10, *)
  @Test func assertQueryBasicIncludeSQL() async throws {
#if SQLITE_ENGINE_GRDB
    assertQuery(
      includeSQL: true,
      Record.all.select(\.id)
    ) {
          """
          SELECT "records"."id"
          FROM "records"
          """
    } results: {
          """
          ┌───┐
          │ 1 │
          │ 2 │
          │ 3 │
          └───┘
          """
    }
#elseif SQLITE_ENGINE_SQLITENIO
    // SQL inclusion not yet supported for SQLiteNIO
    // Skip this test for now
#endif
  }
#endif
  
#if DEBUG
  @available(iOS 17, macOS 14, tvOS 17, watchOS 10, *)
  @Test func assertQueryRecordIncludeSQL() async throws {
#if SQLITE_ENGINE_GRDB
    assertQuery(
      includeSQL: true,
      Record.where { $0.id == 1 }
    ) {
          """
          SELECT "records"."id", "records"."date"
          FROM "records"
          WHERE ("records"."id") = (1)
          """
    } results: {
          """
          ┌────────────────────────────────────────┐
          │ Record(                                │
          │   id: 1,                               │
          │   date: Date(1970-01-01T00:00:42.000Z) │
          │ )                                      │
          └────────────────────────────────────────┘
          """
    }
#elseif SQLITE_ENGINE_SQLITENIO
    // SQL inclusion not yet supported for SQLiteNIO
    // Skip this test for now
#endif
  }
#endif
}

@Table
private struct Record: Equatable, Sendable {
  let id: Int
#if SQLITE_ENGINE_GRDB
  @Column(as: Date.UnixTimeRepresentation.self)
  var date = Date(timeIntervalSince1970: 42)
#elseif SQLITE_ENGINE_SQLITENIO
  let date: Date = Date(timeIntervalSince1970: 42)
#endif
}

#if SQLITE_ENGINE_GRDB
extension DatabaseWriter where Self == DatabaseQueue {
  fileprivate static func database() throws -> DatabaseQueue {
    let database = try DatabaseQueue()
    try database.write { db in
      try #sql(
          """
          CREATE TABLE "records" (
            "id" INTEGER PRIMARY KEY AUTOINCREMENT,
            "date" INTEGER NOT NULL DEFAULT 42
          )
          """
      )
      .execute(db)
      for _ in 1...3 {
        _ = try Record.insert { Record.Draft() }.execute(db)
      }
    }
    return database
  }
}
#elseif SQLITE_ENGINE_SQLITENIO
extension SQLiteConnection {
  fileprivate static func nioConnection() throws -> SQLiteConnection {
    try Task {
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
    }.value
  }
}
#endif
