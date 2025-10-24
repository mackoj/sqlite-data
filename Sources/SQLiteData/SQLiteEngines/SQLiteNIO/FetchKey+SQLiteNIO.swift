#if SQLITE_ENGINE_SQLITENO
import Dependencies
import Foundation
import Sharing
import SQLiteNIO

/// Extension to support SQLiteNIO-based observation in FetchKey
extension SharedReaderKey {
  /// Create a fetch key that uses SQLiteNIO for observation
  static func fetchNIO<Value, Request: SQLiteNIOFetchRequest>(
    _ request: Request,
    connection: SQLiteConnection
  ) -> Self
  where Self == FetchKeyNIO<Value>, Request.Value == Value {
    FetchKeyNIO(request: request, connection: connection)
  }
  
  static func fetchNIO<Records: RangeReplaceableCollection, Request: SQLiteNIOFetchRequest>(
    _ request: Request,
    connection: SQLiteConnection
  ) -> Self
  where Self == FetchKeyNIO<Records>.Default, Request.Value == Records {
    Self[.fetchNIO(request, connection: connection), default: Value()]
  }
}

/// A FetchKey that uses SQLiteNIO for database access and observation
struct FetchKeyNIO<Value: Sendable>: SharedReaderKey {
  let connection: SQLiteConnection
  let request: any SQLiteNIOFetchRequest<Value>
  
  public typealias ID = FetchKeyNIOID
  
  public var id: ID {
    ID(connection: connection, request: request)
  }
  
  init<Request: SQLiteNIOFetchRequest>(
    request: Request,
    connection: SQLiteConnection
  ) where Request.Value == Value {
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
  
  fileprivate init<Request: SQLiteNIOFetchRequest>(
    connection: SQLiteConnection,
    request: Request
  ) {
    self.connectionID = ObjectIdentifier(connection)
    self.request = AnyHashableSendable(request)
    self.requestTypeID = ObjectIdentifier(type(of: request))
  }
}

/// Protocol for requests that can fetch from SQLiteNIO connections
public protocol SQLiteNIOFetchRequest<Value>: Sendable, Hashable {
  associatedtype Value: Sendable
  
  /// Fetch the value from a SQLiteNIO connection
  func fetch(_ connection: SQLiteConnection) async throws -> Value
  
  /// The tables that this request observes for changes
  var observedTables: Set<String> { get }
}

/// An error indicating that no row was found for a query that expected one.
public struct NotFound: Error {
  public init() {}
}

#endif
