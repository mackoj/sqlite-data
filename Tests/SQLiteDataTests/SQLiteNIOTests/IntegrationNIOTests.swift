#if canImport(SQLiteNIO)
import DependenciesTestSupport
import Foundation
import SQLiteData
import SQLiteNIO
import Testing

@Suite(.dependency(\.defaultSQLiteConnection, try .nioTestConnection()))
struct IntegrationNIOTests {
  @Dependency(\.defaultSQLiteConnection) var connection

  @Test func insertAndFetch() async throws {
    // Insert a new record
    _ = try await connection.transaction { conn in
      try await conn.query(
        "INSERT INTO \"User\" (name, email) VALUES (?, ?)",
        [.text("Alice"), .text("alice@example.com")]
      )
    }

    // Fetch using property wrapper
    @FetchAll(User.all) var users
    try await $users.load()
    
    #expect(users.count == 4)  // 3 initial + 1 new
    #expect(users.contains { $0.name == "Alice" })
  }

  @Test func updateAndFetch() async throws {
    // Update a record
    _ = try await connection.transaction { conn in
      try await conn.query(
        "UPDATE \"User\" SET name = ? WHERE id = ?",
        [.text("Updated User"), .integer(1)]
      )
    }

    // Fetch the updated record
    @FetchOne(User.where { $0.id == 1 }) var user: User?
    try await $user.load()
    
    #expect(user?.name == "Updated User")
  }

  @Test func deleteAndFetch() async throws {
    // Delete a record
    _ = try await connection.transaction { conn in
      try await conn.query(
        "DELETE FROM \"User\" WHERE id = ?",
        [.integer(2)]
      )
    }

    // Verify deletion
    @FetchAll(User.all) var users
    try await $users.load()
    
    #expect(users.count == 2)
    #expect(!users.contains { $0.id == 2 })
  }

  @Test func complexQuery() async throws {
    @FetchAll(
      User
        .where { $0.name != "User 1" }
        .order(by: \.name)
    ) var users
    
    try await $users.load()
    
    #expect(users.count == 2)
    #expect(users[0].name < users[1].name)
  }

  @Test func countAggregate() async throws {
    let count = try await User.count.fetchOne(connection) ?? 0
    #expect(count == 3)
  }

  @Test func transactionRollback() async throws {
    let initialCount = try await User.count.fetchOne(connection) ?? 0
    
    // Attempt a transaction that will fail
    do {
      _ = try await connection.transaction { conn in
        try await conn.query(
          "INSERT INTO \"User\" (name, email) VALUES (?, ?)",
          [.text("Temp User"), .text("temp@example.com")]
        )
        
        // Force an error
        throw TestError.intentional
      }
    } catch TestError.intentional {
      // Expected error
    }
    
    // Verify rollback
    let finalCount = try await User.count.fetchOne(connection) ?? 0
    #expect(finalCount == initialCount)
  }

  @Test func savepoint() async throws {
    _ = try await connection.transaction { conn in
      // Insert in main transaction
      try await conn.query(
        "INSERT INTO \"User\" (name, email) VALUES (?, ?)",
        [.text("Main User"), .text("main@example.com")]
      )
      
      // Try savepoint that fails
      do {
        _ = try await conn.savepoint("test") { conn in
          try await conn.query(
            "INSERT INTO \"User\" (name, email) VALUES (?, ?)",
            [.text("Savepoint User"), .text("savepoint@example.com")]
          )
          throw TestError.intentional
        }
      } catch TestError.intentional {
        // Savepoint rolled back
      }
      
      // Main transaction should still succeed
    }
    
    @FetchAll(User.all) var users
    try await $users.load()
    
    #expect(users.contains { $0.name == "Main User" })
    #expect(!users.contains { $0.name == "Savepoint User" })
  }
}

@Table
private struct User: Equatable, Sendable {
  let id: Int
  let name: String
  let email: String
}

private enum TestError: Error {
  case intentional
}

extension SQLiteConnection {
  fileprivate static func nioTestConnection() throws -> SQLiteConnection {
    try Task {
      let connection = try await SQLiteConnection.open(storage: .memory)
      
      // Create table
      try await connection.query("""
        CREATE TABLE "User" (
          "id" INTEGER PRIMARY KEY AUTOINCREMENT,
          "name" TEXT NOT NULL,
          "email" TEXT NOT NULL
        )
        """, [])
      
      // Insert test data
      try await connection.transaction { conn in
        for id in 1...3 {
          try await conn.query(
            "INSERT INTO \"User\" (name, email) VALUES (?, ?)",
            [.text("User \(id)"), .text("user\(id)@example.com")]
          )
        }
      }
      
      return connection
    }.value
  }
}
#endif
