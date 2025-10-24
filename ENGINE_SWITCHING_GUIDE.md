# Engine Switching Guide

This guide explains how to switch between GRDB and SQLiteNIO engines in SQLiteData, and how to ensure proper separation between them.

## Table of Contents

- [Overview](#overview)
- [Quick Start](#quick-start)
- [Using GRDB](#using-grdb)
- [Using SQLiteNIO](#using-sqlitenio)
- [Switching Engines](#switching-engines)
- [Testing with Different Engines](#testing-with-different-engines)
- [Import Separation](#import-separation)
- [Engine Comparison](#engine-comparison)
- [Troubleshooting](#troubleshooting)

## Overview

SQLiteData supports two database engines:

1. **GRDB**: Mature, Apple-platform-focused engine with CloudKit support
2. **SQLiteNIO**: Cross-platform engine with full async/await support

Both engines share the same high-level API (`@FetchAll`, `@FetchOne`) but use different underlying implementations. You can choose which engine to use by configuring your dependencies at app startup.

## Quick Start

### Choose Your Engine

Configure your app to use either GRDB or SQLiteNIO:

**GRDB:**
```swift
import SQLiteData
import SwiftUI

@main
struct MyApp: App {
  init() {
    prepareDependencies {
      $0.defaultDatabase = try! DatabaseQueue(
        path: "/path/to/database.db"
      )
    }
  }
  
  var body: some Scene {
    WindowGroup { ContentView() }
  }
}
```

**SQLiteNIO:**
```swift
import SQLiteData
import SQLiteNIO
import SwiftUI

@main
struct MyApp: App {
  init() {
    prepareDependencies {
      $0.defaultSQLiteConnection = try! await SQLiteConnection.open(
        path: "/path/to/database.db"
      )
    }
  }
  
  var body: some Scene {
    WindowGroup { ContentView() }
  }
}
```

### Use in Views

The view code is similar for both engines:

**GRDB:**
```swift
struct ContentView: View {
  @FetchAll var users: [User]
  @FetchOne var count = 0
  
  var body: some View {
    List(users, id: \.id) { user in
      Text(user.name)
    }
  }
}
```

**SQLiteNIO:**
```swift
struct ContentView: View {
  @FetchAll(User.all) var users
  @FetchOne(User.count) var count = 0
  
  var body: some View {
    List(users, id: \.id) { user in
      Text(user.name)
    }
  }
}
```

## Using GRDB

### Setup

1. Import SQLiteData (GRDB is re-exported automatically)
2. Configure `defaultDatabase` in app initialization
3. Use `@FetchAll` and `@FetchOne` property wrappers

### Full Example

```swift
import SQLiteData
import SwiftUI

@main
struct MyApp: App {
  init() {
    prepareDependencies {
      do {
        // Create database queue
        let dbQueue = try DatabaseQueue(
          path: NSSearchPathForDirectoriesInDomains(
            .applicationSupportDirectory,
            .userDomainMask,
            true
          ).first! + "/database.db"
        )
        
        // Run migrations
        var migrator = DatabaseMigrator()
        migrator.registerMigration("v1") { db in
          try db.execute(sql: """
            CREATE TABLE users (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              name TEXT NOT NULL,
              email TEXT NOT NULL UNIQUE
            )
            """)
        }
        try migrator.migrate(dbQueue)
        
        // Set as default
        $0.defaultDatabase = dbQueue
      } catch {
        fatalError("Database initialization failed: \(error)")
      }
    }
  }
  
  var body: some Scene {
    WindowGroup {
      ContentView()
    }
  }
}

struct ContentView: View {
  @FetchAll var users: [User]
  @Dependency(\.defaultDatabase) var database
  
  var body: some View {
    List(users, id: \.id) { user in
      Text(user.name)
    }
    .toolbar {
      Button("Add User") {
        Task {
          try? await database.write { db in
            try User.insert {
              $0.name
              $0.email
            }
            .values {
              "New User"
              "user@example.com"
            }
            .execute(db)
          }
        }
      }
    }
  }
}

@Table
struct User: Codable {
  let id: Int
  var name: String
  var email: String
}
```

### GRDB-Specific Features

- **CloudKit Synchronization**: Full support via `SyncEngine` (GRDB-only, see note below)
- **ValueObservation**: Built-in reactive queries
- **FTS5**: Full-text search support
- **Custom SQLite functions**: Easy registration
- **Connection pools**: Read/write separation with `DatabasePool`

> **Note on CloudKit**: CloudKit synchronization requires GRDB and is not available with SQLiteNIO.
> This is because CloudKit integration depends on GRDB-specific features like `DatabaseMigrator`,
> custom SQL functions, and connection pooling. If you need CloudKit sync, use the GRDB trait.
> For cross-platform applications without CloudKit, use SQLiteNIO.

## Using SQLiteNIO

### Setup

1. Import SQLiteData and SQLiteNIO explicitly
2. Configure `defaultSQLiteConnection` in app initialization
3. Use `@FetchAll` and `@FetchOne` with statement syntax

### Full Example

```swift
import SQLiteData
import SQLiteNIO
import SwiftUI

@main
struct MyApp: App {
  init() {
    prepareDependencies {
      Task {
        do {
          // Create connection
          let connection = try await SQLiteConnection.open(
            path: NSSearchPathForDirectoriesInDomains(
              .applicationSupportDirectory,
              .userDomainMask,
              true
            ).first! + "/database.db"
          )
          
          // Run migrations
          try await connection.query("""
            CREATE TABLE IF NOT EXISTS users (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              name TEXT NOT NULL,
              email TEXT NOT NULL UNIQUE
            )
            """, [])
          
          // Set as default
          $0.defaultSQLiteConnection = connection
        } catch {
          fatalError("Database initialization failed: \(error)")
        }
      }
    }
  }
  
  var body: some Scene {
    WindowGroup {
      ContentView()
    }
  }
}

struct ContentView: View {
  @FetchAll(User.all) var users
  @Dependency(\.defaultSQLiteConnection) var connection
  
  var body: some View {
    List(users, id: \.id) { user in
      Text(user.name)
    }
    .toolbar {
      Button("Add User") {
        Task {
          try? await connection.transaction { conn in
            try await conn.query("""
              INSERT INTO users (name, email) VALUES (?, ?)
              """, [
              .text("New User"),
              .text("user@example.com")
            ])
          }
        }
      }
    }
  }
}

@Table
struct User: Codable, Sendable {
  let id: Int
  var name: String
  var email: String
}
```

### SQLiteNIO-Specific Features

- **Full Async/Await**: All APIs are async from the ground up
- **Linux Support**: Runs on all platforms including Linux
- **NIO Integration**: Built on Swift NIO for efficient I/O
- **Actor Safety**: Thread-safe by default with actors
- **Transactions**: Full ACID transaction support

## Switching Engines

### From GRDB to SQLiteNIO

1. **Update App Initialization**:

   ```swift
   // Before (GRDB)
   prepareDependencies {
     $0.defaultDatabase = try! DatabaseQueue(path: "db.sqlite")
   }
   
   // After (SQLiteNIO)
   prepareDependencies {
     $0.defaultSQLiteConnection = try! await SQLiteConnection.open(path: "db.sqlite")
   }
   ```

2. **Update Imports** (if using explicit engine features):

   ```swift
   // Before
   import GRDB
   
   // After
   import SQLiteNIO
   ```

3. **Update Property Wrappers** (if using table-based syntax):

   ```swift
   // Before (GRDB - implicit)
   @FetchAll var users: [User]
   
   // After (SQLiteNIO - explicit statement)
   @FetchAll(User.all) var users
   ```

4. **Update Database Operations**:

   ```swift
   // Before (GRDB)
   try database.write { db in
     try User.insert { $0.name }.values { "Alice" }.execute(db)
   }
   
   // After (SQLiteNIO)
   try await connection.transaction { conn in
     try await conn.query("INSERT INTO users (name) VALUES (?)", [.text("Alice")])
   }
   ```

### From SQLiteNIO to GRDB

Follow the reverse process:

1. Change `defaultSQLiteConnection` to `defaultDatabase`
2. Update imports if needed
3. Remove explicit statement syntax from property wrappers (optional)
4. Convert async database operations to GRDB's closure-based API

### Maintaining Both Engines

You can use both engines simultaneously if needed:

```swift
@main
struct MyApp: App {
  init() {
    prepareDependencies {
      // GRDB for main app database
      $0.defaultDatabase = try! DatabaseQueue(path: "main.db")
      
      // SQLiteNIO for analytics database
      $0.defaultSQLiteConnection = try! await SQLiteConnection.open(path: "analytics.db")
    }
  }
}

struct DashboardView: View {
  // Uses GRDB
  @FetchAll var users: [User]
  
  // Uses SQLiteNIO
  @FetchAll(AnalyticsEvent.all) var events
}
```

## Testing with Different Engines

### GRDB Tests

```swift
import DependenciesTestSupport
import SQLiteData
import Testing

@Suite(.dependency(\.defaultDatabase, try .database()))
struct UserTests {
  @Dependency(\.defaultDatabase) var database
  
  @Test func createUser() async throws {
    // Use GRDB database
    try await database.write { db in
      try User.insert { $0.name }.values { "Test" }.execute(db)
    }
    
    @FetchAll var users: [User]
    #expect(users.count == 1)
  }
}
```

### SQLiteNIO Tests

```swift
import DependenciesTestSupport
import SQLiteData
import SQLiteNIO
import Testing

@Suite(
  .dependency(
    \.defaultSQLiteConnection,
    try await SQLiteConnection.open(storage: .memory)
  )
)
struct UserTests {
  @Dependency(\.defaultSQLiteConnection) var connection
  
  @Test func createUser() async throws {
    // Use SQLiteNIO connection
    try await connection.query(
      "INSERT INTO users (name) VALUES (?)",
      [.text("Test")]
    )
    
    @FetchAll(User.all) var users
    #expect(users.count == 1)
  }
}
```

### Testing Both Engines

You can create parameterized tests that work with both engines:

```swift
enum DatabaseEngine {
  case grdb
  case sqliteNIO
}

@Suite
struct CrossEngineTests {
  @Test(arguments: [DatabaseEngine.grdb, DatabaseEngine.sqliteNIO])
  func userOperations(engine: DatabaseEngine) async throws {
    switch engine {
    case .grdb:
      // Configure GRDB
      prepareDependencies {
        $0.defaultDatabase = try! DatabaseQueue()
      }
      
    case .sqliteNIO:
      // Configure SQLiteNIO
      prepareDependencies {
        $0.defaultSQLiteConnection = try! await SQLiteConnection.open(storage: .memory)
      }
    }
    
    // Test code that works with both
    @FetchAll(User.all) var users
    #expect(users.isEmpty)
  }
}
```

## Import Separation

### Conditional Compilation

The library uses conditional compilation to ensure engines don't cross-contaminate:

**SQLiteNIO Files**:
```swift
#if canImport(SQLiteNIO)
import SQLiteNIO
// SQLiteNIO-specific code
#endif
```

**GRDB Files**:
```swift
import GRDB
// GRDB-specific code
// No conditional needed as GRDB is always available on supported platforms
```

### Verify Separation

You can verify imports are properly separated:

```bash
# Check SQLiteNIO files don't import GRDB
grep -r "import GRDB" Sources/SQLiteData/SQLiteNIO/
# Should return nothing

# Check GRDB files don't import SQLiteNIO  
grep -r "import SQLiteNIO" Sources/SQLiteData/StructuredQueries+GRDB/
# Should return nothing
```

### Import Rules

| File Location | Can Import | Cannot Import |
|--------------|-----------|---------------|
| `Sources/SQLiteData/SQLiteNIO/` | SQLiteNIO, NIOCore, StructuredQueriesCore | GRDB, GRDBSQLite |
| `Sources/SQLiteData/StructuredQueries+GRDB/` | GRDB, GRDBSQLite, StructuredQueriesCore | SQLiteNIO, NIOCore |
| `Sources/SQLiteData/*.swift` | Sharing, Dependencies, StructuredQueriesCore | Neither GRDB nor SQLiteNIO directly |

## Engine Comparison

### Feature Matrix

| Feature | GRDB | SQLiteNIO |
|---------|------|-----------|
| **Platform Support** | | |
| iOS | ✅ | ✅ |
| macOS | ✅ | ✅ |
| tvOS | ✅ | ✅ |
| watchOS | ✅ | ✅ |
| Linux | ❌ | ✅ |
| **API Style** | | |
| Synchronous | ✅ | ❌ |
| Async/Await | Partial | ✅ Full |
| **Features** | | |
| Basic Queries | ✅ | ✅ |
| Transactions | ✅ | ✅ |
| Change Observation | ✅ | ✅ |
| CloudKit Sync | ✅ | ❌ (GRDB-only)* |
| Connection Pooling | ✅ | ❌ (planned) |
| FTS5 Full-Text Search | ✅ | ❌ (planned) |
| Custom Functions | ✅ | ❌ (planned) |
| **Performance** | | |
| Read Performance | Excellent | Good |
| Write Performance | Excellent | Good |
| Memory Usage | Low | Low |
| **Maturity** | | |
| Status | Stable | Active Development |
| Community | Large | Growing |
| Documentation | Extensive | Growing |

\* CloudKit synchronization requires GRDB-specific features (DatabaseMigrator, custom functions, connection pooling) and is not available with SQLiteNIO. See the [GRDB-Specific Features](#grdb-specific-features) section for details.

### When to Choose GRDB

- ✅ You need CloudKit synchronization
- ✅ You're only targeting Apple platforms
- ✅ You need FTS5 full-text search
- ✅ You prefer synchronous APIs
- ✅ You need maximum performance
- ✅ You want battle-tested stability

### When to Choose SQLiteNIO

- ✅ You need Linux support
- ✅ You prefer async/await throughout
- ✅ You're building server-side Swift apps
- ✅ You want modern Swift concurrency
- ✅ You need actor-based thread safety
- ✅ You're starting a new project

## Troubleshooting

### "No such module 'SQLiteNIO'" Error

**Problem**: Compiler can't find SQLiteNIO module.

**Solution**: 
1. Ensure SQLiteNIO is in your Package.swift dependencies
2. Check import spelling: `import SQLiteNIO` (case-sensitive)
3. Clean build folder: `swift package clean`

### "Default connection not configured" Error

**Problem**: Property wrapper can't find default connection.

**Solution**:
```swift
// Make sure you configure the connection in app init
@main
struct MyApp: App {
  init() {
    prepareDependencies {
      $0.defaultSQLiteConnection = try! await SQLiteConnection.open(/*...*/)
    }
  }
}
```

### Property Wrapper Not Updating

**Problem**: View doesn't update when database changes.

**Solution for GRDB**:
```swift
// Ensure you're using @FetchAll/@FetchOne, not manual database calls
@FetchAll var users: [User]  // ✅ Reactive
// not: let users = try database.read { ... }  // ❌ Not reactive
```

**Solution for SQLiteNIO**:
```swift
// Ensure you're using statement syntax
@FetchAll(User.all) var users  // ✅ Reactive
```

### CloudKit Tests Failing on Linux

**Problem**: CloudKit tests won't compile on Linux.

**Solution**: This is expected. CloudKit is Apple-platform only. Skip CloudKit tests on Linux:

```bash
# Run non-CloudKit tests only
swift test --filter "^((?!CloudKit).)*$"
```

### Mixed Engine Confusion

**Problem**: Not sure which engine a particular code is using.

**Solution**: Check the file location and imports:

```swift
// SQLiteNIO code
#if canImport(SQLiteNIO)
import SQLiteNIO
// This code uses SQLiteNIO
#endif

// GRDB code  
import GRDB
// This code uses GRDB

// Engine-agnostic code
import SQLiteData
@FetchAll var users: [User]
// Works with either engine based on configuration
```

## Best Practices

1. **Choose One Engine**: Start with one engine and stick with it unless you have specific needs for both

2. **Configure Early**: Set up your default database/connection in app initialization before any views load

3. **Be Consistent**: If using SQLiteNIO, always use explicit statement syntax in property wrappers

4. **Test Both Paths**: If supporting multiple engines, test with both configurations

5. **Document Your Choice**: Add a comment in your app initialization explaining why you chose a particular engine

6. **Migration Plan**: If switching engines, do it all at once rather than gradually to avoid confusion

7. **Type Safety**: Leverage Swift's type system - the compiler will prevent mixing engine-specific APIs

## Further Reading

- [PHASE_5_SUMMARY.md](PHASE_5_SUMMARY.md) - Detailed Phase 5 implementation
- [MIGRATION_PLAN.md](MIGRATION_PLAN.md) - Complete migration roadmap
- [SQLiteNIO README](Sources/SQLiteData/SQLiteNIO/README.md) - SQLiteNIO-specific documentation
- [GRDB Documentation](https://github.com/groue/GRDB.swift) - Official GRDB documentation
- [SQLiteNIO Documentation](https://github.com/vapor/sqlite-nio) - Official SQLiteNIO documentation
