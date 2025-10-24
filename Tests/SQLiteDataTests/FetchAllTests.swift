import DependenciesTestSupport
import Foundation
import SQLiteData
import Testing

#if SQLITE_ENGINE_SQLITENIO
  import SQLiteNIO
#endif

#if SQLITE_ENGINE_GRDB
  @Suite(.dependency(\.defaultDatabase, try .database()))
#elseif SQLITE_ENGINE_SQLITENIO
  @Suite(.dependency(\.defaultSQLiteConnection, try .nioTestConnection()))
#endif
struct FetchAllTests {
  #if SQLITE_ENGINE_GRDB
    @Dependency(\.defaultDatabase) var database
  #elseif SQLITE_ENGINE_SQLITENIO
    @Dependency(\.defaultSQLiteConnection) var connection
  #endif

  @MainActor
  @Test func concurrency() async throws {
    #if SQLITE_ENGINE_GRDB
      let count = 1_000
      try await database.write { db in
        try Record.delete().execute(db)
      }

      @FetchAll var records: [Record]

      await withThrowingTaskGroup { group in
        for index in 1...count {
          group.addTask {
            try await self.database.write { db in
              try Record.insert { Record(id: index) }.execute(db)
            }
          }
        }
      }

      try await $records.load()
      #expect(records == (1...count).map { Record(id: $0) })

      await withThrowingTaskGroup { group in
        for index in 1...(count / 2) {
          group.addTask {
            try await self.database.write { db in
              try Record.find(index * 2).delete().execute(db)
            }
          }
        }
      }

      try await $records.load()
      #expect(records == (0...(count / 2 - 1)).map { Record(id: $0 * 2 + 1) })
    #elseif SQLITE_ENGINE_SQLITENIO
      let count = 100  // Reduced from 1000 for faster testing
      try await connection.query("DELETE FROM \"Record\"", [])

      @FetchAll(Record.all) var records

      await withThrowingTaskGroup { group in
        for index in 1...count {
          group.addTask {
            try await self.connection.transaction { conn in
              try await conn.query(
                "INSERT INTO \"Record\" (id, date) VALUES (?, ?)",
                [.integer(index), .text(Date(timeIntervalSince1970: 42).iso8601String)]
              )
            }
          }
        }
      }

      try await $records.load()
      #expect(records.count == count)
      #expect(Set(records.map(\.id)) == Set(1...count))

      await withThrowingTaskGroup { group in
        for index in 1...(count / 2) {
          group.addTask {
            try await self.connection.query(
              "DELETE FROM \"Record\" WHERE id = ?",
              [.integer(index * 2)]
            )
          }
        }
      }

      try await $records.load()
      #expect(records.count == count / 2)
    #endif
  }

  @available(iOS 17, macOS 14, tvOS 17, watchOS 10, *)
  @Test func fetchFailure() {
    #if SQLITE_ENGINE_GRDB
      do {
        try database.read { db in
          _ =
            try Record
            .select { ($0.id, $0.date, #sql("\($0.optionalDate)", as: Date.self)) }
            .fetchAll(db)
        }
        Issue.record()
      } catch {
        #expect(
          "\(error)".contains(
            """
            Expected column 2 ("optionalDate") to not be NULL
            """
          )
        )
      }
    #elseif SQLITE_ENGINE_SQLITENIO
      // Skip this test for SQLiteNIO as it's GRDB-specific
    #endif
  }

  #if SQLITE_ENGINE_SQLITENIO
    @Test func basicFetch() async throws {
      @FetchAll(Record.all) var records
      try await $records.load()
      #expect(records.count == 3)
      #expect(records[0].id == 1)
      #expect(records[1].id == 2)
      #expect(records[2].id == 3)
    }

    @Test func filteredFetch() async throws {
      @FetchAll(Record.where { $0.id == 1 }) var records
      try await $records.load()
      #expect(records.count == 1)
      #expect(records[0].id == 1)
    }

    @Test func orderedFetch() async throws {
      @FetchAll(Record.order(by: \.id, .desc)) var records
      try await $records.load()
      #expect(records.count == 3)
      #expect(records[0].id == 3)
      #expect(records[1].id == 2)
      #expect(records[2].id == 1)
    }

    @Test func emptyResults() async throws {
      @FetchAll(Record.where { $0.id == 999 }) var records
      try await $records.load()
      #expect(records.isEmpty)
    }
  #endif
}

@Table
private struct Record: Equatable, Sendable {
  let id: Int
  #if SQLITE_ENGINE_GRDB
    @Column(as: Date.UnixTimeRepresentation.self)
    var date = Date(timeIntervalSince1970: 42)
    @Column(as: Date?.UnixTimeRepresentation.self)
    var optionalDate: Date?
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
            "date" INTEGER NOT NULL DEFAULT 42,
            "optionalDate" INTEGER
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
    fileprivate static func nioTestConnection() throws -> SQLiteConnection {
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
