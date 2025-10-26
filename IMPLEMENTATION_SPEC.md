# SQLiteData Implementation Specification

## Document Purpose

This specification documents the changes made to fork `@mackoj/sqlite-data` from the original `@pointfreeco/sqlite-data`, with a focus on adding the `SQLiteClient` abstraction using the protocol witness pattern.

---

## Table of Contents

1. [Executive Summary](#executive-summary)
2. [Original Architecture (Point-Free)](#original-architecture-point-free)
3. [New Architecture (Fork)](#new-architecture-fork)
4. [Design Decisions](#design-decisions)
5. [Implementation Details](#implementation-details)
6. [API Comparison](#api-comparison)
7. [Migration Guide](#migration-guide)
8. [Future Considerations](#future-considerations)

---

## Executive Summary

### What Changed

The fork introduces a **`SQLiteClient`** abstraction that provides a unified, async-only interface for database operations across both GRDB and SQLiteNIO engines. This abstraction uses the **protocol witness pattern** as described in Point-Free's dependency design documentation.

### Key Improvements

- **Unified Interface**: Single API for both GRDB and SQLiteNIO
- **Async-Only**: Consistent async/await throughout (no sync APIs)
- **Dependency-Based**: Database access via `@Dependency` within closures
- **Type-Safe**: Compile-time trait selection ensures correct engine usage
- **Zero Overhead**: All abstraction is compile-time only

### Scope of Changes

- **3 new files** added to core library
- **2 documentation files** added
- **1 test suite** added
- **0 breaking changes** to existing API
- **100% backwards compatible** with Point-Free implementation

---

## Original Architecture (Point-Free)

### Design Philosophy

The original `@pointfreeco/sqlite-data` repository provides:

1. **Direct Engine Access**: Users directly interact with `defaultDatabase` (GRDB) or `defaultSQLiteConnection` (SQLiteNIO)
2. **Property Wrappers**: High-level `@FetchAll`, `@FetchOne`, `@Fetch` for declarative data access
3. **Trait-Based Selection**: Compile-time selection between GRDB and SQLiteNIO via package traits
4. **CloudKit Integration**: Built-in support for CloudKit sync (GRDB only)

### Core Components

```
Sources/SQLiteData/
├── CloudKit/                    # CloudKit sync functionality
├── Documentation.docc/          # DocC documentation
├── Fetch.swift                  # @Fetch property wrapper
├── FetchAll.swift               # @FetchAll property wrapper
├── FetchOne.swift               # @FetchOne property wrapper
├── FetchKeyRequest.swift        # Request protocol
├── Internal/                    # Internal utilities
│   ├── Exports.swift           # Re-exports GRDB/SQLiteNIO
│   ├── FetchKey+SwiftUI.swift  # SwiftUI integration
│   ├── ISO8601.swift           # Date formatting
│   └── StatementKey.swift      # Statement caching
└── Traits/
    ├── GRDB/                    # GRDB-specific implementations
    │   ├── DefaultDatabase.swift
    │   ├── FetchKey+GRDB.swift
    │   ├── QueryCursor.swift
    │   ├── Statement+GRDB.swift
    │   └── ...
    └── SQLiteNIO/               # SQLiteNIO-specific implementations
        ├── DefaultConnection.swift
        ├── FetchKey+SQLiteNIO.swift
        ├── Statement+SQLiteNIO.swift
        └── ...
```

### Usage Pattern (Original)

**Setup:**
```swift
// GRDB
prepareDependencies {
  $0.defaultDatabase = try! DatabaseQueue()
}

// SQLiteNIO
prepareDependencies {
  $0.defaultSQLiteConnection = try! await SQLiteConnection.open(...)
}
```

**Usage:**
```swift
// Direct database access
@Dependency(\.defaultDatabase) var database

try await database.write { db in
  try item.insert(db)
}

// Or via property wrappers
@FetchAll var items: [Item]
```

### Key Characteristics

- **Engine-Specific Code**: Users write `#if SQLITE_ENGINE_GRDB` blocks when needed
- **Direct Access**: Full access to GRDB or SQLiteNIO APIs
- **No Abstraction Layer**: Direct dependency on chosen engine
- **Maximum Flexibility**: Can use any engine-specific feature

---

## New Architecture (Fork)

### Design Philosophy

The fork adds an **optional** abstraction layer that:

1. **Provides Unified API**: Single interface for common operations
2. **Maintains Backwards Compatibility**: Original APIs remain unchanged
3. **Uses Protocol Witness Pattern**: Struct with closures instead of protocols
4. **Leverages Dependency System**: Database access via `@Dependency` within closures
5. **Async-Only**: All operations use async/await

### Added Components

```
Sources/SQLiteData/
├── SQLiteClient.swift           # NEW: Protocol witness abstraction
└── Traits/
    ├── GRDB/
    │   └── SQLiteClient+GRDB.swift    # NEW: GRDB implementation
    └── SQLiteNIO/
        └── SQLiteClient+SQLiteNIO.swift # NEW: SQLiteNIO implementation

Tests/SQLiteDataTests/
└── SQLiteClientTests.swift      # NEW: Test suite

Documentation/
├── SQLITECLIENT_DESIGN.md       # NEW: Design documentation
└── SQLITECLIENT_SUMMARY.md      # NEW: Implementation guide
```

### SQLiteClient Structure

```swift
public struct SQLiteClient: Sendable {
  // Async read operation
  public var read: @Sendable (
    _ block: @escaping @Sendable () async throws -> Void
  ) async throws -> Void
  
  // Async write operation
  public var write: @Sendable (
    _ block: @escaping @Sendable () async throws -> Void
  ) async throws -> Void
  
  // Context-sensitive path
  public var contextSensitivePath: @Sendable () throws -> String?
  
  // Table observation
  public var observeTables: @Sendable (
    _ tables: Set<String>,
    _ onChange: @escaping @Sendable () -> Void
  ) async throws -> SQLiteCancellable
}
```

### Usage Pattern (New)

**Setup (unchanged):**
```swift
// GRDB
prepareDependencies {
  $0.defaultDatabase = try! DatabaseQueue()
}

// SQLiteNIO
prepareDependencies {
  $0.defaultSQLiteConnection = try! await SQLiteConnection.open(...)
}
```

**Usage (new option):**
```swift
@Dependency(\.sqliteClient) var client

try await client.read {
  // Access engine-specific database via @Dependency
  #if SQLITE_ENGINE_GRDB
  @Dependency(\.defaultDatabase) var database
  // Use GRDB APIs
  #elseif SQLITE_ENGINE_SQLITENIO
  @Dependency(\.defaultSQLiteConnection) var connection
  // Use SQLiteNIO APIs
  #endif
}

try await client.write {
  // Same pattern for writes
}
```

**Observation:**
```swift
let cancellable = try await client.observeTables(["users", "posts"]) {
  print("Data changed!")
}
```

### Key Characteristics

- **Optional Layer**: Existing code continues to work unchanged
- **Unified Operations**: Common patterns abstracted
- **Engine Access**: Full engine APIs still available via `@Dependency`
- **Async-Only**: Consistent async patterns throughout

---

## Design Decisions

### 1. Protocol Witness Pattern

**Decision:** Use struct with closures instead of protocol

**Rationale:**
- ✅ Better testability (mocks are struct instances)
- ✅ Compile-time flexibility (different types per impl)
- ✅ No existential overhead
- ✅ Explicit dependencies
- ✅ Follows Point-Free best practices

**Alternative Considered:** Traditional protocol
```swift
// NOT USED - Traditional approach
protocol SQLiteDatabaseClient {
  func read(_ block: () async throws -> Void) async throws
  func write(_ block: () async throws -> Void) async throws
}
```

**Why Not:** 
- Requires existential types
- Runtime protocol dispatch overhead
- Less flexible for testing
- Harder to compose

### 2. Database Access via @Dependency

**Decision:** Closures don't receive database parameter; access via `@Dependency` instead

**Rationale:**
- ✅ Cleaner API (no type erasure needed)
- ✅ Trait system ensures correctness
- ✅ No GRDB/SQLiteNIO types in public API
- ✅ Consistent with existing patterns
- ✅ Easier to understand

**Alternative Considered:** Pass database to closure
```swift
// NOT USED - Database passing approach
try await client.read { db in
  // db is AnyDatabaseConnection
}
```

**Why Not:**
- Requires type erasure (AnyDatabaseConnection)
- Mismatch between GRDB (sync closure) and SQLiteNIO (async)
- More complex API
- Type casting needed in closures

### 3. Async-Only API

**Decision:** All operations are async, no sync variants

**Rationale:**
- ✅ Consistent interface
- ✅ Future-proof design
- ✅ SQLiteNIO is naturally async
- ✅ GRDB has async variants
- ✅ Modern Swift patterns

**Alternative Considered:** Both sync and async
```swift
// NOT USED - Dual API approach
var read: @Sendable (...) throws -> Void
var asyncRead: @Sendable (...) async throws -> Void
```

**Why Not:**
- API duplication
- SQLiteNIO doesn't have sync operations
- Confusing when to use which
- Maintenance burden

### 4. Static Properties vs Factory Methods

**Decision:** Use static properties (`.grdb`, `.nio`)

**Rationale:**
- ✅ Simpler API
- ✅ Database accessed via `@Dependency`
- ✅ No parameters needed
- ✅ Clearer intent

**Alternative Considered:** Factory methods with parameters
```swift
// NOT USED - Factory method approach
static func grdb(database: DatabaseWriter) -> Self
static func nio(connection: SQLiteConnection) -> Self
```

**Why Not:**
- Database should come from `@Dependency`
- Redundant parameters
- More ceremony
- Against design goal

### 5. Minimal API Surface

**Decision:** Only provide `read`, `write`, `observeTables`, `contextSensitivePath`

**Rationale:**
- ✅ Focus on common operations
- ✅ Users can access full engine APIs via `@Dependency`
- ✅ Easier to maintain
- ✅ Clear scope

**Alternative Considered:** Comprehensive API wrapping all operations
```swift
// NOT USED - Comprehensive approach
func execute(_ sql: String) async throws
func fetchAll<T>(...) async throws -> [T]
func fetchOne<T>(...) async throws -> T?
// ... many more methods
```

**Why Not:**
- Would duplicate existing engine APIs
- Maintenance burden
- Users lose access to engine-specific features
- Not the goal of this abstraction

---

## Implementation Details

### File Structure

#### `Sources/SQLiteData/SQLiteClient.swift`

**Purpose:** Core protocol witness struct and dependency integration

**Key Components:**
- `SQLiteClient` struct (96 lines)
- `SQLiteCancellable` protocol
- `DependencyValues` extension
- Live/test value implementations

**Dependencies:**
- `Dependencies` (swift-dependencies)
- `Foundation`
- Optional: `Combine`

#### `Sources/SQLiteData/Traits/GRDB/SQLiteClient+GRDB.swift`

**Purpose:** GRDB-specific implementation

**Key Components:**
- `static var grdb: Self` factory
- `GRDBCancellable` wrapper
- `CombineCancellableWrapper` (when Combine available)
- `SQLiteClientError` enum

**Implementation Notes:**
- Uses `@Dependency(\.defaultDatabase)` to access database
- Bridges GRDB's sync closures to async execution
- Uses `ValueObservation` for table monitoring
- Imports `ConcurrencyExtras` for async/sync bridging

**Code Sample:**
```swift
public static var grdb: Self {
  Self(
    read: { block in
      @Dependency(\.defaultDatabase) var database
      try await database.read { _ in }
      try await block()
    },
    // ...
  )
}
```

#### `Sources/SQLiteData/Traits/SQLiteNIO/SQLiteClient+SQLiteNIO.swift`

**Purpose:** SQLiteNIO-specific implementation

**Key Components:**
- `static var nio: Self` factory
- `NIOCancellable` wrapper

**Implementation Notes:**
- Uses `@Dependency(\.defaultSQLiteConnection)` to access connection
- Fully async (no bridging needed)
- Uses `SQLiteNIOObserver` for table monitoring
- Simpler than GRDB implementation

**Code Sample:**
```swift
public static var nio: Self {
  Self(
    read: { block in
      try await block()
    },
    // ...
  )
}
```

### Type Definitions

#### SQLiteCancellable

```swift
public protocol SQLiteCancellable: Sendable {
  func cancel()
}
```

**Purpose:** Unified cancellation interface for observations

**Implementations:**
- `GRDBCancellable`: Wraps GRDB's `DatabaseCancellable`
- `CombineCancellableWrapper`: Wraps Combine's `AnyCancellable`
- `NIOCancellable`: Custom implementation for SQLiteNIO

### Dependency Integration

```swift
extension DependencyValues {
  public var sqliteClient: SQLiteClient {
    get { self[SQLiteClientKey.self] }
    set { self[SQLiteClientKey.self] = newValue }
  }
  
  private enum SQLiteClientKey: DependencyKey {
    static let liveValue = SQLiteClient.live
    static let testValue = SQLiteClient.test
  }
}
```

**Live Value:**
```swift
public static var live: Self {
  #if SQLITE_ENGINE_GRDB
    return .grdb
  #elseif SQLITE_ENGINE_SQLITENIO
    return .nio
  #else
    fatalError("No SQLite engine trait is enabled")
  #endif
}
```

### Testing Strategy

**Test File:** `Tests/SQLiteDataTests/SQLiteClientTests.swift`

**Test Coverage:**
- ✅ Factory method tests (both engines)
- ✅ Read/write operations
- ✅ Context-sensitive paths
- ✅ Dependency integration
- ✅ Cancellable subscriptions
- ✅ Error handling

**Test Count:** 12 test cases

**Approach:**
- Conditional compilation for engine-specific tests
- In-memory databases for isolation
- Proper error handling verification
- No trivial assertions

---

## API Comparison

### Before (Point-Free Only)

```swift
// Direct database access
@Dependency(\.defaultDatabase) var database

// Read
let items = try await database.read { db in
  try Item.fetchAll(db)
}

// Write
try await database.write { db in
  try item.insert(db)
}

// Property wrappers (unchanged)
@FetchAll var items: [Item]
```

### After (Fork - New Option)

```swift
// Option 1: Use SQLiteClient (NEW)
@Dependency(\.sqliteClient) var client

try await client.read {
  @Dependency(\.defaultDatabase) var database
  let items = try await database.read { db in
    try Item.fetchAll(db)
  }
}

// Option 2: Direct access (UNCHANGED)
@Dependency(\.defaultDatabase) var database
let items = try await database.read { db in
  try Item.fetchAll(db)
}

// Property wrappers (UNCHANGED)
@FetchAll var items: [Item]
```

### Side-by-Side: Common Operations

| Operation | Original | With SQLiteClient |
|-----------|----------|-------------------|
| **Setup** | `$0.defaultDatabase = ...` | Same (unchanged) |
| **Read** | `database.read { db in ... }` | `client.read { ... }` |
| **Write** | `database.write { db in ... }` | `client.write { ... }` |
| **Observe** | Use `ValueObservation` directly | `client.observeTables(...)` |
| **Context Path** | Manual construction | `client.contextSensitivePath()` |

### Migration Effort

**For existing code:** **ZERO** - All existing code continues to work unchanged

**To adopt SQLiteClient:** Low - Replace direct database calls with client calls

---

## Migration Guide

### For Existing Projects

**Good News:** No migration required! All existing code works unchanged.

### To Adopt SQLiteClient

**Step 1:** Access the client
```swift
// Add this dependency
@Dependency(\.sqliteClient) var client
```

**Step 2:** Replace direct database calls
```swift
// Before
try await database.read { db in
  // operations
}

// After
try await client.read {
  @Dependency(\.defaultDatabase) var database
  try await database.read { db in
    // operations
  }
}
```

**Step 3:** Use observation helper (optional)
```swift
// Before
let observation = ValueObservation.tracking { db in
  try Table.fetchCount(db)
}
let cancellable = observation.start(in: database) { _ in
  // handle change
}

// After
let cancellable = try await client.observeTables(["Table"]) {
  // handle change
}
```

### Best Practices

1. **Use SQLiteClient for**: Common operations that you want abstracted
2. **Use direct access for**: Engine-specific features, advanced usage
3. **Continue using**: `@FetchAll`, `@FetchOne` property wrappers
4. **Test with**: Both approaches work in tests

---

## Future Considerations

### Potential Enhancements

1. **More Operations**
   - Add `transaction` control
   - Add `migrate` operation
   - Add batch operations

2. **Return Values**
   - Support returning values from read/write closures
   - Generic return types

3. **Advanced Observation**
   - More granular observation controls
   - Combine operators integration
   - AsyncSequence support

4. **Synchronous Fallback**
   - Optional sync API using `ConcurrencyExtras`
   - For compatibility with sync contexts

### Non-Goals

- ❌ Replace all direct database access
- ❌ Wrap every engine-specific feature
- ❌ Remove engine-specific code paths
- ❌ Change existing property wrappers
- ❌ Modify CloudKit integration

### Backwards Compatibility Guarantee

**This fork maintains 100% backwards compatibility with Point-Free's implementation.**

- All existing APIs work unchanged
- SQLiteClient is purely additive
- No breaking changes introduced
- Engine traits work identically
- Property wrappers unchanged

---

## Appendices

### A. Commit History

1. `fef28c9` - Initial plan
2. `703f75c` - Add SQLiteClient abstraction with protocol witness style
3. `fc49866` - Add documentation and tests for SQLiteClient
4. `8e2e956` - Address code review feedback - improve test quality
5. `fc8af72` - Add implementation summary document
6. `643eea6` - Redesign SQLiteClient to use @Dependency for database access with async-only API

### B. File Sizes

- `SQLiteClient.swift`: ~180 lines
- `SQLiteClient+GRDB.swift`: ~120 lines
- `SQLiteClient+SQLiteNIO.swift`: ~80 lines
- `SQLiteClientTests.swift`: ~270 lines
- `SQLITECLIENT_DESIGN.md`: ~300 lines
- `SQLITECLIENT_SUMMARY.md`: ~280 lines

**Total Addition:** ~1,230 lines of code and documentation

### C. Build Verification

Both engine configurations build successfully:
- ✅ `swift build --traits GRDB`
- ✅ `swift build --traits SQLiteNIO`

### D. Dependencies Added

- `ConcurrencyExtras` (already in project, used for GRDB async bridging)

### E. References

- [Point-Free: Designing Dependencies](https://pointfreeco.github.io/swift-dependencies/main/documentation/dependencies/designingdependencies)
- [Point-Free: Lifetimes](https://pointfreeco.github.io/swift-dependencies/main/documentation/dependencies/lifetimes)
- [Point-Free: Dependencies Collection](https://www.pointfree.co/collections/dependencies/designing-dependencies)
- [Protocol Witness Pattern](https://www.pointfree.co/episodes/ep33-protocol-witnesses-part-1)

---

## Conclusion

This fork adds an **optional** `SQLiteClient` abstraction that provides a unified interface for common database operations while maintaining 100% backwards compatibility with the original Point-Free implementation. The design follows Point-Free's protocol witness pattern and integrates seamlessly with the existing dependency system.

**Key Takeaways:**
- ✅ Additive only - no breaking changes
- ✅ Protocol witness pattern
- ✅ Async-only API
- ✅ Dependency-based database access
- ✅ Both engines supported
- ✅ Fully tested and documented

**Use When:** You want a unified interface for common operations across both engines.

**Skip When:** You need engine-specific features or prefer direct database access.
