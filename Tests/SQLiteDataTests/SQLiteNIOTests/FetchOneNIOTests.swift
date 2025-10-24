#if canImport(SQLiteNIO)
import DependenciesTestSupport
import Foundation
import SQLiteData
import SQLiteNIO
import Testing

@Suite(.dependency(\.defaultSQLiteConnection, try await .nioTestConnection()))
struct FetchOneNIOTests {
  @Dependency(\.defaultSQLiteConnection) var connection

  @Test func nonTableInit() {
    @FetchOne var value = 42
    #expect(value == 42)
    #expect($value.loadError == nil)
  }

  @Test func tableInit() async throws {
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
  }

  @Test func optionalTableInit() async throws {
    @FetchOne var record: Record?
    try await $record.load()
    #expect(record?.id == 1)
    #expect($record.loadError == nil)
    
    try await connection.query("DELETE FROM \"Record\"", [])
    try await $record.load()
    #expect(record == nil)
    #expect($record.loadError == nil)
  }

  @Test func optionalTableInit_WithDefault() async throws {
    @FetchOne var record: Record? = Record(id: 0, date: Date())
    try await $record.load()
    #expect(record?.id == 1)
    #expect($record.loadError == nil)
    
    try await connection.query("DELETE FROM \"Record\"", [])
    try await $record.load()
    #expect(record == nil)
    #expect($record.loadError == nil)
  }

  @Test func selectStatementInit() async throws {
    @FetchOne(Record.order(by: \.id)) var record = Record(id: 0, date: Date())
    try await $record.load()
    #expect(record.id == 1)
    #expect($record.loadError == nil)
    
    try await connection.query("DELETE FROM \"Record\"", [])
    await #expect(throws: NotFound.self) {
      try await $record.load()
    }
    #expect(record.id == 1)  // Value unchanged after error
    #expect($record.loadError is NotFound)

    await #expect(throws: NotFound.self) {
      try await $record.load(Record.order(by: \.id))
    }
    #expect(record.id == 1)
    #expect($record.loadError is NotFound)
  }

  @Test func countQuery() async throws {
    @FetchOne(Record.count) var count = 0
    try await $count.load()
    #expect(count == 3)
    #expect($count.loadError == nil)
  }

  @Test func specificRecord() async throws {
    @FetchOne(Record.where { $0.id == 2 }) var record: Record?
    try await $record.load()
    #expect(record?.id == 2)
    #expect($record.loadError == nil)
  }

  @Test func nonExistentRecord() async throws {
    @FetchOne(Record.where { $0.id == 999 }) var record: Record?
    try await $record.load()
    #expect(record == nil)
    #expect($record.loadError == nil)
  }
}

@Table
private struct Record: Equatable, Sendable {
  let id: Int
  let date: Date
}

extension SQLiteConnection {
  fileprivate static func nioTestConnection() async throws -> SQLiteConnection {
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
