# SQLiteNIO Integration (Phase 2 Complete)

This directory contains SQLiteNIO-based implementations that run alongside the existing GRDB code. The goal is to eventually replace GRDB with SQLiteNIO for cross-platform (including Linux) support.

## Status: Phase 2 Complete - ValueObservation Implemented

**Phase 2 is now complete!** The core observation mechanics using SQLiteNIO 1.12.0's native update hooks are fully functional. This implementation provides real-time database change observation similar to GRDB's ValueObservation.

## What's Implemented

### ✅ Phase 1: Foundation Layer (Complete)

#### 1. Database Protocols (`DatabaseProtocols.swift`)
- `SQLiteNIODatabase.Reader`: Protocol for read-only database access
- `SQLiteNIODatabase.Writer`: Protocol for read-write database access  
- `SQLiteNIODatabase.Connection`: Actor-isolated database connection wrapper
- `SQLiteNIODatabase.Queue`: Simple database queue for serialized access

These provide a GRDB-like API surface using async/await instead of dispatch queues.

#### 2. Row Decoder (`SQLiteRowDecoder.swift`)
- `SQLiteRowDecoder`: Decodes `Decodable` types from `SQLiteRow`
- Handles common types: primitives, Date, UUID, Data
- Similar to GRDB's `FetchableRecord` but using `Decodable`

### ✅ Phase 2: ValueObservation Mechanics (Complete)

#### 3. Change Observer (`SQLiteNIOObserver.swift`) - **NOW WITH REAL UPDATE HOOKS!**
- `SQLiteNIOObserver`: Actor that observes database changes
- **Uses SQLiteNIO 1.12.0's native `addUpdateObserver` API**
- **Real-time change notifications** via sqlite3_update_hook
- Integrates with Swift's Sharing library
- Thread-safe via actor isolation
- Automatic hook lifecycle management

This **fully replaces** GRDB's `ValueObservation` system.

#### 4. Query Execution (`Statement+SQLiteNIO.swift`)
- Extensions for `StructuredQueriesCore.Statement`
- `execute()`: Execute INSERT/UPDATE/DELETE queries
- `fetchAll()`: Fetch all rows and decode to Swift types
- `fetchOne()`: Fetch a single row
- Proper binding conversion from StructuredQueries to SQLiteNIO

#### 5. FetchKey Integration (`FetchKey+SQLiteNIO.swift`)
- `FetchKeyNIO`: SharedReaderKey implementation for SQLiteNIO
- Integrates with Swift Sharing library
- Automatic re-fetching on database changes
- Compatible with @FetchAll/@FetchOne pattern

## What's NOT Yet Implemented

❌ Complete integration with existing @FetchAll/@FetchOne property wrappers (use FetchKeyNIO instead)
❌ Statement caching and optimization
❌ Full transaction management (BEGIN/COMMIT/ROLLBACK)
❌ Connection pooling (read/write separation)
❌ CloudKit sync layer migration
❌ Comprehensive error handling
❌ Performance optimizations
❌ Comprehensive tests

## Architecture Comparison

### GRDB (Current)
```
@FetchAll → ValueObservation → DatabaseQueue → GRDB → SQLite
                ↓
        TransactionObserver
                ↓
        Combine Publishers
```

### SQLiteNIO (Target)
```
@FetchAll → SQLiteNIOObserver → Connection → SQLiteNIO → SQLite
                ↓                     ↓
        sqlite3_update_hook    NIO EventLoop
                ↓
        Swift Sharing/Observation
```

## Phase 2 Implementation Details

### Update Hook Integration

We now use SQLiteNIO 1.12.0's **native update hook support**:

```swift
// Install the hook
let token = try await connection.addUpdateObserver(lifetime: .pinned) { event in
  // Called immediately when INSERT/UPDATE/DELETE occurs
  print("Table \(event.table) row \(event.rowID) changed: \(event.operation)")
}

// Clean up
token.cancel()
```

Key features:
- **Immediate notification**: Callbacks fire as soon as changes occur
- **Table-level filtering**: Subscribe only to specific tables
- **Operation types**: Know whether it was INSERT, UPDATE, or DELETE
- **Row IDs**: Get the exact row that changed
- **Automatic cleanup**: Use lifetime management (`.scoped` or `.pinned`)

### Query Execution

Execute StructuredQueries statements directly on SQLiteNIO connections:

```swift
// Execute a query
try await User.insert { $0.name; $0.email }
  .values { "Alice"; "alice@example.com" }
  .execute(connection)

// Fetch all
let users = try await User.all.fetchAll(connection)

// Fetch one
let user = try await User.where { $0.id == 1 }.fetchOne(connection)
```

### Integration with Sharing Library

Use `FetchKeyNIO` for reactive data access:

```swift
@SharedReader(.fetchNIO(User.all, connection: connection))
var users: [User] = []

// users automatically updates when the database changes!
```

## Next Steps for Full Implementation

See `MIGRATION_PLAN.md` in the root directory for the complete implementation plan.

### Phase 3: Property Wrapper Integration (Next)
1. **Integrate FetchKeyNIO with @FetchAll/@FetchOne**
   - Update property wrappers to optionally use FetchKeyNIO
   - Add feature flag for GRDB vs SQLiteNIO
   - Maintain backward compatibility

2. **Transaction Support**: Implement full transaction semantics
   - BEGIN/COMMIT/ROLLBACK handling
   - Savepoints for nested transactions
   - Proper error rollback

3. **Testing**: Create comprehensive tests
   - Unit tests for each component
   - Integration tests with Sharing library
   - Linux-specific tests
   - Performance benchmarks vs GRDB

## Usage Example (Conceptual)

```swift
import SQLiteNIO

// Create connection
let connection = try await SQLiteConnection.open(path: "db.sqlite")
let queue = SQLiteNIODatabase.Queue(connection: connection)

// Query data
let rows = try await queue.asyncRead { conn in
  try await conn.query(sql: "SELECT * FROM users WHERE id = ?", bindings: [.integer(1)])
}

// Decode rows
for row in rows {
  let user = try row.decode(User.self)
  print(user.name)
}

// Observe changes
let observer = SQLiteNIOObserver(connection: connection)
let subscription = observer.subscribe(tables: ["users"]) { change in
  print("Table \(change.tableName) changed")
}
```

## Known Limitations

1. **Update Hook**: Not actually installed - placeholder only
2. **No Pooling**: Single connection, no read/write separation
3. **No Caching**: Every query re-parses SQL
4. **Blocking**: Some operations may block the EventLoop
5. **Error Handling**: Minimal error context and recovery
6. **Thread Safety**: Relies entirely on actor isolation

## Contributing

This is experimental code. Before contributing:
1. Read `MIGRATION_PLAN.md` for context
2. Discuss approach in an issue first
3. Focus on one component at a time
4. Add tests for any new functionality
5. Ensure Linux compatibility

## Resources

- [SQLiteNIO GitHub](https://github.com/vapor/sqlite-nio)
- [SQLiteNIO PR #90 - Hook Support](https://github.com/vapor/sqlite-nio/pull/90)
- [Swift Sharing Library](https://github.com/pointfreeco/swift-sharing)
- [StructuredQueries](https://github.com/pointfreeco/swift-structured-queries)
- [GRDB Documentation](https://github.com/groue/GRDB.swift)
