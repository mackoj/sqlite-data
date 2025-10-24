import DependenciesTestSupport
import Foundation
import SQLiteData
import Testing

#if SQLITE_ENGINE_SQLITENIO
  import SQLiteNIO
#endif

#if SQLITE_ENGINE_GRDB
  @Suite(.dependency(\.defaultDatabase, try .syncUps()))
#elseif SQLITE_ENGINE_SQLITENIO
  @Suite(.dependency(\.defaultSQLiteConnection, try .nioTestConnection()))
#endif
struct IntegrationTests {
  #if SQLITE_ENGINE_GRDB
    @Dependency(\.defaultDatabase) var database
  #elseif SQLITE_ENGINE_SQLITENIO
    @Dependency(\.defaultSQLiteConnection) var connection
  #endif

  #if SQLITE_ENGINE_GRDB
    @Test
    func fetchAll_SQLString() async throws {
      @FetchAll(SyncUp.where(\.isActive)) var syncUps: [SyncUp]
      #expect(syncUps == [])

      try await database.write { db in
        _ = try SyncUp.insert { SyncUp.Draft(isActive: true, title: "Engineering") }
          .execute(db)
      }
      try await $syncUps.load()
      #expect(syncUps == [SyncUp(id: 1, isActive: true, title: "Engineering")])
      try await database.write { db in
        _ = try SyncUp.upsert { SyncUp.Draft(id: 1, isActive: false, title: "Engineering") }
          .execute(db)
      }
      try await $syncUps.load()
      #expect(syncUps == [])
      try await database.write { db in
        _ = try SyncUp.upsert { SyncUp.Draft(id: 1, isActive: true, title: "Engineering") }
          .execute(db)
      }
      try await $syncUps.load()
      #expect(syncUps == [SyncUp(id: 1, isActive: true, title: "Engineering")])
    }

    @Test
    func fetch_FetchKeyRequest() async throws {
      @Fetch(ActiveSyncUps()) var syncUps: [SyncUp] = []
      #expect(syncUps == [])

      try await database.write { db in
        _ = try SyncUp.insert { SyncUp.Draft(isActive: true, title: "Engineering") }
          .execute(db)
      }
      try await $syncUps.load()
      #expect(syncUps == [SyncUp(id: 1, isActive: true, title: "Engineering")])
      try await database.write { db in
        _ = try SyncUp.upsert { SyncUp.Draft(id: 1, isActive: false, title: "Engineering") }
          .execute(db)
      }
      try await $syncUps.load()
      #expect(syncUps == [])
      try await database.write { db in
        _ = try SyncUp.upsert { SyncUp.Draft(id: 1, isActive: true, title: "Engineering") }
          .execute(db)
      }
      try await $syncUps.load()
      #expect(syncUps == [SyncUp(id: 1, isActive: true, title: "Engineering")])
    }
  #elseif SQLITE_ENGINE_SQLITENIO
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
  #endif
}

#if SQLITE_ENGINE_GRDB
  @Table
  private struct SyncUp: Equatable, Identifiable {
    let id: Int
    var isActive: Bool
    var title: String
  }

  @Table
  private struct Attendee: Equatable {
    let id: Int
    var name: String
    var syncUpID: SyncUp.ID
  }

  extension DatabaseWriter where Self == DatabaseQueue {
    fileprivate static func syncUps() throws -> Self {
      let database = try DatabaseQueue()
      var migrator = DatabaseMigrator()
      migrator.registerMigration("Create schema") { db in
        try #sql(
          """
          CREATE TABLE "syncUps" (
            "id" INTEGER PRIMARY KEY AUTOINCREMENT,
            "isActive" INTEGER NOT NULL,
            "title" TEXT NOT NULL
          )
          """
        )
        .execute(db)
        try #sql(
          """
          CREATE TABLE "attendees" (
            "id" INTEGER PRIMARY KEY AUTOINCREMENT,
            "syncUpID" INTEGER NOT NULL,
            "name" TEXT NOT NULL,

            FOREIGN KEY("syncUpID") REFERENCES "syncUps"("id")
          )
          """
        )
        .execute(db)
      }
      try migrator.migrate(database)
      return database
    }
  }

  private struct ActiveSyncUps: FetchKeyRequest {
    func fetch(_ db: Database) throws -> [SyncUp] {
      try SyncUp
        .where(\.isActive)
        .fetchAll(db)
    }
  }
#elseif SQLITE_ENGINE_SQLITENIO
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
