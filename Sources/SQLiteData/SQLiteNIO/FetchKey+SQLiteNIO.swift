import Dependencies
import Foundation
import Sharing

#if canImport(SQLiteNIO)
import SQLiteNIO

/// Extension to support SQLiteNIO-based observation in FetchKey
extension SharedReaderKey {
  /// Create a fetch key that uses SQLiteNIO for observation
  static func fetchNIO<Value>(
    _ request: some FetchKeyRequest<Value>,
    connection: SQLiteConnection
  ) -> Self
  where Self == FetchKeyNIO<Value> {
    FetchKeyNIO(request: request, connection: connection)
  }
  
  static func fetchNIO<Records: RangeReplaceableCollection>(
    _ request: some FetchKeyRequest<Records>,
    connection: SQLiteConnection
  ) -> Self
  where Self == FetchKeyNIO<Records>.Default {
    Self[.fetchNIO(request, connection: connection), default: Value()]
  }
}

/// A FetchKey that uses SQLiteNIO for database access and observation
struct FetchKeyNIO<Value: Sendable>: SharedReaderKey {
  let connection: SQLiteConnection
  let request: any FetchKeyRequest<Value>
  
  public typealias ID = FetchKeyNIOID
  
  public var id: ID {
    ID(connection: connection, request: request)
  }
  
  init(
    request: some FetchKeyRequest<Value>,
    connection: SQLiteConnection
  ) {
    self.connection = connection
    self.request = request
  }
  
  public func load(context: LoadContext<Value>, continuation: LoadContinuation<Value>) {
    guard case .userInitiated = context else {
      continuation.resumeReturningInitialValue()
      return
    }
    
    Task {
      do {
        // Execute the fetch request on the connection
        let value = try await request.fetch(connection)
        continuation.resume(returning: value)
      } catch {
        continuation.resume(throwing: error)
      }
    }
  }
  
  public func subscribe(
    context: LoadContext<Value>, subscriber: SharedSubscriber<Value>
  ) -> SharedSubscription {
    // Get the tables that this request observes
    let tables = request.observedTables
    
    // Create an observer
    let observer = SQLiteNIOObserver(connection: connection)
    
    let subscriptionTask = Task {
      do {
        // Subscribe to changes
        let subscription = try await observer.subscribe(tables: tables) { _ in
          // When a change occurs, re-fetch the data
          Task {
            do {
              let newValue = try await self.request.fetch(self.connection)
              subscriber.yield(newValue)
            } catch {
              subscriber.yield(throwing: error)
            }
          }
        }
        
        // Return a subscription that cancels the observer subscription
        return SharedSubscription {
          subscription.cancel()
        }
      } catch {
        subscriber.yield(throwing: error)
        return SharedSubscription {}
      }
    }
    
    // Return a subscription that cancels the task
    return SharedSubscription {
      subscriptionTask.cancel()
    }
  }
}

struct FetchKeyNIOID: Hashable {
  fileprivate let connectionID: ObjectIdentifier
  fileprivate let request: AnyHashableSendable
  fileprivate let requestTypeID: ObjectIdentifier
  
  fileprivate init(
    connection: SQLiteConnection,
    request: some FetchKeyRequest
  ) {
    self.connectionID = ObjectIdentifier(connection)
    self.request = AnyHashableSendable(request)
    self.requestTypeID = ObjectIdentifier(type(of: request))
  }
}

/// Protocol extension to determine observed tables from a request
extension FetchKeyRequest {
  /// The tables that this request observes for changes
  /// Default implementation returns empty set - should be overridden by specific request types
  var observedTables: Set<String> {
    []
  }
}

/// Simplified approach: Users can use FetchKeyNIO directly with @SharedReader
/// Example:
/// ```swift
/// @SharedReader(.fetchNIO(MyRequest(), connection: connection))
/// var myData: MyDataType
/// ```

#endif
