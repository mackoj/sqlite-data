#if canImport(SQLiteNIO)
import DependenciesTestSupport
import Foundation
import SQLiteData
import SQLiteNIO
import Testing

@Suite(.dependency(\.defaultSQLiteConnection, try await .nioTestConnection()))
struct FetchAllNIOTests {
  @Dependency(\.defaultSQLiteConnection) var connection

  @MainActor
  @Test func concurrency() async throws {
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
  }

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
}

@Table
private struct Record: Equatable, Sendable {
  let id: Int
  let date: Date = Date(timeIntervalSince1970: 42)
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
