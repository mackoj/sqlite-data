# CloudKit SQLiteNIO Implementation Plan

## Status: 🚧 In Progress

## Overview
Implement CloudKit synchronization support for SQLiteNIO engine, making it available alongside the existing GRDB implementation.

## Challenges

CloudKit integration requires several GRDB-specific features that don't have direct SQLiteNIO equivalents:

1. **DatabaseMigrator** - Schema version management
2. **Custom SQL Functions** - Runtime function registration  
3. **Triggers** - Database triggers for change tracking
4. **ATTACH DATABASE** - Multiple database management
5. **ValueObservation** - ✅ Already abstracted via FetchKey
6. **DatabaseWriter/Reader protocols** - Read/write separation

## Implementation Approach

### Phase 1: Database Abstractions ✅
Create abstraction layer that works with both engines:

- `CloudKitDatabaseWriter` protocol - Write operations
- `CloudKitDatabaseReader` protocol - Read operations  
- `CloudKitDatabase` protocol - Database connection wrapper

Engine-specific implementations:
- `Traits/GRDB/CloudKit/CloudKitDatabase+GRDB.swift` - Wraps GRDB's `DatabaseWriter`
- `Traits/SQLiteNIO/CloudKit/CloudKitDatabase+SQLiteNIO.swift` - Wraps `SQLiteConnection`

### Phase 2: Custom Functions
GRDB: Uses `db.add(function:)` API
SQLiteNIO: Need to use SQLite3 C API (`sqlite3_create_function_v2`)

Implementation:
- Create `CustomFunctionRegistry` abstraction
- GRDB version delegates to GRDB's built-in support
- SQLiteNIO version uses C API directly

### Phase 3: Database Migrations
GRDB: Uses `DatabaseMigrator` with versioning
SQLiteNIO: Need custom implementation

Implementation:
- Create `CloudKitMigrator` abstraction
- GRDB version wraps `DatabaseMigrator`
- SQLiteNIO version implements manual version tracking table

### Phase 4: Triggers
GRDB: Standard SQL CREATE TRIGGER statements
SQLiteNIO: Same SQL but need proper execution context

Implementation:
- Both engines can use same SQL for triggers
- Need to ensure proper transaction handling

### Phase 5: Metadata Database
GRDB: Uses ATTACH DATABASE and separate `DatabasePool`
SQLiteNIO: Need separate `SQLiteConnection` instance

Implementation:
- Abstract metadata database access
- GRDB uses attached database approach
- SQLiteNIO uses separate connection with manual attachment

## Estimated Effort

- **Phase 1 (Abstractions)**: 2-3 days
- **Phase 2 (Custom Functions)**: 2-3 days
- **Phase 3 (Migrations)**: 3-4 days
- **Phase 4 (Triggers)**: 1-2 days  
- **Phase 5 (Metadata DB)**: 2-3 days
- **Testing & Integration**: 3-5 days

**Total**: 13-20 days of focused development

## Alternative: Staged Approach

Given the complexity, consider a staged rollout:

### Stage 1: Infrastructure Only
- Update guards to allow compilation with both engines
- Provide clear "unsupported" errors when using SQLiteNIO
- Document CloudKit as GRDB-only for now
- **Benefit**: Maintains build system consistency

### Stage 2: Basic SQLiteNIO Support  
- Implement core database abstractions
- Support basic sync operations
- Limited to simple schemas without complex triggers

### Stage 3: Full Feature Parity
- Complete all advanced features
- Full test coverage
- Production ready

## Recommendation

Given the scope, I recommend **Stage 1** for this PR:
1. Update compilation guards for consistency
2. Add clear runtime errors/warnings when CloudKit used with SQLiteNIO
3. Document the limitation explicitly
4. Create this implementation plan for future work

This provides value immediately while setting up for future implementation.

## Files Affected

- All 34 files in `Sources/SQLiteData/CloudKit/`
- All CloudKit test files
- `ENGINE_SWITCHING_GUIDE.md` - Update CloudKit status
- `Package.swift` - Potentially add conditional CloudKit availability

## Next Steps

1. Update CloudKit guards to be more explicit about requirements
2. Add compile-time warnings/documentation  
3. Create abstraction interfaces (protocols)
4. Implement GRDB versions (extract from current code)
5. Implement SQLiteNIO versions (new code)
6. Update tests to work with both engines
7. Update documentation
