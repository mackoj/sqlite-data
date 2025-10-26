#if SQLITE_ENGINE_GRDB
import ConcurrencyExtras
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
  /// This implementation uses the database from `@Dependency(\.defaultDatabase)`.
  ///
  /// Example:
  /// ```swift
  /// let client = SQLiteClient.grdb
  /// ```
  ///
  /// - Returns: A SQLiteClient backed by GRDB.
  public static var grdb: Self {
    Self(
      read: { block in
        @Dependency(\.defaultDatabase) var database
        // GRDB's async read takes a synchronous closure
        // We need to bridge to async by waiting for the sync closure to complete
        // then execute our async block
        try await database.read { _ in }
        try await block()
      },
      write: { block in
        @Dependency(\.defaultDatabase) var database
        // GRDB's async write takes a synchronous closure
        // We need to bridge to async by waiting for the sync closure to complete
        // then execute our async block
        try await database.write { _ in }
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
        @Dependency(\.defaultDatabase) var database
        
        // Create a value observation that watches for changes in the specified tables
        let observation = ValueObservation.tracking { db -> Int in
          // We just need to trigger on any change to these tables
          // The actual value doesn't matter, we just use a dummy query
          return try tables.map { table in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM \(table)") ?? 0
          }.reduce(0, +)
        }
        
        #if canImport(Combine)
        let cancellable = observation.publisher(in: database)
          .sink(
            receiveCompletion: { _ in },
            receiveValue: { _ in onChange() }
          )
        return CombineCancellableWrapper(cancellable: cancellable)
        #else
        return await MainActor.run {
          let cancellable = observation.start(
            in: database,
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
