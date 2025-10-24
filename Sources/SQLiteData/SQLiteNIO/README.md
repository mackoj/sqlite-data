# SQLiteNIO Integration (Experimental)

This directory contains experimental SQLiteNIO-based implementations that run alongside the existing GRDB code. The goal is to eventually replace GRDB with SQLiteNIO for cross-platform (including Linux) support.

## Status: Proof of Concept

This is a **proof of concept** demonstrating the key patterns needed for the migration. It is **not production-ready** and should not be used in real applications yet.

## What's Implemented

### 1. Database Protocols (`DatabaseProtocols.swift`)
- `SQLiteNIODatabase.Reader`: Protocol for read-only database access
- `SQLiteNIODatabase.Writer`: Protocol for read-write database access  
- `SQLiteNIODatabase.Connection`: Actor-isolated database connection wrapper
- `SQLiteNIODatabase.Queue`: Simple database queue for serialized access

These provide a GRDB-like API surface using async/await instead of dispatch queues.

### 2. Change Observer (`SQLiteNIOObserver.swift`)
- `SQLiteNIOObserver`: Actor that observes database changes
- Uses SQLite's update hook mechanism (placeholder implementation)
- Integrates with Swift's Sharing library
- Thread-safe via actor isolation

This replaces GRDB's `ValueObservation` system.

### 3. Row Decoder (`SQLiteRowDecoder.swift`)
- `SQLiteRowDecoder`: Decodes `Decodable` types from `SQLiteRow`
- Handles common types: primitives, Date, UUID, Data
- Similar to GRDB's `FetchableRecord` but using `Decodable`

## What's NOT Implemented

❌ Actual SQLite update hook installation (needs PR #90 or C interop)
❌ Statement caching and optimization
❌ Transaction management
❌ Connection pooling
❌ Integration with existing @FetchAll/@FetchOne property wrappers
❌ Migration of StructuredQueries integration
❌ CloudKit sync layer
❌ Comprehensive error handling
❌ Performance optimizations
❌ Tests

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

## Next Steps for Full Implementation

See `MIGRATION_PLAN.md` in the root directory for the complete implementation plan.

### Immediate TODOs:
1. **Install Update Hook**: Implement actual `sqlite3_update_hook` integration
   - Option A: Use SQLiteNIO PR #90 when available
   - Option B: Use raw SQLite3 C API via Swift interop
   - Option C: Extend SQLiteNIO with custom hook support

2. **Query Execution**: Create async versions of fetch methods
   - `fetchAll()` → async iterator over rows
   - `fetchOne()` → async single row fetch
   - `execute()` → async statement execution

3. **Integrate with FetchKey**: Update `FetchKey.swift` to optionally use SQLiteNIO
   - Add feature flag or runtime detection
   - Maintain backward compatibility with GRDB

4. **Transaction Support**: Implement transaction semantics
   - BEGIN/COMMIT/ROLLBACK handling
   - Savepoints for nested transactions
   - Proper error rollback

5. **Testing**: Create comprehensive tests
   - Unit tests for each component
   - Integration tests with Sharing library
   - Linux-specific tests
   - Performance benchmarks

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
