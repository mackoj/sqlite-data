# SQLiteClient Protocol Witness Design

## Overview

This document describes the `SQLiteClient` abstraction introduced to provide a unified interface for interacting with SQLite databases using different engines (GRDB or SQLiteNIO). The design follows the protocol witness pattern as outlined in Point-Free's dependency design documentation.

## What is the Protocol Witness Pattern?

The protocol witness pattern is an alternative to traditional protocol-based abstractions. Instead of defining a protocol with required methods, we define a struct that contains closures representing the operations. This provides several benefits:

1. **Better testability** - Mock implementations are just struct instances with test closures
2. **Compile-time flexibility** - Different implementations can have different concrete types
3. **No existential types** - Avoids performance overhead of protocol types
4. **Easier to reason about** - All dependencies are explicit in the struct

## Design Process

Following Point-Free's guidance, we started with a protocol-based design:

```swift
protocol SQLiteDatabaseClient {
  func read(_ block: @escaping () async throws -> Void) async throws
  func write(_ block: @escaping () async throws -> Void) async throws
  func contextSensitivePath() throws -> String?
  func observeTables(_ tables: Set<String>, onChange: @escaping () -> Void) async throws -> Cancellable
}
```

Then refactored it into the protocol witness style:

```swift
struct SQLiteClient {
  var read: @Sendable (_ block: @escaping @Sendable () async throws -> Void) async throws -> Void
  var write: @Sendable (_ block: @escaping @Sendable () async throws -> Void) async throws -> Void
  var contextSensitivePath: @Sendable () throws -> String?
  var observeTables: @Sendable (_ tables: Set<String>, _ onChange: @escaping @Sendable () -> Void) async throws -> SQLiteCancellable
  
  init(
    read: @escaping @Sendable (_ block: @escaping @Sendable () async throws -> Void) async throws -> Void,
    write: @escaping @Sendable (_ block: @escaping @Sendable () async throws -> Void) async throws -> Void,
    contextSensitivePath: @escaping @Sendable () throws -> String?,
    observeTables: @escaping @Sendable (_ tables: Set<String>, _ onChange: @escaping @Sendable () -> Void) async throws -> SQLiteCancellable
  )
}
```

## Static Factory Methods

Following the witness pattern, we provide static factory methods for each implementation:

### GRDB Implementation

```swift
extension SQLiteClient {
  static func grdb(database: any GRDB.DatabaseReader) -> Self {
    Self(
      read: { block in
        try await database.read { _ in }
        try await block()
      },
      write: { block in
        guard let writer = database as? any GRDB.DatabaseWriter else {
          throw SQLiteClientError.readOnlyDatabase
        }
        try await writer.write { _ in }
        try await block()
      },
      // ... other implementations
    )
  }
}
```

### SQLiteNIO Implementation

```swift
extension SQLiteClient {
  static func nio(connection: SQLiteConnection) -> Self {
    Self(
      read: { block in
        try await block()
      },
      write: { block in
        try await block()
      },
      // ... other implementations
    )
  }
  
  static func nioDefault() async throws -> Self {
    // Context-aware connection creation
  }
}
```

## Integration with Dependencies

The client integrates with `swift-dependencies` for dependency injection:

```swift
extension DependencyValues {
  var sqliteClient: SQLiteClient {
    get { self[SQLiteClientKey.self] }
    set { self[SQLiteClientKey.self] = newValue }
  }
  
  private enum SQLiteClientKey: DependencyKey {
    static let liveValue = SQLiteClient.live
    static let testValue = SQLiteClient.test
  }
}
```

## Usage Examples

### In a Live App

```swift
@main
struct MyApp: App {
  init() {
    prepareDependencies {
      #if SQLITE_ENGINE_GRDB
      let database = try! defaultDatabase()
      $0.sqliteClient = .grdb(database: database)
      #elseif SQLITE_ENGINE_SQLITENIO
      // SQLiteNIO requires async initialization
      Task {
        $0.sqliteClient = try await .nioDefault()
      }
      #endif
    }
  }
  
  var body: some Scene {
    WindowGroup {
      ContentView()
    }
  }
}
```

