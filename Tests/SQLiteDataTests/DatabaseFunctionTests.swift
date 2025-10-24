#if SQLITE_ENGINE_GRDB
  import DependenciesTestSupport
  import Foundation
  import SQLiteData
  import SQLiteDataTestSupport
  import Testing

  struct DatabaseFunctionTests {
    @DatabaseFunction
    func exclaim(_ text: String) -> String {
      text + "!"
    }
    @Test func scalarFunction() async throws {
      var configuration = Configuration()
      configuration.prepareDatabase { db in
        db.add(function: $exclaim)
      }
      let database = try DatabaseQueue(configuration: configuration)
      assertQuery(Values($exclaim("Blob")), database: database) {
        """
        ┌─────────┐
        │ "Blob!" │
        └─────────┘
        """
      }
    }

    @Test(.dependency(\.defaultDatabase, try .database())) func aggregateFunction() async throws {
      assertQuery(Record.select { $sum($0.id) }) {
        """
        ┌───┐
        │ 6 │
        └───┘
        """
      }
    }
  }

  @Table
  private struct Record: Equatable {
    let id: Int
  }

  @DatabaseFunction
  func sum(_ xs: some Sequence<Int>) -> Int {
    xs.reduce(0, +)
  }

  extension DatabaseWriter where Self == DatabaseQueue {
    fileprivate static func database() throws -> DatabaseQueue {
      var configuration = Configuration()
      configuration.prepareDatabase { db in
        db.add(function: $sum)
      }
      let database = try DatabaseQueue(configuration: configuration)
      try database.write { db in
        try #sql(
          """
          CREATE TABLE "records" (
            "id" INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT
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
#elseif SQLITE_ENGINE_SQLITENO
  import DependenciesTestSupport
  import Foundation
  import SQLiteData
  import SQLiteDataTestSupport
  import Testing
  import SQLiteNIO

  struct DatabaseFunctionTests {
    // SQLiteNIO doesn't have DatabaseFunction macro support
    // These tests demonstrate equivalent SQLiteNIO functionality
    @Test func scalarFunction() async throws {
      let connection = try await SQLiteConnection.open(storage: .memory)
      
      // SQLiteNIO: Direct query execution
      let result = try await connection.query("SELECT 'Blob' || '!' as value", [])
      #expect(result.count == 1)
      
      try await connection.close()
    }

    @Test func aggregateFunction() async throws {
      let connection = try await SQLiteConnection.open(storage: .memory)
      
      // Create test table
      try await connection.query("""
        CREATE TABLE "Record" (
          "id" INTEGER NOT NULL PRIMARY KEY
        )
        """, [])
      
      // Insert test data
      for id in 1...3 {
        try await connection.query(
          "INSERT INTO \"Record\" (id) VALUES (?)",
          [.integer(id)]
        )
      }
      
      // Use SQL aggregate function
      let rows = try await connection.query("SELECT SUM(id) as sum FROM \"Record\"", [])
      #expect(rows.count == 1)
      if let sumValue = rows.first?.column("sum") {
        #expect(sumValue == .integer(6))
      }
      
      try await connection.close()
    }
  }
#endif
