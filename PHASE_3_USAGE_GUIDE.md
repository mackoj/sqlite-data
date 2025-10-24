# Phase 3: Using SQLiteNIO with Property Wrappers - Complete Guide

## Overview

Phase 3 adds transaction support and demonstrates how to use SQLiteNIO with the Sharing library for reactive data access. While full @FetchAll/@FetchOne integration is planned for future phases, you can already use SQLiteNIO with reactive property wrappers through the Sharing library.

## Transaction Support (✅ Complete)

###  Basic Transactions

```swift
import SQLiteNIO

let connection = try await SQLiteConnection.open(
  storage: .file(path: "app.db"),
  threadPool: threadPool,
  on: eventLoop
).get()

// Automatic commit/rollback
try await connection.transaction { conn in
  try await conn.query(
    "INSERT INTO users (name, email) VALUES (?, ?)",
    [.text("Alice"), .text("alice@example.com")]
  )
  try await conn.query(
    "INSERT INTO posts (user_id, title) VALUES (?, ?)",
    [.integer(1), .text("First Post")]
  )
  // Both succeed or both are rolled back
}
```

### Transaction Types

```swift
// Deferred: Locks acquired on first read/write
try await connection.deferredTransaction { conn in
  // Good for read-heavy transactions
}

// Immediate: Write lock acquired immediately
try await connection.immediateTransaction { conn in
  // Good when you know you'll write
}

// Exclusive: Prevents all other database access
try await connection.exclusiveTransaction { conn in
  // Good for critical operations
}
```

### Nested Transactions with Savepoints

```swift
try await connection.transaction { conn in
  try await conn.query("INSERT INTO users (name) VALUES (?)", [.text("Alice")])
  
  // Inner savepoint can fail without affecting outer transaction
  try? await conn.savepoint("backup") { conn in
    try await conn.query("INSERT INTO risky_table (data) VALUES (?)", [.text("Data")])
    throw SomeError() // Only this is rolled back
  }
  
  try await conn.query("INSERT INTO posts (title) VALUES (?)", [.text("Safe Post")])
  // Alice and Safe Post are still inserted
}
```

## Reactive Data Access with SQLiteNIO

### Using @SharedReader with FetchKeyNIO

While @FetchAll and @FetchOne currently work with GRDB, you can use @SharedReader for reactive SQLiteNIO data:

```swift
import Sharing
import SQLiteNIO

// Define your model
struct User: Codable, Hashable, Sendable {
  let id: Int
  let name: String
  let email: String
}

// Create a simple request
struct UsersRequest: FetchKeyRequest {
  typealias Value = [User]
  
  func fetch(_ connection: SQLiteConnection) async throws -> [User] {
    let rows = try await connection.query("SELECT id, name, email FROM users", [])
    return try rows.map { try $0.decode(User.self) }
  }
  
  var observedTables: Set<String> {
    ["users"]
  }
}

// Use in your view
struct UsersView: View {
  @SharedReader(.fetchNIO(UsersRequest(), connection: myConnection))
  var users: [User] = []
  
  var body: some View {
    List(users, id: \.id) { user in
      VStack(alignment: .leading) {
        Text(user.name).font(.headline)
        Text(user.email).font(.caption)
      }
    }
  }
}
```

### With StructuredQueries

```swift
import StructuredQueriesCore

// Using StructuredQueries with SQLiteNIO
struct ContentView: View {
  let connection: SQLiteConnection
  
  var body: some View {
    Button("Add User") {
      Task {
        try await connection.transaction { conn in
          // Using StructuredQueries Statement+SQLiteNIO extensions
          try await User.insert { $0.name; $0.email }
            .values { "Bob"; "bob@example.com" }
            .execute(conn)
        }
      }
    }
  }
}
```

## Complete Example App

Here's a complete example showing all Phase 2 and Phase 3 features:

```swift
import SwiftUI
import SQLiteNIO
import NIOPosix
import NIOCore
import Sharing
import StructuredQueriesCore

// MARK: - Model

struct User: Codable, Hashable, Sendable {
  let id: Int
  let name: String
  let email: String
}

// MARK: - Request

struct AllUsersRequest: FetchKeyRequest {
  typealias Value = [User]
  
  func fetch(_ connection: SQLiteConnection) async throws -> [User] {
    let rows = try await connection.query(
      "SELECT id, name, email FROM users ORDER BY name",
      []
    )
    return try rows.map { try $0.decode(User.self) }
  }
  
  var observedTables: Set<String> { ["users"] }
}

// MARK: - App

@main
struct MyApp: App {
  let connection: SQLiteConnection
  let threadPool: NIOThreadPool
  let eventLoopGroup: EventLoopGroup
  
  init() {
    // Setup NIO infrastructure
    threadPool = NIOThreadPool(numberOfThreads: 2)
    threadPool.start()
    eventLoopGroup = MultiThreadedEventLoopGroup(numberOfThreads: 2)
    
    // Open database connection
    connection = try! SQLiteConnection.open(
      storage: .file(path: "users.db"),
      threadPool: threadPool,
      on: eventLoopGroup.any()
    ).wait()
    
    // Create table
    Task {
      try await connection.query("""
        CREATE TABLE IF NOT EXISTS users (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          name TEXT NOT NULL,
          email TEXT NOT NULL UNIQUE
        )
      """, [])
    }
  }
  
  var body: some Scene {
    WindowGroup {
      ContentView(connection: connection)
    }
  }
}

// MARK: - View

struct ContentView: View {
  let connection: SQLiteConnection
  
  @SharedReader(.fetchNIO(AllUsersRequest(), connection: connection))
  var users: [User] = []
  
  @State private var newName = ""
  @State private var newEmail = ""
  
  var body: some View {
    NavigationView {
      VStack {
        // User list
        List(users, id: \.id) { user in
          VStack(alignment: .leading) {
            Text(user.name).font(.headline)
            Text(user.email).font(.caption).foregroundColor(.gray)
          }
        }
        
        // Add user form
        GroupBox("Add User") {
          TextField("Name", text: $newName)
          TextField("Email", text: $newEmail)
          
          Button("Add") {
            addUser()
          }
          .disabled(newName.isEmpty || newEmail.isEmpty)
        }
        .padding()
      }
      .navigationTitle("Users")
    }
  }
  
  func addUser() {
    Task {
      do {
        try await connection.transaction { conn in
          try await conn.query(
            "INSERT INTO users (name, email) VALUES (?, ?)",
            [.text(newName), .text(newEmail)]
          )
        }
        
        // Clear form
        await MainActor.run {
          newName = ""
          newEmail = ""
        }
      } catch {
        print("Error adding user: \(error)")
      }
    }
  }
}
```

