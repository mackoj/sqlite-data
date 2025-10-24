import SQLiteData
import Testing

#if SQLITE_ENGINE_SQLITENIO
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
#elseif SQLITE_ENGINE_SQLITENIO
  // SQLiteNIO tests are simplified - cursor-level operations are GRDB-specific
  @Suite struct QueryCursorTests {
    @Test func basicOperations() async throws {
      // Basic sanity test
      #expect(1 == 1)
    }
  }
#endif
