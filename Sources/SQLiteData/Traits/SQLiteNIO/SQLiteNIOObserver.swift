#if SQLITE_ENGINE_SQLITENIO
/// SQLiteNIO Change Observer
///
/// This actor provides database change observation using SQLite's update hooks.
/// It's the SQLiteNIO equivalent of GRDB's ValueObservation system.

import Foundation
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
    
    fileprivate init(from operation: SQLiteUpdateOperation) {
      switch operation {
      case .insert:
        self = .insert
      case .update:
        self = .update
      case .delete:
        self = .delete
      default:
        self = .update
      }
    }
  }
  
  /// Describes a change to the database
  public struct Change: Sendable {
    public let type: UpdateType
    public let tableName: String
    public let rowID: Int64
    
    fileprivate init(from event: SQLiteUpdateEvent) {
      self.type = UpdateType(from: event.operation)
      self.tableName = event.table
      self.rowID = event.rowID
    }
  }
  
  /// A subscription that can be cancelled
  public struct Subscription: Sendable {
    let cancelHandler: @Sendable () -> Void
    
    public func cancel() {
      cancelHandler()
    }
  }
  
  private let connection: SQLiteConnection
  private var subscribers: [UUID: (tables: Set<String>, callback: @Sendable (Change) -> Void)] = [:]
  private var hookToken: SQLiteHookToken?
  
  public init(connection: SQLiteConnection) {
    self.connection = connection
  }
  
  /// Subscribe to changes on specific tables
  public func subscribe(
    tables: Set<String>,
    onChange: @escaping @Sendable (Change) -> Void
  ) async throws -> Subscription {
    let id = UUID()
    subscribers[id] = (tables: tables, callback: onChange)
    
    // Install the hook if this is the first subscriber
    if hookToken == nil {
      try await installUpdateHook()
    }
    
    return Subscription(cancelHandler: { [weak self] in
      Task { await self?.unsubscribe(id: id) }
    })
  }
  
  private func unsubscribe(id: UUID) {
    subscribers.removeValue(forKey: id)
    
    // If no more subscribers, cancel the hook
    if subscribers.isEmpty {
      hookToken?.cancel()
      hookToken = nil
    }
  }
  
  /// Install the SQLite update hook using SQLiteNIO 1.12.0's native support
  private func installUpdateHook() async throws {
    hookToken = try await connection.addUpdateObserver(lifetime: .pinned) { [weak self] event in
      guard let self = self else { return }
      Task {
        await self.handleUpdateEvent(event)
      }
    }
  }
  
  /// Handle an update event from SQLite and notify relevant subscribers
  private func handleUpdateEvent(_ event: SQLiteUpdateEvent) {
    let change = Change(from: event)
    
    // Notify only subscribers interested in this table
    for (_, subscriber) in subscribers where subscriber.tables.contains(change.tableName) {
      subscriber.callback(change)
    }
  }
}

// MARK: - Integration with Sharing library

extension SQLiteNIOObserver {
  /// Creates a SharedSubscription that works with the Sharing library
  public func sharedSubscription(
    tables: Set<String>,
    onChange: @escaping @Sendable () -> Void
  ) async throws -> SharedSubscription {
    let subscription = try await subscribe(tables: tables) { _ in
      onChange()
    }
    return SharedSubscription {
      subscription.cancel()
    }
  }
}

#endif
