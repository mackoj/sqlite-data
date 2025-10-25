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
  /// This implementation uses SQLiteNIO's connection for all operations.
  ///
  /// Example:
  /// ```swift
  /// let connection = try await SQLiteConnection.open(path: "path/to/db.sqlite")
  /// let client = SQLiteClient.nio(connection: connection)
  /// ```
  ///
  /// - Parameter connection: A SQLiteNIO connection.
  /// - Returns: A SQLiteClient backed by SQLiteNIO.
  public static func nio(connection: SQLiteConnection) -> Self {
    Self(
      read: { block in
        // For SQLiteNIO, reads go directly - operations are performed in the block
        try await block()
      },
      write: { block in
        // For SQLiteNIO, writes also go directly
        // The connection handles concurrency internally
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
  
  /// Creates a context-sensitive SQLiteNIO connection.
  ///
  /// This is a helper method that creates a connection based on the current dependency context:
  /// - In live context: Uses a file-based database in the application support directory
  /// - In preview context: Uses an in-memory database
  /// - In test context: Uses a temporary file
  ///
  /// Example:
  /// ```swift
  /// let client = try await SQLiteClient.nioDefault()
  /// ```
  ///
  /// - Returns: A SQLiteClient backed by a context-appropriate SQLiteNIO connection.
  public static func nioDefault() async throws -> Self {
    @Dependency(\.context) var context
    
    let connection: SQLiteConnection
    switch context {
    case .live:
      let applicationSupportDirectory = try FileManager.default.url(
        for: .applicationSupportDirectory,
        in: .userDomainMask,
        appropriateFor: nil,
        create: true
      )
      let path = applicationSupportDirectory.appendingPathComponent("SQLiteData.db").path
      connection = try await SQLiteConnection.open(storage: .file(path: path))
      
    case .preview:
      connection = try await SQLiteConnection.open(storage: .memory)
      
    case .test:
      let path = "\(NSTemporaryDirectory())\(UUID().uuidString).db"
      connection = try await SQLiteConnection.open(storage: .file(path: path))
    }
    
    return .nio(connection: connection)
  }
}

#endif