### In a Feature

```swift
@Observable
final class UserListModel {
  @Dependency(\.sqliteClient) var sqliteClient
  
  var users: [User] = []
  
  func loadUsers() async throws {
    try await sqliteClient.read {
      #if SQLITE_ENGINE_GRDB
      users = try await User.fetchAll(database)
      #elseif SQLITE_ENGINE_SQLITENIO
      users = try await User.all.fetchAll(connection)
      #endif
    }
  }
  
  func saveUser(_ user: User) async throws {
    try await sqliteClient.write {
      #if SQLITE_ENGINE_GRDB
      try await user.insert(database)
      #elseif SQLITE_ENGINE_SQLITENIO
      try await user.insert(connection)
      #endif
    }
  }
}
```

### In Tests

```swift
@Test
func testUserList() async throws {
  #if SQLITE_ENGINE_GRDB
  let database = try DatabaseQueue()
  let client = SQLiteClient.grdb(database: database)
  #elseif SQLITE_ENGINE_SQLITENIO
  let connection = try await SQLiteConnection.open(storage: .memory)
  let client = SQLiteClient.nio(connection: connection)
  #endif
  
  await withDependencies {
    $0.sqliteClient = client
  } operation: {
    let model = UserListModel()
    try await model.loadUsers()
    #expect(model.users.isEmpty)
  }
}
```

### In Previews

```swift
#Preview {
  let _ = prepareDependencies {
    #if SQLITE_ENGINE_GRDB
    let database = try! DatabaseQueue()
    $0.sqliteClient = .grdb(database: database)
    #elseif SQLITE_ENGINE_SQLITENIO
    Task {
      let connection = try! await SQLiteConnection.open(storage: .memory)
      $0.sqliteClient = .nio(connection: connection)
    }
    #endif
  }
  
  ContentView()
}
```

## Context-Aware Behavior

The client provides context-aware defaults based on the `@Dependency(\.context)` value:

- **Live**: File-based database in application support directory
- **Preview**: In-memory database
- **Test**: Temporary file

This is accessed via the `contextSensitivePath()` method:

```swift
let path = try sqliteClient.contextSensitivePath()
// Live: "/path/to/Application Support/SQLiteData.db"
// Preview: nil (in-memory)
// Test: "/tmp/UUID.db"
```

## Table Observation

Both implementations support observing changes to specific tables:

```swift
let cancellable = try await sqliteClient.observeTables(["users", "posts"]) {
  print("Tables changed!")
}

// Later...
cancellable.cancel()
```

**GRDB Implementation**: Uses `ValueObservation` to track table changes
**SQLiteNIO Implementation**: Uses `SQLiteNIOObserver` for change notifications

## Benefits of This Design

1. **Unified Interface**: Same API works with both GRDB and SQLiteNIO
2. **Trait-Based Selection**: Only one engine is compiled into the binary
3. **Easy Testing**: Mock implementations are simple struct instances
4. **Dependency Injection**: Integrates seamlessly with swift-dependencies
5. **Context Awareness**: Automatically configures based on environment
6. **Type Safety**: Compile-time checking ensures correct usage
7. **No Runtime Overhead**: All abstraction is compile-time only

## Future Enhancements

Potential additions to the abstraction:

1. **Migration support**: Add a `migrate` closure for schema migrations
2. **Transaction control**: Explicit transaction begin/commit/rollback
3. **Batch operations**: Optimize bulk inserts/updates
4. **Read replicas**: Support for read-only database replicas
5. **Connection pooling**: Advanced connection management

## References

- [Designing Dependencies](https://pointfreeco.github.io/swift-dependencies/main/documentation/dependencies/designingdependencies)
- [Lifetimes](https://pointfreeco.github.io/swift-dependencies/main/documentation/dependencies/lifetimes)
- [Designing Dependencies (Collection)](https://www.pointfree.co/collections/dependencies/designing-dependencies)
