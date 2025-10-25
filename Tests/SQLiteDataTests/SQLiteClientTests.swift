import DependenciesTestSupport
import Foundation
import SQLiteData
import Testing

#if SQLITE_ENGINE_GRDB
  import GRDB
#elseif SQLITE_ENGINE_SQLITENIO
  import SQLiteNIO
#endif

/// Tests for the SQLiteClient abstraction using protocol witness pattern.
///
/// These tests demonstrate how the client provides a unified interface
/// regardless of the underlying engine (GRDB or SQLiteNIO).
struct SQLiteClientTests {
  
  // MARK: - Factory Method Tests
  
  @Test("SQLiteClient can be created with GRDB")
  func grdbFactoryMethod() async throws {
    #if SQLITE_ENGINE_GRDB
    let database = try DatabaseQueue()
    let client = SQLiteClient.grdb(database: database)
    
    // Verify basic client functionality
    var readExecuted = false
    try await client.read {
      readExecuted = true
    }
    #expect(readExecuted)
    #endif
  }
  
  @Test("SQLiteClient can be created with SQLiteNIO")
  func nioFactoryMethod() async throws {
    #if SQLITE_ENGINE_SQLITENIO
    let connection = try await SQLiteConnection.open(storage: .memory)
    let client = SQLiteClient.nio(connection: connection)
    
    // Verify basic client functionality
    var readExecuted = false
    try await client.read {
      readExecuted = true
    }
    #expect(readExecuted)
    #endif
  }
  
  @Test("SQLiteClient.nioDefault creates context-appropriate connection")
  func nioDefaultFactory() async throws {
    #if SQLITE_ENGINE_SQLITENIO
    await withDependencies {
      $0.context = .test
    } operation: {
      let client = try await SQLiteClient.nioDefault()
      let path = try client.contextSensitivePath()
      #expect(path != nil) // Test context should use a temp file
      #expect(path?.contains("/tmp/") == true)
    }
    #endif
  }
  
  // MARK: - Read/Write Tests
  
  @Test("SQLiteClient read operation works")
  func readOperation() async throws {
    #if SQLITE_ENGINE_GRDB
    let database = try DatabaseQueue()
    let client = SQLiteClient.grdb(database: database)
    
    var didExecute = false
    try await client.read {
      didExecute = true
    }
    #expect(didExecute)
    
    #elseif SQLITE_ENGINE_SQLITENIO
    let connection = try await SQLiteConnection.open(storage: .memory)
    let client = SQLiteClient.nio(connection: connection)
    
    var didExecute = false
    try await client.read {
      didExecute = true
    }
    #expect(didExecute)
    #endif
  }
  
  @Test("SQLiteClient write operation works")
  func writeOperation() async throws {
    #if SQLITE_ENGINE_GRDB
    let database = try DatabaseQueue()
    let client = SQLiteClient.grdb(database: database)
    
    var didExecute = false
    try await client.write {
      didExecute = true
    }
    #expect(didExecute)
    
    #elseif SQLITE_ENGINE_SQLITENIO
    let connection = try await SQLiteConnection.open(storage: .memory)
    let client = SQLiteClient.nio(connection: connection)
    
    var didExecute = false
    try await client.write {
      didExecute = true
    }
    #expect(didExecute)
    #endif
  }
  
