#if SQLITE_ENGINE_SQLITENIO
import Dependencies
import Foundation
import SQLiteNIO

// MARK: - SQLiteNIO Cancellable Wrapper

private final class NIOCancellable: SQLiteCancellable, @unchecked Sendable {
  private let _cancel: @Sendable () -> Void
  
  init(cancel: @escaping @Sendable () -> Void) {
    self._cancel = cancel
  }
  
  func cancel() {
    _cancel()
  }
}

// MARK: - SQLiteClient SQLiteNIO Implementation

extension SQLiteClient {
  /// Creates a SQLiteClient backed by SQLiteNIO.
  ///
  /// This implementation uses the connection from `@Dependency(\.defaultSQLiteConnection)`.
  ///
  /// Example:
  /// ```swift
  /// let client = SQLiteClient.nio
  /// ```
  ///
  /// - Returns: A SQLiteClient backed by SQLiteNIO.
  public static var nio: Self {
    Self(
      read: { block in
        try await block()
      },
      write: { block in
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
          return nil  // In-memory (use .memory storage)
        case .test:
          return "\(NSTemporaryDirectory())\(UUID().uuidString).db"
        }
      },
      observeTables: { tables, onChange in
        @Dependency(\.defaultSQLiteConnection) var connection
        
        // Create an observer for the specified tables
        let observer = SQLiteNIOObserver(connection: connection)
        
        // Subscribe to changes
        let subscription = try await observer.subscribe(tables: tables) { _ in
          onChange()
        }
        
        return NIOCancellable {
          subscription.cancel()
        }
      }
    )
  }
}

#endif
