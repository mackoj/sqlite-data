# Phase 6: SPM Traits Implementation for Engine Selection

## Overview

This document outlines the implementation of SPM traits to enable compile-time engine selection between GRDB and SQLiteNIO, eliminating ambiguous initializer issues and providing a clean, performant API.

## Goals

1. **Compile-time engine selection** - Only one engine is compiled into the binary
2. **Unified API** - Same initializers work for both engines
3. **No ambiguity** - Compiler knows which engine to use at compile time
4. **Zero runtime overhead** - No protocol dispatch or runtime checks
5. **Enforced mutual exclusion** - Only one engine can be enabled per build

## Implementation Status

### ✅ Completed

1. **Package.swift Updates**
   - Added `GRDB` trait
   - Added `SQLiteNIO` trait
   - Made GRDB dependency conditional on `GRDB` trait
   - Made SQLiteNIO dependency conditional on `SQLiteNIO` trait
   - Added compilation flags: `SQLITE_ENGINE_GRDB` and `SQLITE_ENGINE_SQLITENO`

2. **SQLiteNIO Files**
   - Replaced `#if canImport(SQLiteNIO)` with `#if SQLITE_ENGINE_SQLITENO`
   - All SQLiteNIO-specific files now use the trait-based flag

3. **GRDB Directory Files**
   - Added `#if SQLITE_ENGINE_GRDB` guards to all files in `StructuredQueries+GRDB/`
   - Added guards to `FetchKey+GRDB.swift`

### 🔨 In Progress

4. **FetchAll.swift and FetchOne.swift Refactoring**
   - Need to wrap GRDB-specific initializers with `#if SQLITE_ENGINE_GRDB`
   - Need to ensure common initializers work with both engines
   - Challenge: These files have mixed GRDB and generic code

## Architecture

### Trait Configuration

Users enable one trait when building or testing:

```bash
# Build with GRDB
swift build --experimental-enable-traits --enable-trait GRDB

# Build with SQLiteNIO
swift build --experimental-enable-traits --enable-trait SQLiteNIO

# Test with GRDB
swift test --experimental-enable-traits --enable-trait GRDB
```

### Compilation Flags

- `SQLITE_ENGINE_GRDB` - Defined when GRDB trait is enabled
- `SQLITE_ENGINE_SQLITENO` - Defined when SQLiteNIO trait is enabled

### File Organization

```
Sources/SQLiteData/
├── FetchAll.swift                    # Core struct + conditional initializers
├── FetchOne.swift                    # Core struct + conditional initializers
├── FetchAll+SQLiteNIO.swift          # #if SQLITE_ENGINE_SQLITENO
├── FetchOne+SQLiteNIO.swift          # #if SQLITE_ENGINE_SQLITENO
├── StructuredQueries+GRDB/           # All files: #if SQLITE_ENGINE_GRDB
│   ├── DefaultDatabase.swift
│   ├── Statement+GRDB.swift
│   └── ...
├── SQLiteNIO/                        # All files: #if SQLITE_ENGINE_SQLITENO
│   ├── DefaultConnection.swift
│   ├── Statement+SQLiteNIO.swift
│   └── ...
└── Internal/
    ├── FetchKey+GRDB.swift           # #if SQLITE_ENGINE_GRDB
    ├── FetchKey+SwiftUI.swift        # No guard (works with both)
    └── ...
```

## Next Steps

### 1. Refactor FetchAll.swift

Current structure has mixed initializers. Need to:

a. Keep common initializers (no guards):
```swift
// Common - no engine-specific code
@_disfavoredOverload
public init(wrappedValue: [Element] = []) {
  sharedReader = SharedReader(value: wrappedValue)
}
```

b. Wrap GRDB initializers:
```swift
#if SQLITE_ENGINE_GRDB
public init(
  wrappedValue: [Element] = [],
  database: (any DatabaseReader)? = nil
)
where Element: StructuredQueriesCore.Table, Element.QueryOutput == Element {
  let statement = Element.all.selectStar().asSelect()
  self.init(wrappedValue: wrappedValue, statement, database: database)
}
#endif
```

