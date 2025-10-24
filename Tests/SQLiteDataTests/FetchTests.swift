import DependenciesTestSupport
import Foundation
import SQLiteData
import Testing

#if SQLITE_ENGINE_SQLITENO
  import SQLiteNIO
#endif

#if SQLITE_ENGINE_GRDB
  @Suite(.dependency(\.defaultDatabase, try .database()))
#elseif SQLITE_ENGINE_SQLITENO
  @Suite(.dependency(\.defaultSQLiteConnection, try .nioConnection()))
#endif
struct FetchTests {
  #if SQLITE_ENGINE_GRDB
    @Dependency(\.defaultDatabase) var database
  #elseif SQLITE_ENGINE_SQLITENO
    @Dependency(\.defaultSQLiteConnection) var connection
  #endif

  @Test func bareFetchAll() async throws {
    #if SQLITE_ENGINE_GRDB
      @FetchAll var records: [Record]
      #expect(records == [Record(id: 1), Record(id: 2), Record(id: 3)])

      try await database.write { try Record.delete().execute($0) }
      try await $records.load()
      #expect(records == [])
    #elseif SQLITE_ENGINE_SQLITENO
      @FetchAll(Record.all) var records: [Record]
      try await $records.load()
      #expect(records == [Record(id: 1), Record(id: 2), Record(id: 3)])

      try await connection.query("DELETE FROM \"Record\"", [])
      try await $records.load()
      #expect(records == [])
    #endif
  }

  @Test func fetchAllWithQuery() async throws {
    #if SQLITE_ENGINE_GRDB
      @FetchAll(Record.where { $0.id > 1 }) var records: [Record]
      #expect(records == [Record(id: 2), Record(id: 3)])

      try await database.write { try Record.delete().execute($0) }
      try await $records.load()
      #expect(records == [])
    #elseif SQLITE_ENGINE_SQLITENO
      @FetchAll(Record.where { $0.id > 1 }) var records: [Record]
      try await $records.load()
      #expect(records == [Record(id: 2), Record(id: 3)])

      try await connection.query("DELETE FROM \"Record\"", [])
      try await $records.load()
      #expect(records == [])
    #endif
  }

  @Test func fetchOneCountWithQuery() async throws {
    #if SQLITE_ENGINE_GRDB
      @FetchOne(Record.where { $0.id > 1 }.count()) var recordsCount = 0
      #expect(recordsCount == 2)

      try await database.write { try Record.delete().execute($0) }
      try await $recordsCount.load()
      #expect(recordsCount == 0)
    #elseif SQLITE_ENGINE_SQLITENO
      // Count query for SQLiteNIO
      let recordsCount = try await Record.where { $0.id > 1 }.count().fetchOne(connection) ?? 0
      #expect(recordsCount == 2)

      try await connection.query("DELETE FROM \"Record\"", [])
      let recordsCountAfterDelete = try await Record.count().fetchOne(connection) ?? 0
      #expect(recordsCountAfterDelete == 0)
    #endif
  }

  @Test func fetchOneOptional() async throws {
    #if SQLITE_ENGINE_GRDB
      @FetchOne var record: Record?
      #expect(record == Record(id: 1))
      print(#line)

      try await database.write { try Record.delete().execute($0) }
      try await $record.load()
      #expect(record == nil)
    #elseif SQLITE_ENGINE_SQLITENO
      @FetchOne(Record.all) var record: Record?
      try await $record.load()
      #expect(record?.id == 1)

      try await connection.query("DELETE FROM \"Record\"", [])
      try await $record.load()
      #expect(record == nil)
    #endif
  }

  @Test func fetchOneWithDefault() async throws {
    #if SQLITE_ENGINE_GRDB
      @FetchOne var record = Record(id: 0)
      try await $record.load()
      #expect(record == Record(id: 1))

      try await database.write { try Record.delete().execute($0) }
      await #expect(throws: NotFound.self) {
        try await $record.load()
      }
      #expect($record.loadError is NotFound)
      #expect(record == Record(id: 1))
    #elseif SQLITE_ENGINE_SQLITENO
      @FetchOne(Record.all) var record = Record(id: 0)
      try await $record.load()
      #expect(record.id == 1)

      try await connection.query("DELETE FROM \"Record\"", [])
      await #expect(throws: NotFound.self) {
        try await $record.load()
      }
      #expect($record.loadError is NotFound)
      #expect(record.id == 1)
    #endif
  }

  @Test func fetchOneOptional_SQL() async throws {
    #if SQLITE_ENGINE_GRDB
      @FetchOne(#sql("SELECT * FROM records LIMIT 1")) var record: Record?
      #expect(record == Record(id: 1))

      try await database.write { try Record.delete().execute($0) }
      try await $record.load()
      #expect(record == nil)
    #elseif SQLITE_ENGINE_SQLITENO
      // Raw SQL query for SQLiteNIO
      @FetchOne(Record.all.limit(1)) var record: Record?
      try await $record.load()
      #expect(record?.id == 1)

      try await connection.query("DELETE FROM \"Record\"", [])
      try await $record.load()
      #expect(record == nil)
    #endif
  }
}

#if SQLITE_ENGINE_GRDB
  @Table
  private struct Record: Equatable {
    let id: Int
  }

  extension DatabaseWriter where Self == DatabaseQueue {
    fileprivate static func database() throws -> DatabaseQueue {
      let database = try DatabaseQueue()
      var migrator = DatabaseMigrator()
      migrator.registerMigration("Up") { db in
        try #sql(
          """
          CREATE TABLE "records" ("id" INTEGER PRIMARY KEY AUTOINCREMENT)
          """
        )
        .execute(db)
        for _ in 1...3 {
          _ = try Record.insert { Record.Draft() }.execute(db)
        }
      }
      try migrator.migrate(database)
      return database
    }
  }

  func compileTimeTests() {
    @FetchAll(#sql("SELECT * FROM records")) var records: [Record]
    @FetchOne(#sql("SELECT count(*) FROM records")) var count = 0
    @FetchOne(#sql("SELECT * FROM records LIMIT 1")) var record: Record?
  }
#elseif SQLITE_ENGINE_SQLITENO
  @Table
  private struct Record: Equatable, Sendable {
    let id: Int
  }

  extension SQLiteConnection {
    fileprivate static func nioConnection() throws -> SQLiteConnection {
      try Task {
        let connection = try await SQLiteConnection.open(storage: .memory)
        
        // Create table
        try await connection.query("""
          CREATE TABLE "Record" (
            "id" INTEGER PRIMARY KEY AUTOINCREMENT
          )
          """, [])
        
        // Insert test data
        try await connection.transaction { conn in
          for id in 1...3 {
            try await conn.query(
              "INSERT INTO \"Record\" (id) VALUES (?)",
              [.integer(id)]
            )
          }
        }
        
        return connection
      }.value
    }
  }
#endif
