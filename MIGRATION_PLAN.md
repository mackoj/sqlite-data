# GRDB to SQLiteNIO Migration Implementation Plan

## Overview
This document outlines the practical implementation plan for migrating sqlite-data from GRDB to SQLiteNIO, based on the comprehensive migration guide provided.

## Scope Assessment
The migration involves:
- ~20 source files directly depending on GRDB
- Core abstractions: DatabaseReader, DatabaseWriter, Database, ValueObservation
- Query execution and cursor infrastructure
- Change observation and notification system
- CloudKit synchronization integration (complex)

## Implementation Strategy

### Phase 1: Foundation Layer (Days 1-3)
**Goal**: Create SQLiteNIO abstractions that mimic GRDB's API surface

#### Files to Create:
1. `Sources/SQLiteData/SQLiteNIO/DatabaseProtocols.swift`
   - `DatabaseReader` protocol
   - `DatabaseWriter` protocol  
   - `Configuration` struct
   - `Database` wrapper class

2. `Sources/SQLiteData/SQLiteNIO/DatabaseQueue.swift`
   - Wraps `SQLiteConnection`
   - Implements `DatabaseWriter`
   - Provides async read/write methods
   - Thread-safety via actor or locks

3. `Sources/SQLiteData/SQLiteNIO/DatabasePool.swift`
   - Connection pooling for read/write separation
   - Similar to `DatabaseQueue` but with pool management

#### Files to Modify:
- `Package.swift`: Replace GRDB dependency with SQLiteNIO

### Phase 2: Query Execution (Days 4-6)  
**Goal**: Enable basic query execution with SQLiteNIO

#### Files to Create:
1. `Sources/SQLiteData/SQLiteNIO/SQLiteRowDecoder.swift`
   - Decodes `SQLiteRow` to `Decodable` types
   - Maps column names to property names
   - Handles type conversions

2. `Sources/SQLiteData/SQLiteNIO/QueryCursor.swift`
   - Async cursor over query results
   - Compatible with existing `QueryCursor<T>` API
   - Wraps SQLiteNIO's row iteration

#### Files to Modify:
- `Sources/SQLiteData/StructuredQueries+GRDB/Statement+GRDB.swift`
  - Rename to `Statement+SQLiteNIO.swift`
  - Replace GRDB `Database` with SQLiteNIO wrapper
  - Convert sync methods to async
  - Update `execute()`, `fetchAll()`, `fetchOne()`, `fetchCursor()`

### Phase 3: Change Observation (Days 7-10)
**Goal**: Implement database change observation using update hooks

