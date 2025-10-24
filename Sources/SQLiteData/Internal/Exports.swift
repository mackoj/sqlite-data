@_exported import Dependencies
@_exported import StructuredQueriesSQLite

// Compile-time validation that at least one engine trait is enabled
#if !SQLITE_ENGINE_GRDB && !SQLITE_ENGINE_SQLITENIO
#error("At least one SQLite engine trait must be enabled. Use --traits GRDB or --traits SQLiteNIO when building.")
#endif

#if SQLITE_ENGINE_GRDB
@_exported import struct GRDB.Configuration
@_exported import class GRDB.Database
@_exported import struct GRDB.DatabaseError
@_exported import struct GRDB.DatabaseMigrator
@_exported import class GRDB.DatabasePool
@_exported import class GRDB.DatabaseQueue
@_exported import protocol GRDB.DatabaseReader
@_exported import protocol GRDB.DatabaseWriter
@_exported import protocol GRDB.ValueObservationScheduler
#endif
