import SQLiteData
import Testing

#if SQLITE_ENGINE_SQLITENO
  import DependenciesTestSupport
  import Foundation
  import SQLiteNIO
#endif

#if SQLITE_ENGINE_GRDB
  @Suite struct QueryCursorTests {
    let database: DatabaseQueue
    init() throws {
      var configuration = Configuration()
      configuration.prepareDatabase {
        $0.trace { print($0) }
      }
      database = try DatabaseQueue(configuration: configuration)
      try database.write { db in
        try #sql(#"CREATE TABLE "numbers" ("value" INTEGER NOT NULL)"#)
          .execute(db)
      }
    }

    @Test func emptyInsert() throws {
      try database.write { db in
        try Number.insert { [] }.execute(db)
      }
    }

    @Test func emptyUpdate() throws {
      try database.write { db in
        try Number.update { _ in }.execute(db)
      }
    }
  }

  @Table private struct Number {
    var value = 0
  }
#elseif SQLITE_ENGINE_SQLITENO
  @Suite(.dependency(\.defaultSQLiteConnection, try .nioTestConnection()))
  struct QueryCursorTests {
    @Dependency(\.defaultSQLiteConnection) var connection

    @Test func basicFetch() async throws {
      let records = try await Record.all.fetchAll(connection)
      #expect(records.count == 3)
      #expect(records[0].id == 1)
      #expect(records[1].id == 2)
      #expect(records[2].id == 3)
    }

    @Test func fetchOne() async throws {
      let record = try await Record.where { $0.id == 1 }.fetchOne(connection)
      #expect(record?.id == 1)
    }

    @Test func fetchNonExistent() async throws {
      let record = try await Record.where { $0.id == 999 }.fetchOne(connection)
      #expect(record == nil)
    }

    @Test func orderedFetch() async throws {
      let records = try await Record.order(by: \.id, .desc).fetchAll(connection)
      #expect(records.count == 3)
      #expect(records[0].id == 3)
      #expect(records[1].id == 2)
      #expect(records[2].id == 1)
    }

    @Test func limitFetch() async throws {
      let records = try await Record.all.limit(2).fetchAll(connection)
      #expect(records.count == 2)
    }

    @Test func offsetFetch() async throws {
      let records = try await Record.all.order(by: \.id).offset(1).fetchAll(connection)
      #expect(records.count == 2)
      #expect(records[0].id == 2)
    }

    @Test func countQuery() async throws {
      let count = try await Record.count.fetchOne(connection)
      #expect(count == 3)
    }

    @Test func selectColumn() async throws {
      let ids = try await Record.select(\.id).fetchAll(connection)
      #expect(ids == [1, 2, 3])
    }
  }

  @Table
  private struct Record: Equatable, Sendable {
    let id: Int
    let date: Date = Date(timeIntervalSince1970: 42)
  }

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