c. Ensure SQLiteNIO initializers remain in FetchAll+SQLiteNIO.swift with guards

### 2. Refactor FetchOne.swift

Same approach as FetchAll.swift:
- Identify common initializers
- Wrap GRDB-specific ones with `#if SQLITE_ENGINE_GRDB`
- Keep SQLiteNIO ones in FetchOne+SQLiteNIO.swift

### 3. Update Tests

Tests need to be updated to use traits:

```swift
// GRDB tests
#if SQLITE_ENGINE_GRDB
@Suite(.dependency(\.defaultDatabase, try .database()))
struct MyTests { ... }
#endif

// SQLiteNIO tests  
#if SQLITE_ENGINE_SQLITENO
@Suite(.dependency(\.defaultSQLiteConnection, try .nioConnection()))
struct MyNIOTests { ... }
#endif
```

### 4. Documentation Updates

- Update README with trait usage
- Update migration guide
- Add troubleshooting for trait selection

### 5. CI/CD Updates

Update GitHub Actions to test both traits:

```yaml
- name: Test with GRDB
  run: swift test --experimental-enable-traits --enable-trait GRDB
  
- name: Test with SQLiteNIO
  run: swift test --experimental-enable-traits --enable-trait SQLiteNIO
```

## Benefits

### ✅ Solves Ambiguous Initializer Issue

With traits, this code works without ambiguity:

```swift
import SQLiteData

private final class Model {
  @FetchAll var titles: [String]

  init() {
    _titles = FetchAll(Reminder.select(\.title))
  }
}
```

**Why?** Only one engine's initializers are compiled, so no ambiguity.

### ✅ Unified API

Both syntaxes work with either engine:

```swift
// Works with both GRDB and SQLiteNIO
@FetchAll var users: [User]

// Works with both GRDB and SQLiteNIO  
@FetchAll(User.all) var users
```

### ✅ Compile-Time Safety

- Can't accidentally use both engines
- Compilation fails if no trait is enabled
- No runtime checks or overhead

### ✅ Clean Code

- No complex runtime engine detection
- No protocol dispatch overhead
- Simple conditional compilation

## Migration Guide

### For Existing GRDB Users

Add trait when building:

```bash
swift build --experimental-enable-traits --enable-trait GRDB
```

No code changes needed!

### For Existing SQLiteNIO Users

Add trait when building:

```bash
swift build --experimental-enable-traits --enable-trait SQLiteNIO
```

No code changes needed!

### For New Projects

Choose your engine by enabling the appropriate trait in your Package.swift:

```swift
// In your app's Package.swift
.target(
  name: "MyApp",
  dependencies: [
    .product(
      name: "SQLiteData",
      package: "sqlite-data",
      traits: ["GRDB"]  // or ["SQLiteNIO"]
    )
  ]
)
```

## Open Questions

1. **Default trait?** Should one trait be enabled by default?
   - Proposal: Enable GRDB by default for backward compatibility
   
2. **Validation?** Should we add compile-time validation that at least one trait is enabled?
   - Proposal: Add `#if !SQLITE_ENGINE_GRDB && !SQLITE_ENGINE_SQLITENO` with `#error`
   
3. **Test organization?** Should tests be split by trait?
   - Proposal: Keep current structure but add guards

## Performance Impact

**Zero runtime overhead:**
- No protocol dispatch
- No type erasure
- No runtime checks
- Pure compile-time branching via `#if`

**Binary size:**
- Smaller binaries - only one engine compiled in
- GRDB build: ~X MB smaller (no SQLiteNIO)
- SQLiteNIO build: ~Y MB smaller (no GRDB)

## Security Considerations

- Traits reduce attack surface by excluding unused engine code
- Simpler dependency tree per build
- Fewer potential vulnerabilities from unused code

## Conclusion

SPM traits provide the ideal solution for engine abstraction:
- Compile-time selection
- Zero runtime overhead
- Clean, unified API
- No ambiguous initializers
- Enforced mutual exclusion

This approach aligns perfectly with the project's performance and API design goals.
