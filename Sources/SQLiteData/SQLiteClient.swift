import Dependencies
import Foundation

#if canImport(Combine)
  import Combine
#endif

/// A client for interacting with SQLite databases using different engines.
///
/// This client provides a unified interface for database operations that can be backed by
/// different SQLite engines (GRDB or SQLiteNIO). It uses the protocol witness pattern
/// as described in Point-Free's dependency design documentation.
///
/// The database connection is accessed via `@Dependency` within closures, ensuring
/// the correct engine is used based on compile-time traits.
///
/// ## Usage with Dependencies
///
/// Configure the client as a dependency in your app:
///
/// ```swift
/// @main
/// struct MyApp: App {
///   init() {
///     prepareDependencies {
///       #if SQLITE_ENGINE_GRDB
///       $0.defaultDatabase = try! defaultDatabase()
///       #elseif SQLITE_ENGINE_SQLITENIO  
///       $0.defaultSQLiteConnection = try! await SQLiteConnection.open(...)
///       #endif
///     }
///   }
/// }
/// ```
///
/// Then use the client anywhere:
///
/// ```swift
/// @Dependency(\.sqliteClient) var sqliteClient
///
/// // Execute read operations
/// try await sqliteClient.read {
///   #if SQLITE_ENGINE_GRDB
///   @Dependency(\.defaultDatabase) var database
///   // Use database for GRDB operations
///   #elseif SQLITE_ENGINE_SQLITENIO
///   @Dependency(\.defaultSQLiteConnection) var connection
///   // Use connection for SQLiteNIO operations
///   #endif
/// }
/// ```
public struct SQLiteClient: Sendable {
  /// Executes an asynchronous read-only transaction on the database.
  ///
  /// The database connection is accessed via `@Dependency` within the closure.
  ///
  /// - Parameter block: A closure for performing read operations.
  public var read: @Sendable (_ block: @escaping @Sendable () async throws -> Void) async throws -> Void
  
  /// Executes an asynchronous write transaction on the database.
  ///
  /// The database connection is accessed via `@Dependency` within the closure.
  ///
  /// - Parameter block: A closure for performing write operations.
  public var write: @Sendable (_ block: @escaping @Sendable () async throws -> Void) async throws -> Void
  
  /// Creates a context-sensitive database path.
  ///
  /// Returns an appropriate database path based on the current context:
  /// - In live context: Path in the application support directory
  /// - In preview context: In-memory database (returns nil)
  /// - In test context: Temporary file
  public var contextSensitivePath: @Sendable () throws -> String?
  
  /// Subscribes to changes in specified tables.
  ///
  /// - Parameters:
  ///   - tables: The set of table names to observe.
  ///   - onChange: A closure called when changes occur.
  /// - Returns: A cancellable subscription.
  public var observeTables: @Sendable (
    _ tables: Set<String>,
    _ onChange: @escaping @Sendable () -> Void
  ) async throws -> SQLiteCancellable
  
  /// Creates a new SQLiteClient with custom implementations.
  ///
  /// This initializer is typically not called directly. Instead, use the static
  /// factory methods like ``grdb`` or ``nio``.
  public init(
    read: @escaping @Sendable (_ block: @escaping @Sendable () async throws -> Void) async throws -> Void,
    write: @escaping @Sendable (_ block: @escaping @Sendable () async throws -> Void) async throws -> Void,
    contextSensitivePath: @escaping @Sendable () throws -> String?,
    observeTables: @escaping @Sendable (
      _ tables: Set<String>,
      _ onChange: @escaping @Sendable () -> Void
    ) async throws -> SQLiteCancellable
  ) {
    self.read = read
    self.write = write
    self.contextSensitivePath = contextSensitivePath
    self.observeTables = observeTables
  }
}

// MARK: - Cancellable Protocol

/// A protocol for cancellable subscriptions.
public protocol SQLiteCancellable: Sendable {
  func cancel()
}

// MARK: - Dependency Values

extension DependencyValues {
  /// The SQLite client used for database operations.
  ///
  /// Configure this as early as possible in your app's lifetime:
  ///
  /// ```swift
  /// @main
  /// struct MyApp: App {
  ///   init() {
  ///     prepareDependencies {
  ///       $0.sqliteClient = .grdb(database: try! defaultDatabase())
  ///     }
  ///   }
  /// }
  /// ```
  ///
  /// Access it anywhere using `@Dependency`:
  ///
  /// ```swift
  /// @Dependency(\.sqliteClient) var sqliteClient
  /// ```
  public var sqliteClient: SQLiteClient {
    get { self[SQLiteClientKey.self] }
    set { self[SQLiteClientKey.self] = newValue }
  }
  
  private enum SQLiteClientKey: DependencyKey {
    static let liveValue = SQLiteClient.live
    static let testValue = SQLiteClient.test
  }
}

// MARK: - Live and Test Implementations

extension SQLiteClient {
  /// A live implementation that selects the appropriate engine based on the active trait.
  public static var live: Self {
    #if SQLITE_ENGINE_GRDB
      return .grdb
    #elseif SQLITE_ENGINE_SQLITENIO
      return .nio
    #else
      fatalError("No SQLite engine trait is enabled. Enable either GRDB or SQLiteNIO trait.")
    #endif
  }
  
  /// A test implementation that uses an in-memory database.
  public static var test: Self {
    #if SQLITE_ENGINE_GRDB
      return .grdb
    #elseif SQLITE_ENGINE_SQLITENIO
      return .nio
    #else
      fatalError("No SQLite engine trait is enabled")
    #endif
  }
}
