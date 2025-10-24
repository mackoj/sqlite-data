/// Example Usage of SQLiteNIO Integration
///
/// This file provides examples of how to use the SQLiteNIO-based database abstractions.
/// These examples are for documentation purposes and are not meant to be run directly.

import Foundation

#if canImport(SQLiteNIO)
import SQLiteNIO

/// Example demonstrating basic SQLiteNIO usage
public enum SQLiteNIOExample {
  
  /// Example: Creating a connection and querying data
  ///
  /// ```swift
  /// // Open a connection
  /// let threadPool = NIOThreadPool(numberOfThreads: 1)
  /// threadPool.start()
  /// let eventLoopGroup = MultiThreadedEventLoopGroup(numberOfThreads: 1)
  /// let connection = try await SQLiteConnection.open(
  ///   storage: .memory,
  ///   threadPool: threadPool,
  ///   on: eventLoopGroup.next()
  /// ).get()
  ///
  /// // Wrap in a queue
  /// let queue = SQLiteNIODatabase.Queue(connection: connection)
  ///
  /// // Execute a query
  /// let rows = try await queue.asyncRead { conn in
  ///   try await conn.query(sql: "SELECT * FROM users WHERE id = ?", bindings: [.integer(1)])
  /// }
  ///
  /// // Decode rows
  /// for row in rows {
  ///   let user = try row.decode(User.self)
  ///   print(user.name)
  /// }
  /// ```
  public static func basicUsage() async throws {
    // See above for implementation
  }
  
  /// Example: Observing database changes
  ///
  /// ```swift
  /// // Create observer
  /// let observer = SQLiteNIOObserver(connection: connection)
  ///
  /// // Subscribe to changes on specific tables
  /// let subscription = await observer.subscribe(tables: ["users"]) { change in
  ///   print("Table \(change.tableName) changed: \(change.type)")
  ///   // Refetch data here
  /// }
  ///
  /// // Later, cancel the subscription
  /// subscription.cancel()
  /// ```
  public static func observationExample() async throws {
    // See above for implementation
  }
  
  /// Example: Decoding complex types
  ///
  /// ```swift
  /// struct User: Decodable {
  ///   let id: Int
  ///   let name: String
  ///   let email: String
  ///   let createdAt: Date
  ///   let profileImage: Data?
  /// }
  ///
  /// let rows = try await connection.query(
  ///   "SELECT * FROM users",
  ///   []
  /// )
  ///
  /// let users = try rows.map { try $0.decode(User.self) }
  /// ```
  public static func decodingExample() async throws {
    // See above for implementation
  }
  
  /// Example: Integration with Sharing library
  ///
  /// ```swift
  /// // This would eventually replace GRDB-based FetchKey
  /// struct SQLiteNIOFetchKey<Value: Sendable>: SharedReaderKey {
  ///   let connection: SQLiteConnection
  ///   let sql: String
  ///
  ///   func load(context: LoadContext<Value>, continuation: LoadContinuation<Value>) {
  ///     Task {
  ///       let rows = try await connection.query(sql, [])
  ///       let values = try rows.map { try $0.decode(Value.self) }
  ///       continuation.resume(returning: values as! Value)
  ///     }
  ///   }
  ///
  ///   func subscribe(
  ///     context: LoadContext<Value>,
  ///     subscriber: SharedSubscriber<Value>
  ///   ) -> SharedSubscription {
  ///     let observer = SQLiteNIOObserver(connection: connection)
  ///     return observer.sharedSubscription(tables: ["users"]) {
  ///       // Refetch and notify
  ///       Task {
  ///         let rows = try await connection.query(sql, [])
  ///         let values = try rows.map { try $0.decode(Value.self) }
  ///         subscriber.yield(values as! Value)
  ///       }
  ///     }
  ///   }
  /// }
  /// ```
  public static func sharingIntegration() {
    // See above for implementation
  }
}

#endif
