#if SQLITE_ENGINE_GRDB
import Dependencies
import Foundation
import GRDB

#if canImport(Combine)
  import Combine
#endif

// MARK: - GRDB Cancellable Wrapper

private struct GRDBCancellable: SQLiteCancellable {
  let cancellable: DatabaseCancellable
  
  func cancel() {
    cancellable.cancel()
  }
}

#if canImport(Combine)
private struct CombineCancellableWrapper: SQLiteCancellable {
  let cancellable: AnyCancellable
  
  func cancel() {
    cancellable.cancel()
  }
}
#endif

// MARK: - SQLiteClient GRDB Implementation

extension SQLiteClient {
  /// Creates a SQLiteClient backed by GRDB.
  ///
  /// This implementation uses GRDB's database pool or queue for all operations.
  ///
  /// Example:
  /// ```swift
  /// let database = try DatabasePool(path: "path/to/db.sqlite")
  /// let client = SQLiteClient.grdb(database: database)
  /// ```
  ///
  /// - Parameter database: A GRDB database reader (typically a DatabasePool or DatabaseQueue).
  /// - Returns: A SQLiteClient backed by GRDB.
  public static func grdb(database: any GRDB.DatabaseReader) -> Self {
    Self(
      read: { block in
        try await database.read { _ in
          // The block is async, but GRDB's closure is sync, so we need to use Task
        }
        // Execute the async block after the database read completes
        try await block()
      },
      write: { block in
        guard let writer = database as? any GRDB.DatabaseWriter else {
          throw SQLiteClientError.readOnlyDatabase
        }
        try await writer.write { _ in
          // The block is async, but GRDB's closure is sync, so we need to use Task
        }
        // Execute the async block after the database write completes
        try await block()
      },
      contextSensitivePath: {
        @Dependency(\.context) var context
        switch context {
        case .live:
          let applicationSupportDirectory = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
          )
          return applicationSupportDirectory.appendingPathComponent("SQLiteData.db").path
        case .preview:
          return nil  // In-memory
        case .test:
          return "\(NSTemporaryDirectory())\(UUID().uuidString).db"
        }
      },
      observeTables: { tables, onChange in
        guard let writer = database as? any GRDB.DatabaseWriter else {
          throw SQLiteClientError.observationRequiresWriter
        }
        
        // Create a value observation that watches for changes in the specified tables
        let observation = ValueObservation.tracking { db -> Int in
          // We just need to trigger on any change to these tables
          // The actual value doesn't matter, we just use a dummy query
          return try tables.map { table in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM \(table)") ?? 0
          }.reduce(0, +)
        }
        
        #if canImport(Combine)
        let cancellable = observation.publisher(in: writer)
          .sink(
            receiveCompletion: { _ in },
            receiveValue: { _ in onChange() }
          )
        return CombineCancellableWrapper(cancellable: cancellable)
        #else
        return await MainActor.run {
          let cancellable = observation.start(
            in: writer,
            onError: { _ in },
            onChange: { _ in onChange() }
          )
          return GRDBCancellable(cancellable: cancellable)
        }
        #endif
      }
    )
  }
}

// MARK: - Errors

public enum SQLiteClientError: Error {
  case readOnlyDatabase
  case observationRequiresWriter
}

#endif
