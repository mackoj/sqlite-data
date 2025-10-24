# Phase 3 Implementation Plan

## Overview

Phase 3 focuses on integrating SQLiteNIO observation with existing property wrappers while maintaining full backward compatibility with GRDB.

## Completed

### 1. Transaction Support ✅

Added comprehensive transaction support for SQLiteNIO:

```swift
// Basic transaction with automatic rollback
try await connection.transaction { conn in
  try await conn.query("INSERT INTO users (name) VALUES (?)", [.text("Alice")])
  try await conn.query("INSERT INTO posts (title) VALUES (?)", [.text("Post")])
}

// Deferred transaction (locks acquired on first read/write)
try await connection.deferredTransaction { conn in
  // ...
}

// Immediate transaction (write lock acquired immediately)
try await connection.immediateTransaction { conn in
  // ...
}

// Exclusive transaction (prevents all other access)
try await connection.exclusiveTransaction { conn in
  // ...
}

// Savepoints for nested transactions
try await connection.transaction { conn in
  try await conn.query("INSERT INTO users (name) VALUES (?)", [.text("Alice")])
  
  try? await conn.savepoint("inner") { conn in
    try await conn.query("INSERT INTO bad_table (data) VALUES (?)", [.text("Bad")])
    throw SomeError() // Only rolls back inner savepoint
  }
  
  // Alice is still inserted
}
```

## Remaining Work

### 2. Property Wrapper Integration

**Goal**: Make @FetchAll/@FetchOne work seamlessly with SQLiteNIO while maintaining GRDB compatibility.

**Approach**: Two options:

#### Option A: Automatic Detection (Preferred)
- Update FetchKey to detect if database is GRDB or SQLiteNIO
- Use appropriate observation mechanism automatically
- Completely transparent to users

#### Option B: Explicit Opt-In
- Add new initializers that accept SQLiteConnection
- Users explicitly choose SQLiteNIO
- Simpler implementation, clear intent

**Decision**: Start with Option B (explicit opt-in) as it:
- Maintains 100% backward compatibility
- Gives users explicit control
- Is easier to implement and test
- Can be upgraded to Option A later if needed

### Implementation Steps

1. **Add SQLiteConnection initializers to @FetchAll**
   ```swift
   @FetchAll(Item.all, connection: sqliteConnection) var items
   ```

2. **Add SQLiteConnection initializers to @FetchOne**
   ```swift
   @FetchOne(Item.count, connection: sqliteConnection) var count = 0
   ```

3. **Update FetchKeyRequest protocol**
   - Add method for fetching from SQLiteConnection
   - Keep existing GRDB methods

4. **Create SQLiteNIOFetchKey**
   - Similar to existing FetchKey but for SQLiteNIO
   - Uses SQLiteNIOObserver for change observation
   - Integrates with SharedReader

5. **Add examples and tests**

## Architecture

### Current (GRDB only)
```
@FetchAll
  └─> SharedReader
       └─> FetchKey
            ├─> load: DatabaseReader.asyncRead
            └─> subscribe: ValueObservation (GRDB)
```

### Phase 3 (Both GRDB and SQLiteNIO)
```
@FetchAll
  ├─> (database: DatabaseReader) ─> FetchKey ─> ValueObservation (GRDB)
  └─> (connection: SQLiteConnection) ─> SQLiteNIOFetchKey ─> SQLiteNIOObserver
```

## Usage Examples

### Example 1: Using GRDB (Existing, unchanged)
```swift
import SQLiteData
import GRDB

// Setup GRDB database
let dbQueue = try DatabaseQueue(path: "db.sqlite")

// Use with property wrappers (works as before)
struct ContentView: View {
  @FetchAll(User.all, database: dbQueue) var users
  
  var body: some View {
    List(users, id: \.id) { user in
      Text(user.name)
    }
  }
}
```

### Example 2: Using SQLiteNIO (New)
```swift
import SQLiteData
import SQLiteNIO

// Setup SQLiteNIO connection
let connection = try await SQLiteConnection.open(
  storage: .file(path: "db.sqlite"),
  threadPool: threadPool,
  on: eventLoop
).get()

// Use with property wrappers (new initializers)
struct ContentView: View {
  @FetchAll(User.all, connection: connection) var users
  
  var body: some View {
    List(users, id: \.id) { user in
      Text(user.name)
    }
  }
}
```

### Example 3: Transactions with SQLiteNIO
```swift
Button("Add User") {
  Task {
    try await connection.transaction { conn in
      // Use StructuredQueries with SQLiteNIO
      try await User.insert { $0.name; $0.email }
        .values { "Alice"; "alice@example.com" }
        .execute(conn)
      
      // Property wrappers automatically update!
    }
  }
}
```

## Testing Strategy

1. **Backward Compatibility Tests**
   - Verify existing @FetchAll/@FetchOne tests still pass
   - Ensure GRDB usage is unchanged

2. **SQLiteNIO Integration Tests**
   - Test property wrappers with SQLiteConnection
   - Verify automatic updates on database changes
   - Test with transactions

3. **Mixed Usage Tests**
   - Use both GRDB and SQLiteNIO in same app
   - Verify no conflicts or issues

## Timeline

- Transaction Support: ✅ Complete (2 hours)
- Property Wrapper Integration: 🔄 In Progress (4-6 hours)
  - SQLiteConnection initializers (1-2 hours)
  - SQLiteNIOFetchKey implementation (2-3 hours)
  - Tests and examples (1 hour)
- Documentation: 📝 Pending (1 hour)

**Total Estimated**: 7-9 hours
**Completed**: 2 hours
**Remaining**: 5-7 hours

## Success Criteria

- [ ] @FetchAll works with SQLiteConnection
- [ ] @FetchOne works with SQLiteConnection
- [ ] Automatic UI updates when database changes (via SQLiteNIOObserver)
- [ ] Transaction support tested and working
- [ ] Examples demonstrate usage
- [ ] All existing tests still pass
- [ ] New tests for SQLiteNIO integration pass
- [ ] Documentation updated

## Notes

- Keep public API consistent between GRDB and SQLiteNIO versions
- Minimize code duplication
- Ensure proper error handling and cleanup
- Consider adding convenience methods for common patterns
