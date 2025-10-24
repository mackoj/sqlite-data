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
struct FetchOneTests {
  #if SQLITE_ENGINE_GRDB
    @Dependency(\.defaultDatabase) var database
  #elseif SQLITE_ENGINE_SQLITENIO
    @Dependency(\.defaultSQLiteConnection) var connection
  #endif

  @Test func nonTableInit() {
    @FetchOne var value = 42
    #expect(value == 42)
    #expect($value.loadError == nil)
  }

  @Test func tableInit() async throws {
    #if SQLITE_ENGINE_GRDB
      @FetchOne var record = Record(id: 0)
      try await $record.load()
      #expect(record == Record(id: 1))
      #expect($record.loadError == nil)
      try await database.write { try Record.delete().execute($0) }
      await #expect(throws: NotFound.self) {
        try await $record.load()
      }
      #expect(record == Record(id: 1))
      #expect($record.loadError is NotFound)
    #elseif SQLITE_ENGINE_SQLITENIO
      @FetchOne var record = Record(id: 0, date: Date())
      try await $record.load()
      #expect(record.id == 1)
      #expect($record.loadError == nil)
      
      try await connection.query("DELETE FROM \"Record\"", [])
      await #expect(throws: NotFound.self) {
        try await $record.load()
      }
      #expect(record.id == 1)  // Value unchanged after error
      #expect($record.loadError is NotFound)
    #endif
  }

  @Test func optionalTableInit() async throws {
    #if SQLITE_ENGINE_GRDB
      @FetchOne var record: Record?
      try await $record.load()
      #expect(record == Record(id: 1))
      #expect($record.loadError == nil)
      try await database.write { try Record.delete().execute($0) }
      try await $record.load()
      #expect(record == nil)
      #expect($record.loadError == nil)
    #elseif SQLITE_ENGINE_SQLITENIO
      @FetchOne var record: Record?
      try await $record.load()
      #expect(record?.id == 1)
      #expect($record.loadError == nil)
      
      try await connection.query("DELETE FROM \"Record\"", [])
      try await $record.load()
      #expect(record == nil)
      #expect($record.loadError == nil)
    #endif
  }

  @Test func optionalTableInit_WithDefault() async throws {
    #if SQLITE_ENGINE_GRDB
      @FetchOne var record: Record? = Record(id: 0)
      try await $record.load()
      #expect(record == Record(id: 1))
      #expect($record.loadError == nil)
      try await database.write { try Record.delete().execute($0) }
      try await $record.load()
      #expect(record == nil)
      #expect($record.loadError == nil)
    #elseif SQLITE_ENGINE_SQLITENIO
      @FetchOne var record: Record? = Record(id: 0, date: Date())
      try await $record.load()
      #expect(record?.id == 1)
      #expect($record.loadError == nil)
      
      try await connection.query("DELETE FROM \"Record\"", [])
      try await $record.load()
      #expect(record == nil)
      #expect($record.loadError == nil)
    #endif
  }

  #if SQLITE_ENGINE_GRDB
    @Test func selectStatementInit() async throws {
      @FetchOne(Record.order(by: \.id)) var record = Record(id: 0)
      try await $record.load()
      #expect(record == Record(id: 1))
      #expect($record.loadError == nil)
      try await database.write { try Record.delete().execute($0) }
      await #expect(throws: NotFound.self) {
        try await $record.load()
      }
      #expect(record == Record(id: 1))
      #expect($record.loadError is NotFound)

      await #expect(throws: NotFound.self) {
        try await $record.load(Record.order(by: \.id))
      }
      #expect(record == Record(id: 1))
      #expect($record.loadError is NotFound)
    }

    @Test func statementInit_Representable() async throws {
      @FetchOne(Record.select(\.date)) var recordDate = Date(timeIntervalSince1970: 1729)
      try await $recordDate.load()
      #expect(recordDate.timeIntervalSince1970 == 42)
      #expect($recordDate.loadError == nil)
      try await database.write { try Record.delete().execute($0) }
      await #expect(throws: NotFound.self) {
        try await $recordDate.load()
      }
      #expect(recordDate.timeIntervalSince1970 == 42)
      #expect($recordDate.loadError is NotFound)

      await #expect(throws: NotFound.self) {
        try await $recordDate.load(Record.select(\.date))
      }
      #expect(recordDate.timeIntervalSince1970 == 42)
      #expect($recordDate.loadError is NotFound)
    }

    @Test func statementInit_OptionalRepresentable() async throws {
      @FetchOne(Record.select(\.date)) var recordDate: Date?
      try await $recordDate.load()
      #expect(recordDate?.timeIntervalSince1970 == 42)
      #expect($recordDate.loadError == nil)
      try await database.write { try Record.delete().execute($0) }
      try await $recordDate.load()
      #expect(recordDate?.timeIntervalSince1970 == nil)
      #expect($recordDate.loadError == nil)

      try await $recordDate.load(Record.select(\.date))
      #expect(recordDate?.timeIntervalSince1970 == nil)
      #expect($recordDate.loadError == nil)
    }

    @Test func statementInit_OptionalRepresentableWithDefault() async throws {
      @FetchOne(Record.select(\.date)) var recordDate: Date? = Date(timeIntervalSince1970: 1729)
      try await $recordDate.load()
      #expect(recordDate?.timeIntervalSince1970 == 42)
      #expect($recordDate.loadError == nil)
      try await database.write { try Record.delete().execute($0) }
      try await $recordDate.load()
      #expect(recordDate?.timeIntervalSince1970 == nil)
      #expect($recordDate.loadError == nil)

      try await $recordDate.load(Record.select(\.date))
      #expect(recordDate?.timeIntervalSince1970 == nil)
      #expect($recordDate.loadError == nil)
    }

    @Test func statementInit_Tuple() async throws {
      @FetchOne(Record.select { ($0.id, $0.date) }) var value = (0, Date(timeIntervalSince1970: 1729))
      try await $value.load()
      #expect(value.0 == 1)
      #expect(value.1.timeIntervalSince1970 == 42)
      #expect($value.loadError == nil)
      try await database.write { try Record.delete().execute($0) }
      await #expect(throws: NotFound.self) {
        try await $value.load()
      }
      #expect(value.0 == 1)
      #expect(value.1.timeIntervalSince1970 == 42)
      #expect($value.loadError is NotFound)

      await #expect(throws: NotFound.self) {
        try await $value.load(Record.select { ($0.id, $0.date) })
      }
      #expect(value.0 == 1)
      #expect(value.1.timeIntervalSince1970 == 42)
      #expect($value.loadError is NotFound)
    }

    @Test func statementInit_OptionalTuple() async throws {
      @FetchOne(Record.select { ($0.id, $0.date) }) var value: (Int, Date)?
      try await $value.load()
      #expect(value?.0 == 1)
      #expect(value?.1.timeIntervalSince1970 == 42)
      #expect($value.loadError == nil)
      try await database.write { try Record.delete().execute($0) }
      try await $value.load()
      #expect(value?.0 == nil)
      #expect(value?.1.timeIntervalSince1970 == nil)
      #expect($value.loadError == nil)
    }

    @Test func concurrency() async throws {
      await withThrowingTaskGroup { group in
        for _ in 0..<100 {
          group.addTask {
            @FetchOne var record: Record?
            try await $record.load()
            #expect(record?.id == 1)
          }
        }
      }
    }
  #elseif SQLITE_ENGINE_SQLITENIO
    @Test func selectStatementInit() async throws {
      @FetchOne(Record.order(by: \.id)) var record = Record(id: 0, date: Date())
      try await $record.load()
      #expect(record.id == 1)
      #expect($record.loadError == nil)
      
      try await connection.query("DELETE FROM \"Record\"", [])
      await #expect(throws: NotFound.self) {
        try await $record.load()
      }
      #expect(record.id == 1)
      #expect($record.loadError is NotFound)
      
      await #expect(throws: NotFound.self) {
        try await $record.load(Record.order(by: \.id))
      }
      #expect(record.id == 1)
      #expect($record.loadError is NotFound)
    }

    @Test func fetchFirst() async throws {
      @FetchOne(Record.order(by: \.id)) var record = Record(id: 0, date: Date())
      try await $record.load()
      #expect(record.id == 1)
    }

    @Test func fetchWithFilter() async throws {
      @FetchOne(Record.where { $0.id == 2 }) var record: Record?
      try await $record.load()
      #expect(record?.id == 2)
    }

    @Test func fetchNonExistent() async throws {
      @FetchOne(Record.where { $0.id == 999 }) var record: Record?
      try await $record.load()
      #expect(record == nil)
    }

    @Test func updateValue() async throws {
      @FetchOne(Record.where { $0.id == 1 }) var record: Record?
      try await $record.load()
      #expect(record?.id == 1)
      
      // Update the record
      try await connection.transaction { conn in
        try await conn.query(
          "UPDATE \"Record\" SET id = ? WHERE id = ?",
          [.integer(10), .integer(1)]
        )
      }
      
      try await $record.load()
      #expect(record == nil)  // Original query doesn't match anymore
    }
  #endif
}

#if SQLITE_ENGINE_GRDB
  @Table
  private struct Record: Equatable {
    let id: Int
    @Column(as: Date.UnixTimeRepresentation.self)
    var date = Date(timeIntervalSince1970: 42)
    @Column(as: Date?.UnixTimeRepresentation.self)
    var optionalDate: Date?
  }
  
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
  @Table
  private struct Record: Equatable, Sendable {
    let id: Int
    let date: Date
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
