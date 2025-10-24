import Foundation

#if canImport(SQLiteNIO)
import SQLiteNIO

/// Transaction support for SQLiteNIO connections
extension SQLiteConnection {
  
  /// Execute a block within a database transaction.
  ///
  /// If the block throws an error, the transaction is rolled back.
  /// Otherwise, it is committed.
  ///
  /// ```swift
  /// try await connection.transaction { conn in
  ///   try await conn.query("INSERT INTO users (name) VALUES (?)", [.text("Alice")])
  ///   try await conn.query("INSERT INTO posts (title) VALUES (?)", [.text("Hello")])
  ///   // Both queries succeed or both are rolled back
  /// }
  /// ```
  ///
  /// - Parameter body: The block to execute within the transaction.
  /// - Returns: The value returned by the block.
  /// - Throws: Any error thrown by the block or database operations.
  public func transaction<T>(
    _ body: (SQLiteConnection) async throws -> T
  ) async throws -> T {
    // Begin transaction
    try await self.query("BEGIN TRANSACTION", [])
    
    do {
      // Execute the body
      let result = try await body(self)
      
      // Commit on success
      try await self.query("COMMIT TRANSACTION", [])
      
      return result
    } catch {
      // Rollback on error
      try? await self.query("ROLLBACK TRANSACTION", [])
      throw error
    }
  }
  
  /// Execute a block within a deferred database transaction.
  ///
  /// A deferred transaction doesn't acquire locks until the first read or write operation.
  ///
  /// - Parameter body: The block to execute within the transaction.
  /// - Returns: The value returned by the block.
  /// - Throws: Any error thrown by the block or database operations.
  public func deferredTransaction<T>(
    _ body: (SQLiteConnection) async throws -> T
  ) async throws -> T {
    try await self.query("BEGIN DEFERRED TRANSACTION", [])
    
    do {
      let result = try await body(self)
      try await self.query("COMMIT TRANSACTION", [])
      return result
    } catch {
      try? await self.query("ROLLBACK TRANSACTION", [])
      throw error
    }
  }
  
  /// Execute a block within an immediate database transaction.
  ///
  /// An immediate transaction acquires a write lock immediately,
  /// even before any write operations.
  ///
  /// - Parameter body: The block to execute within the transaction.
  /// - Returns: The value returned by the block.
  /// - Throws: Any error thrown by the block or database operations.
  public func immediateTransaction<T>(
    _ body: (SQLiteConnection) async throws -> T
  ) async throws -> T {
    try await self.query("BEGIN IMMEDIATE TRANSACTION", [])
    
    do {
      let result = try await body(self)
      try await self.query("COMMIT TRANSACTION", [])
      return result
    } catch {
      try? await self.query("ROLLBACK TRANSACTION", [])
      throw error
    }
  }
  
  /// Execute a block within an exclusive database transaction.
  ///
  /// An exclusive transaction prevents all other database connections
  /// from reading or writing while the transaction is active.
  ///
  /// - Parameter body: The block to execute within the transaction.
  /// - Returns: The value returned by the block.
  /// - Throws: Any error thrown by the block or database operations.
  public func exclusiveTransaction<T>(
    _ body: (SQLiteConnection) async throws -> T
  ) async throws -> T {
    try await self.query("BEGIN EXCLUSIVE TRANSACTION", [])
    
    do {
      let result = try await body(self)
      try await self.query("COMMIT TRANSACTION", [])
      return result
    } catch {
      try? await self.query("ROLLBACK TRANSACTION", [])
      throw error
    }
  }
  
  /// Create a savepoint and execute a block within it.
  ///
  /// Savepoints allow you to create nested transactions. If the block throws,
  /// the savepoint is rolled back but the outer transaction continues.
  ///
  /// ```swift
  /// try await connection.transaction { conn in
  ///   try await conn.query("INSERT INTO users (name) VALUES (?)", [.text("Alice")])
  ///   
  ///   try? await conn.savepoint("inner") { conn in
  ///     try await conn.query("INSERT INTO posts (title) VALUES (?)", [.text("Bad Post")])
  ///     throw SomeError() // This rolls back only the inner savepoint
  ///   }
  ///   
  ///   // Alice is still inserted even if inner savepoint failed
  /// }
  /// ```
  ///
  /// - Parameters:
  ///   - name: The name of the savepoint.
  ///   - body: The block to execute within the savepoint.
  /// - Returns: The value returned by the block.
  /// - Throws: Any error thrown by the block or database operations.
  public func savepoint<T>(
    _ name: String = "savepoint",
    _ body: (SQLiteConnection) async throws -> T
  ) async throws -> T {
    // Create savepoint
    try await self.query("SAVEPOINT \(name)", [])
    
    do {
      // Execute the body
      let result = try await body(self)
      
      // Release savepoint on success
      try await self.query("RELEASE SAVEPOINT \(name)", [])
      
      return result
    } catch {
      // Rollback to savepoint on error
      try? await self.query("ROLLBACK TO SAVEPOINT \(name)", [])
      throw error
    }
  }
}

#endif
