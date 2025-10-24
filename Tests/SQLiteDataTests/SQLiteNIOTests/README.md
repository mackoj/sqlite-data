# SQLiteNIO Tests

This directory contains SQLiteNIO-specific test suites that mirror the GRDB tests but use SQLiteNIO as the underlying database engine.

## Test Files

### Core Tests
- **AssertQueryNIOTests.swift**: Tests for the `assertQueryNIO` helper function
- **FetchAllNIOTests.swift**: Tests for `@FetchAll` property wrapper with SQLiteNIO
- **FetchOneNIOTests.swift**: Tests for `@FetchOne` property wrapper with SQLiteNIO
- **IntegrationNIOTests.swift**: End-to-end integration tests with SQLiteNIO
- **QueryCursorNIOTests.swift**: Tests for query execution and cursor operations

### Key Differences from GRDB Tests

1. **Dependency Configuration**: Uses `@Dependency(\.defaultSQLiteConnection)` instead of `@Dependency(\.defaultDatabase)`
2. **Async/Await**: All database operations are async
3. **Test Setup**: Each test suite creates an in-memory SQLiteConnection with test data
4. **Property Wrapper Syntax**: Uses explicit statement syntax: `@FetchAll(User.all)` instead of `@FetchAll var users: [User]`

## Running SQLiteNIO Tests

Run all SQLiteNIO tests:
```bash
swift test --filter SQLiteNIOTests
```

Run a specific test suite:
```bash
swift test --filter FetchAllNIOTests
```

## Tests Not Included

Some tests from the main test suite are not included here because they are:

1. **CompileTimeTests**: Compile-time verification tests don't need engine-specific versions
2. **CustomFunctionTests**: Custom function registration is GRDB-specific (SQLiteNIO support planned)
3. **DatabaseFunctionTests**: Similar to CustomFunctionTests, depends on GRDB's function system
4. **MigrationTests**: Migration patterns are similar but table creation uses different APIs
5. **PrimaryKeyMigrationTests**: CloudKit-specific migration tests

## Test Helper Functions

### assertQueryNIO

The `assertQueryNIO` function in `Sources/SQLiteDataTestSupport/AssertQueryNIO.swift` provides snapshot testing for SQLiteNIO queries:

```swift
await assertQueryNIO(
  User.select(\.name).order(by: \.name)
) {
  """
  ┌───────┐
  │ "Alice" │
  │ "Bob"   │
  │ "Charlie" │
  └───────┘
  """
}
```

Key differences from `assertQuery`:
- Function is `async` (uses `await`)
- Takes `connection: SQLiteConnection?` instead of `database: DatabaseWriter?`
- Uses `@Dependency(\.defaultSQLiteConnection)` for default connection

## Test Data Setup

Each test file includes a helper extension on `SQLiteConnection` to create test connections:

```swift
extension SQLiteConnection {
  fileprivate static func nioTestConnection() async throws -> SQLiteConnection {
    let connection = try await SQLiteConnection.open(storage: .memory)
    
    // Create tables
    try await connection.query("CREATE TABLE ...", [])
    
    // Insert test data
    try await connection.transaction { conn in
      // Insert data...
    }
    
    return connection
  }
}
```

## Coverage

These tests cover:
- ✅ Property wrapper functionality (@FetchAll, @FetchOne)
- ✅ Query execution (fetchAll, fetchOne)
- ✅ Transaction support (transaction, savepoint)
- ✅ CRUD operations (create, read, update, delete)
- ✅ Query operations (where, order, limit, offset)
- ✅ Aggregate functions (count)
- ✅ Snapshot testing with assertQueryNIO

## Future Enhancements

Planned additions:
- Custom function support for SQLiteNIO
- Migration testing patterns
- Performance benchmarks vs GRDB
- Concurrent access tests
- Connection pooling tests
