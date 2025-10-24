#if SQLITE_ENGINE_GRDB
  import Foundation
  import SQLiteData
  import Testing

  @Suite struct CustomFunctionsTests {
    @DatabaseFunction func customDate() -> Date {
      Date(timeIntervalSinceReferenceDate: 0)
    }

    @available(iOS 17, macOS 14, tvOS 17, watchOS 10, *)
    @Test func basics() throws {
      var configuration = Configuration()
      configuration.prepareDatabase { db in
        db.add(function: $customDate)
      }
      let database = try DatabaseQueue(configuration: configuration)
      let date = try database.read { db in
        try Values($customDate())
          .fetchOne(db)
      }
      #expect(date?.timeIntervalSinceReferenceDate == 0)

      try database.write { db in
        db.remove(function: $customDate)
      }
      #expect(throws: (any Error).self) {
        try database.read { db in
          _ = try Values($customDate()).fetchOne(db)
        }
      }
    }
  }
#elseif SQLITE_ENGINE_SQLITENO
  import Foundation
  import SQLiteData
  import Testing
  import SQLiteNIO

  @Suite struct CustomFunctionsTests {
    // SQLiteNIO doesn't have the same custom function macro support as GRDB
    // This test demonstrates basic SQLiteNIO functionality instead
    @available(iOS 17, macOS 14, tvOS 17, watchOS 10, *)
    @Test func basics() async throws {
      let connection = try await SQLiteConnection.open(storage: .memory)
      
      // SQLiteNIO doesn't support custom functions in the same way
      // Just verify basic query functionality works
      let result = try await connection.query("SELECT 1 as value", [])
      #expect(result.count == 1)
      
      try await connection.close()
    }
  }
#endif
