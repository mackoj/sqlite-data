#if SQLITE_ENGINE_GRDB
  import Foundation
  import SQLiteData
  import Testing

  @Suite struct MigrationTests {
    @available(iOS 15, *)
    @Test func dates() throws {
      let database = try DatabaseQueue()
      try database.write { db in
        try #sql(
          """
          CREATE TABLE "models" (
            "date" TEXT NOT NULL
          )
          """
        )
        .execute(db)
      }

      let timestamp = 123.456
      try database.write { db in
        try db.execute(
          literal: "INSERT INTO models (date) VALUES (\(Date(timeIntervalSince1970: timestamp)))"
        )
      }
      try database.read { db in
        let grdbDate = try Date.fetchOne(db, sql: "SELECT * FROM models")
        try #expect(abs(#require(grdbDate).timeIntervalSince1970 - timestamp) < 0.001)

        let date = try #require(try Model.all.fetchOne(db)).date
        #expect(abs(date.timeIntervalSince1970 - timestamp) < 0.001)
      }
    }
  }

  @available(iOS 15, *)
  @Table private struct Model {
    var date: Date
  }
#elseif SQLITE_ENGINE_SQLITENO
  import Foundation
  import SQLiteData
  import Testing
  import SQLiteNIO

  @Suite struct MigrationTests {
    @available(iOS 15, *)
    @Test func dates() async throws {
      let connection = try await SQLiteConnection.open(storage: .memory)
      
      // Create table
      try await connection.query("""
        CREATE TABLE "Model" (
          "date" TEXT NOT NULL
        )
        """, [])
      
      let timestamp = 123.456
      let date = Date(timeIntervalSince1970: timestamp)
      
      // Insert date
      try await connection.query(
        "INSERT INTO \"Model\" (date) VALUES (?)",
        [.text(date.iso8601String)]
      )
      
      // Fetch and verify
      let rows = try await connection.query("SELECT date FROM \"Model\"", [])
      #expect(rows.count == 1)
      
      if let dateStr = rows.first?.column("date"), case .text(let text) = dateStr {
        if let fetchedDate = Date(iso8601String: text) {
          #expect(abs(fetchedDate.timeIntervalSince1970 - timestamp) < 0.001)
        }
      }
      
      try await connection.close()
    }
  }
#endif
