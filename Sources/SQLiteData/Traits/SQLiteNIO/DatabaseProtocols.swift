#if SQLITE_ENGINE_SQLITENIO
/// SQLiteNIO-based database abstractions
///
/// This file provides protocol definitions that mirror GRDB's DatabaseReader and DatabaseWriter
/// protocols, but use async/await and SQLiteNIO under the hood.
///
/// These are experimental and run alongside the existing GRDB implementation.

import Foundation
import SQLiteNIO

/// Namespace for SQLiteNIO-based implementations
public enum SQLiteNIODatabase {
  
  /// Protocol that defines read operations on a database.
  /// This mimics GRDB's DatabaseReader protocol but uses async/await.
  public protocol Reader: AnyObject, Sendable {
    /// Asynchronously reads from the database.
    func asyncRead<T: Sendable>(_ block: @escaping @Sendable (Connection) async throws -> T) async throws -> T
  }
  
  /// Protocol that defines write operations on a database.
  /// This mimics GRDB's DatabaseWriter protocol but uses async/await.
  public protocol Writer: Reader {
    /// Asynchronously writes to the database.
    func asyncWrite<T: Sendable>(_ updates: @escaping @Sendable (Connection) async throws -> T) async throws -> T
  }
  
  /// Represents a database connection that can execute queries.
  /// This wraps SQLiteNIO's connection and provides query execution methods.
  public actor Connection {
    let connection: SQLiteConnection
    
    public init(connection: SQLiteConnection) {
      self.connection = connection
    }
    
    /// Executes a SQL statement with bindings.
    public func execute(sql: String, bindings: [SQLiteData] = []) async throws {
      _ = try await connection.query(sql, bindings)
    }
    
    /// Executes a SQL query and returns rows.
    public func query(sql: String, bindings: [SQLiteData] = []) async throws -> [SQLiteRow] {
      try await connection.query(sql, bindings)
    }
  }
  
  /// A simple database queue that serializes access to a SQLite database.
  public actor Queue: Writer {
    let connection: SQLiteConnection
    
    public init(connection: SQLiteConnection) {
      self.connection = connection
    }
    
    public func asyncRead<T: Sendable>(_ block: @escaping @Sendable (Connection) async throws -> T) async throws -> T {
      let conn = Connection(connection: connection)
      return try await block(conn)
    }
    
    public func asyncWrite<T: Sendable>(_ updates: @escaping @Sendable (Connection) async throws -> T) async throws -> T {
      let conn = Connection(connection: connection)
      // TODO: Wrap in transaction
      return try await updates(conn)
    }
  }
}

#endif