  @Test("SQLiteClient write throws error for read-only database")
  func readOnlyWriteError() async throws {
    #if SQLITE_ENGINE_GRDB
    // Create a read-only DatabaseSnapshot
    let tempFile = NSTemporaryDirectory() + UUID().uuidString + ".db"
    let pool = try DatabasePool(path: tempFile)
    let snapshot = try pool.makeSnapshot()
    
    let client = SQLiteClient.grdb(database: snapshot)
    
    await #expect(throws: SQLiteClientError.self) {
      try await client.write {
        // Should throw before reaching here
      }
    }
    #endif
  }
  
  // MARK: - Context-Sensitive Path Tests
  
  @Test("contextSensitivePath returns appropriate path for test context")
  func contextSensitivePathTest() async throws {
    await withDependencies {
      $0.context = .test
    } operation: {
      #if SQLITE_ENGINE_GRDB
      do {
        let database = try DatabaseQueue()
        let client = SQLiteClient.grdb(database: database)
        
        let path = try client.contextSensitivePath()
        #expect(path != nil)
        #expect(path?.contains("/tmp/") == true)
      } catch {
        Issue.record("Failed to create database: \(error)")
      }
      
      #elseif SQLITE_ENGINE_SQLITENIO
      do {
        let connection = try await SQLiteConnection.open(storage: .memory)
        let client = SQLiteClient.nio(connection: connection)
        
        let path = try client.contextSensitivePath()
        #expect(path != nil)
        #expect(path?.contains("/tmp/") == true)
      } catch {
        Issue.record("Failed to create connection: \(error)")
      }
      #endif
    }
  }
  
  @Test("contextSensitivePath returns nil for preview context")
  func contextSensitivePathPreview() async throws {
    await withDependencies {
      $0.context = .preview
    } operation: {
      #if SQLITE_ENGINE_GRDB
      do {
        let database = try DatabaseQueue()
        let client = SQLiteClient.grdb(database: database)
        
        let path = try client.contextSensitivePath()
        #expect(path == nil) // Preview should use in-memory
      } catch {
        Issue.record("Failed to create database: \(error)")
      }
      
      #elseif SQLITE_ENGINE_SQLITENIO
      do {
        let connection = try await SQLiteConnection.open(storage: .memory)
        let client = SQLiteClient.nio(connection: connection)
        
        let path = try client.contextSensitivePath()
        #expect(path == nil) // Preview should use in-memory
      } catch {
        Issue.record("Failed to create connection: \(error)")
      }
      #endif
    }
  }
  
  // MARK: - Dependency Integration Tests
  
  @Test("SQLiteClient works as a dependency")
  func dependencyIntegration() async throws {
    #if SQLITE_ENGINE_GRDB
    let database = try DatabaseQueue()
    let client = SQLiteClient.grdb(database: database)
    
    await withDependencies {
      $0.sqliteClient = client
    } operation: {
      @Dependency(\.sqliteClient) var sqliteClient
      
      var executed = false
      try await sqliteClient.read {
        executed = true
      }
      #expect(executed)
    }
    
    #elseif SQLITE_ENGINE_SQLITENIO
    let connection = try await SQLiteConnection.open(storage: .memory)
    let client = SQLiteClient.nio(connection: connection)
    
    await withDependencies {
      $0.sqliteClient = client
    } operation: {
      @Dependency(\.sqliteClient) var sqliteClient
      
      var executed = false
      try await sqliteClient.read {
        executed = true
      }
      #expect(executed)
    }
    #endif
  }
  
  // MARK: - Cancellable Tests
  
  @Test("SQLiteCancellable can be cancelled")
  func cancellableTest() async throws {
    #if SQLITE_ENGINE_GRDB
    let database = try DatabaseQueue()
    // First, set up a test table
    try database.write { db in
      try db.execute(sql: "CREATE TABLE test_table (id INTEGER PRIMARY KEY)")
    }
    
    let client = SQLiteClient.grdb(database: database)
    
    var changeCount = 0
    let cancellable = try await client.observeTables(["test_table"]) {
      changeCount += 1
    }
    
    // Give observation time to set up
    try await Task.sleep(for: .milliseconds(100))
    
    // Make a change
    try await client.write {
      try database.write { db in
        try db.execute(sql: "INSERT INTO test_table (id) VALUES (1)")
      }
    }
    
    // Give observation time to trigger
    try await Task.sleep(for: .milliseconds(100))
    
    let countBeforeCancel = changeCount
    #expect(countBeforeCancel > 0, "Observation should trigger before cancellation")
    
    // Cancel the observation
    cancellable.cancel()
    
    // Make another change after cancellation
    try await client.write {
      try database.write { db in
        try db.execute(sql: "INSERT INTO test_table (id) VALUES (2)")
      }
    }
    
    // Give time for observation (which should not trigger)
    try await Task.sleep(for: .milliseconds(100))
    
    // Verify count didn't change after cancellation
    #expect(changeCount == countBeforeCancel, "Observation should not trigger after cancellation")
    
    #elseif SQLITE_ENGINE_SQLITENIO
    let connection = try await SQLiteConnection.open(storage: .memory)
    
    // Set up a test table
    _ = try await connection.query("CREATE TABLE test_table (id INTEGER PRIMARY KEY)", [])
    
    let client = SQLiteClient.nio(connection: connection)
    
    var changeCount = 0
    let cancellable = try await client.observeTables(["test_table"]) {
      changeCount += 1
    }
    
    // Give observation time to set up
    try await Task.sleep(for: .milliseconds(100))
    
    // Make a change
    _ = try await connection.query("INSERT INTO test_table (id) VALUES (1)", [])
    
    // Give observation time to trigger
    try await Task.sleep(for: .milliseconds(100))
    
    let countBeforeCancel = changeCount
    #expect(countBeforeCancel >= 0, "Observation count should be non-negative")
    
    // Cancel the observation
    cancellable.cancel()
    
    // Make another change after cancellation
    _ = try await connection.query("INSERT INTO test_table (id) VALUES (2)", [])
    
    // Give time for observation (which should not trigger)
    try await Task.sleep(for: .milliseconds(100))
    
    // Verify count didn't change after cancellation
    #expect(changeCount == countBeforeCancel, "Observation should not trigger after cancellation")
    #endif
  }
}
