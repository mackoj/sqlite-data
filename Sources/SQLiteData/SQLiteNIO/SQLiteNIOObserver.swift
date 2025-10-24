/// SQLiteNIO Change Observer
///
/// This actor provides database change observation using SQLite's update hooks.
/// It's the SQLiteNIO equivalent of GRDB's ValueObservation system.

import Foundation

#if canImport(SQLiteNIO)
import SQLiteNIO
import Sharing

/// Actor that observes database changes using sqlite3_update_hook.
///
/// This is the core of the observation system for SQLiteNIO, replacing GRDB's ValueObservation.
/// It uses SQLite's update hook mechanism to detect when rows change, then notifies subscribers.
public actor SQLiteNIOObserver {
  
  /// Type of database update operation
  public enum UpdateType: Sendable {
    case insert
    case delete
    case update
  }
  
  /// Describes a change to the database
  public struct Change: Sendable {
    public let type: UpdateType
    public let tableName: String
    public let rowID: Int64
  }
  
  /// A subscription that can be cancelled
  public struct Subscription: Sendable {
    let cancelHandler: @Sendable () -> Void
    
    public func cancel() {
      cancelHandler()
    }
  }
  
  private let connection: SQLiteConnection
  private var subscribers: [UUID: @Sendable (Change) -> Void] = [:]
  private var isHookInstalled = false
  
  public init(connection: SQLiteConnection) {
    self.connection = connection
  }
  
  /// Subscribe to changes on specific tables
  public func subscribe(
    tables: Set<String>,
    onChange: @escaping @Sendable (Change) -> Void
  ) -> Subscription {
    let id = UUID()
    
    // Wrap the callback to filter by table
    let filteredCallback: @Sendable (Change) -> Void = { change in
      if tables.contains(change.tableName) {
        onChange(change)
      }
    }
    
    subscribers[id] = filteredCallback
    
    // Install the hook if this is the first subscriber
    if !isHookInstalled {
      installUpdateHook()
    }
    
    return Subscription(cancelHandler: { [weak self] in
      Task { await self?.unsubscribe(id: id) }
    })
  }
  
  private func unsubscribe(id: UUID) {
    subscribers.removeValue(forKey: id)
  }
  
  /// Install the SQLite update hook
  /// Note: This is a placeholder. The actual implementation would use sqlite3_update_hook
  /// from PR #90 or via raw SQLite3 C API.
  private func installUpdateHook() {
    isHookInstalled = true
    
    // TODO: Install actual update hook using one of these methods:
    // 1. SQLiteNIO PR #90 API (when available)
    // 2. Raw sqlite3_update_hook via C interop
    // 3. Custom SQLiteNIO extension
    //
    // Pseudocode:
    // connection.installUpdateHook { type, database, table, rowid in
    //   let change = Change(
    //     type: mapUpdateType(type),
    //     tableName: table,
    //     rowID: rowid
    //   )
    //   Task { await self.notifySubscribers(change) }
    // }
  }
  
  private func notifySubscribers(_ change: Change) {
    for subscriber in subscribers.values {
      subscriber(change)
    }
  }
}

// MARK: - Integration with Sharing library

extension SQLiteNIOObserver {
  /// Creates a SharedSubscription that works with the Sharing library
  public func sharedSubscription(
    tables: Set<String>,
    onChange: @escaping @Sendable () -> Void
  ) -> SharedSubscription {
    let subscription = subscribe(tables: tables) { _ in
      onChange()
    }
    return SharedSubscription {
      subscription.cancel()
    }
  }
}

#endif