#### Files to Create:
1. `Sources/SQLiteData/SQLiteNIO/SQLiteNIOObserver.swift`
   - Actor for thread-safe observation
   - Uses `sqlite3_update_hook` (from PR #90 or raw SQLite3)
   - Buffers changes to avoid excessive queries
   - Groups changes by table name
   - Integrates with Swift Sharing library

2. `Sources/SQLiteData/SQLiteNIO/UpdateHook.swift`
   - Wrapper around `sqlite3_update_hook`
   - Provides async callback mechanism
   - Handles hook lifecycle

#### Files to Modify:
- `Sources/SQLiteData/Internal/FetchKey.swift`
  - Update `subscribe()` to use `SQLiteNIOObserver`
  - Replace `ValueObservation` with custom observation
  - Maintain existing `SharedSubscription` API

### Phase 4: Property Wrappers (Days 11-12)
**Goal**: Ensure @FetchAll, @FetchOne, @Fetch work with new implementation

#### Files to Verify/Update:
- `Sources/SQLiteData/FetchAll.swift` - May need scheduler updates
- `Sources/SQLiteData/FetchOne.swift` - May need scheduler updates  
- `Sources/SQLiteData/Fetch.swift` - May need scheduler updates
- `Sources/SQLiteData/FetchKeyRequest.swift` - Should work as-is

### Phase 5: Dependency Integration (Days 13-14)
**Goal**: Update default database dependency

#### Files to Modify:
- `Sources/SQLiteData/StructuredQueries+GRDB/DefaultDatabase.swift`
  - Rename to `DefaultDatabase.swift` (remove GRDB reference)
  - Update `defaultDatabase()` to return SQLiteNIO connection
  - Handle in-memory databases for previews/tests
  - Update connection string handling

### Phase 6: Testing & Validation (Days 15-17)
**Goal**: Ensure tests pass and functionality works

#### Tasks:
1. Update test infrastructure
   - Fix CloudKit test imports (conditional compilation)
   - Update test helpers for async APIs
   - Create SQLiteNIO test utilities

2. Run existing tests
   - Fix failures incrementally
   - Document breaking changes

3. Linux verification
   - Build on Linux
   - Run tests on Linux
   - Verify no platform-specific issues

### Phase 7: CloudKit Integration (Days 18-21)
**Goal**: Migrate CloudKit sync layer (complex, may defer)

#### Decision Point:
CloudKit integration is complex and may not be needed for initial Linux support.

#### Options:
A. **Full Migration**: Update all CloudKit code to use SQLiteNIO
   - ~15 files in `Sources/SQLiteData/CloudKit/`
   - Requires understanding CloudKit sync semantics
   - Significant testing required

B. **Defer with Feature Flag**: Keep CloudKit iOS/macOS only
   - Use conditional compilation
   - Document as known limitation
   - Plan future migration

C. **Hybrid Approach**: CloudKit uses compatibility wrapper
   - Create GRDB-compatible wrapper around SQLiteNIO
   - Allows CloudKit code to remain mostly unchanged
   - Best for gradual migration

**Recommendation**: Option B (defer) initially, then Option C

## Technical Considerations

### 1. Async/Await Transition
- GRDB uses synchronous APIs with dispatch queues
- SQLiteNIO uses async/await with NIO EventLoop
- Need to bridge these paradigms carefully

### 2. Scheduler Compatibility
- GRDB has `ValueObservationScheduler`
- SQLiteNIO has EventLoop-based scheduling
- May need custom scheduler adapter

### 3. Error Handling
- Different error types between libraries
- Need consistent error reporting
- Preserve existing error semantics where possible

### 4. Performance
- GRDB is highly optimized
- SQLiteNIO may have different performance characteristics
- Need benchmarking after migration
- May need statement caching

### 5. Transaction Semantics
- GRDB has sophisticated transaction handling
- SQLiteNIO may be simpler
- Ensure ACID properties preserved

## Breaking Changes

### API Changes:
1. Some synchronous methods become async
2. `DatabaseReader`/`DatabaseWriter` protocols change
3. Scheduler API may change
4. CloudKit integration may be iOS/macOS only initially

### Mitigation:
- Use `@available` annotations
- Provide migration guide
- Keep high-level APIs stable (@FetchAll, etc.)

## Success Criteria

### Minimum Viable Migration:
- [x] Package builds on macOS
- [x] Package builds on Linux
- [x] Basic queries work (@FetchAll, @FetchOne)
- [x] Change observation works
- [x] Tests pass (non-CloudKit)
- [x] Property wrappers work in SwiftUI

### Full Migration:
- [ ] All tests pass
- [ ] CloudKit integration works
- [ ] Performance comparable to GRDB
- [ ] Documentation updated
- [ ] Example apps work

## Risk Assessment

### High Risk:
- CloudKit integration complexity
- Performance degradation
- Hidden GRDB dependencies

### Medium Risk:
- Async/await transition bugs
- Threading issues
- Edge cases in observation

### Low Risk:
- Package dependency issues
- Build configuration
- Documentation gaps

## Timeline

### Aggressive (3 weeks):
- Week 1: Phases 1-2
- Week 2: Phases 3-5
- Week 3: Phase 6, skip Phase 7

### Realistic (6 weeks):
- Weeks 1-2: Phases 1-2
- Weeks 3-4: Phases 3-5
- Weeks 5-6: Phases 6-7

### Conservative (10 weeks):
- Weeks 1-3: Phases 1-2 (with testing)
- Weeks 4-6: Phases 3-5 (with testing)
- Weeks 7-9: Phase 6 (comprehensive testing)
- Week 10: Phase 7 (if needed)

## Next Steps

1. Review and approve this plan
2. Set up development branch
3. Start with Phase 1 implementation
4. Regular check-ins after each phase
5. Adjust plan based on learnings

## Notes

- This migration touches core infrastructure
- High test coverage crucial
- Consider feature freeze during migration
- Budget time for unexpected issues
- Linux CI setup needed early