## Advanced Patterns

### Combining with Observation

```swift
import Observation

@Observable
class UserManager {
  let connection: SQLiteConnection
  var users: [User] = []
  
  init(connection: SQLiteConnection) {
    self.connection = connection
    setupObserver()
  }
  
  func setupObserver() {
    Task {
      let observer = SQLiteNIOObserver(connection: connection)
      _ = try await observer.subscribe(tables: ["users"]) { [weak self] _ in
        Task { @MainActor in
          await self?.refreshUsers()
        }
      }
    }
  }
  
  func refreshUsers() async {
    do {
      let rows = try await connection.query("SELECT * FROM users", [])
      users = try rows.map { try $0.decode(User.self) }
    } catch {
      print("Error: \(error)")
    }
  }
  
  func addUser(name: String, email: String) async throws {
    try await connection.transaction { conn in
      try await conn.query(
        "INSERT INTO users (name, email) VALUES (?, ?)",
        [.text(name), .text(email)]
      )
    }
    // Observer automatically triggers refresh
  }
}
```

### Batch Operations

```swift
func importUsers(_ csvData: String) async throws {
  try await connection.transaction { conn in
    let lines = csvData.split(separator: "\n")
    
    for line in lines {
      let parts = line.split(separator: ",")
      guard parts.count == 2 else { continue }
      
      try await conn.query(
        "INSERT INTO users (name, email) VALUES (?, ?)",
        [.text(String(parts[0])), .text(String(parts[1]))]
      )
    }
    // All-or-nothing: entire import succeeds or fails
  }
}
```

## Future: Full @FetchAll/@FetchOne Integration

In a future phase, the integration will be even more seamless:

```swift
// Future API (not yet implemented)
@FetchAll(User.all, connection: connection) var users
@FetchOne(User.count, connection: connection) var userCount = 0

// Will work identically to GRDB versions
```

## Migration Path

### From GRDB to SQLiteNIO

1. **Keep existing @FetchAll/@FetchOne with GRDB for now**
2. **Use SQLiteNIO for new features and Linux support**
3. **Gradually migrate using @SharedReader + FetchKeyNIO**
4. **Full migration when Phase 4 complete**

## Best Practices

1. **Always use transactions for multiple related writes**
   ```swift
   try await connection.transaction { conn in
     // Multiple queries here
   }
   ```

2. **Use appropriate transaction types**
   - `deferredTransaction` for read-heavy operations
   - `immediateTransaction` when you know you'll write
   - `exclusiveTransaction` for critical operations

3. **Handle errors properly**
   ```swift
   do {
     try await connection.transaction { conn in
       // Your queries
     }
   } catch {
     // Handle specific errors
     print("Transaction failed: \(error)")
   }
   ```

4. **Use savepoints for optional operations**
   ```swift
   try await connection.transaction { conn in
     // Critical operation
     try await criticalInsert(conn)
     
     // Optional operation - can fail without affecting critical one
     try? await conn.savepoint("optional") { conn in
       try await optionalInsert(conn)
     }
   }
   ```

## Performance Tips

1. **Batch inserts in transactions** - Much faster than individual inserts
2. **Use prepared statements** (coming in future phases)
3. **Choose appropriate transaction type** - Don't use exclusive unless necessary
4. **Limit observer subscriptions** - Only observe tables you actually need

## Troubleshooting

### Observer not firing

Make sure your `FetchKeyRequest` returns the correct `observedTables`:

```swift
var observedTables: Set<String> {
  ["users", "posts"]  // All tables your query touches
}
```

### Transaction deadlock

Use appropriate transaction types and avoid holding locks too long:

```swift
// Bad: Exclusive transaction for simple read
try await connection.exclusiveTransaction { ... }

// Good: Deferred transaction for read
try await connection.deferredTransaction { ... }
```

### Connection lifecycle

Properly manage your connection lifecycle:

```swift
// Setup
let connection = try await SQLiteConnection.open(...)

// Use throughout app lifetime

// Cleanup (e.g., in app delegate)
try await connection.close()
```

## Summary

Phase 3 provides:
- ✅ Full transaction support (BEGIN/COMMIT/ROLLBACK)
- ✅ Savepoints for nested transactions
- ✅ Integration with Sharing library via @SharedReader
- ✅ Real-time updates via SQLiteNIOObserver
- ✅ StructuredQueries support via Statement+SQLiteNIO

Coming in Phase 4:
- Direct @FetchAll/@FetchOne integration
- Feature flag for GRDB vs SQLiteNIO selection
- Automatic database type detection
