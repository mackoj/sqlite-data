#if SQLITE_ENGINE_SQLITENO
import Foundation
import SQLiteData
import SQLiteNIO
import Testing

@Suite struct SQLiteNIOObserverTests {
  
  func createTestConnection() async throws -> SQLiteConnection {
    let connection = try await SQLiteConnection.open(storage: .memory)
    
    // Create test table
    try await connection.query("""
      CREATE TABLE users (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        email TEXT NOT NULL
      )
      """, [])
    
    return connection
  }
  
  @Test func observerReceivesInsertNotification() async throws {
    let connection = try await createTestConnection()
    let observer = SQLiteNIOObserver(connection: connection)
    
    var receivedChange: SQLiteNIOObserver.Change?
    let changeReceived = Confirmation("Observer receives insert notification", expectedCount: 1)
    
    // Subscribe to changes
    let subscription = try await observer.subscribe(tables: ["users"]) { change in
      receivedChange = change
      changeReceived.confirm()
    }
    
    // Insert a row
    try await connection.query(
      "INSERT INTO users (name, email) VALUES (?, ?)",
      [.text("Alice"), .text("alice@example.com")]
    )
    
    // Wait for notification
    await confirmation("Insert notification received", expectedCount: 1) { confirmation in
      try? await Task.sleep(nanoseconds: 100_000_000) // 100ms
      if receivedChange != nil {
        confirmation()
      }
    }
    
    // Verify the change
    #expect(receivedChange != nil)
    #expect(receivedChange?.tableName == "users")
    #expect(receivedChange?.type == .insert)
    #expect((receivedChange?.rowID ?? 0) > 0)
    
    subscription.cancel()
    try await connection.close()
  }
  
  @Test func observerReceivesUpdateNotification() async throws {
    let connection = try await createTestConnection()
    let observer = SQLiteNIOObserver(connection: connection)
    
    // Insert initial data
    try await connection.query(
      "INSERT INTO users (name, email) VALUES (?, ?)",
      [.text("Bob"), .text("bob@example.com")]
    )
    
    var receivedChange: SQLiteNIOObserver.Change?
    
    // Subscribe to changes
    let subscription = try await observer.subscribe(tables: ["users"]) { change in
      if change.type == .update {
        receivedChange = change
      }
    }
    
    // Update the row
    try await connection.query(
      "UPDATE users SET name = ? WHERE name = ?",
      [.text("Robert"), .text("Bob")]
    )
    
    // Wait for notification
    try await Task.sleep(nanoseconds: 100_000_000) // 100ms
    
    // Verify the change
    #expect(receivedChange != nil)
    #expect(receivedChange?.tableName == "users")
    #expect(receivedChange?.type == .update)
    
    subscription.cancel()
    try await connection.close()
  }
  
  @Test func observerReceivesDeleteNotification() async throws {
    let connection = try await createTestConnection()
    let observer = SQLiteNIOObserver(connection: connection)
    
    // Insert initial data
    try await connection.query(
      "INSERT INTO users (name, email) VALUES (?, ?)",
      [.text("Charlie"), .text("charlie@example.com")]
    )
    
    var receivedChange: SQLiteNIOObserver.Change?
    
    // Subscribe to changes
    let subscription = try await observer.subscribe(tables: ["users"]) { change in
      if change.type == .delete {
        receivedChange = change
      }
    }
    
    // Delete the row
    try await connection.query(
      "DELETE FROM users WHERE name = ?",
      [.text("Charlie")]
    )
    
    // Wait for notification
    try await Task.sleep(nanoseconds: 100_000_000) // 100ms
    
    // Verify the change
    #expect(receivedChange != nil)
    #expect(receivedChange?.tableName == "users")
    #expect(receivedChange?.type == .delete)
    
    subscription.cancel()
    try await connection.close()
  }
  
  @Test func observerFiltersTableChanges() async throws {
    let connection = try await createTestConnection()
    let observer = SQLiteNIOObserver(connection: connection)
    
    // Create another table
    try await connection.query("""
      CREATE TABLE posts (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        title TEXT NOT NULL
      )
      """, [])
    
    var receivedChanges: [SQLiteNIOObserver.Change] = []
    
    // Subscribe only to users table
    let subscription = try await observer.subscribe(tables: ["users"]) { change in
      receivedChanges.append(change)
    }
    
    // Insert into posts (should not trigger)
    try await connection.query(
      "INSERT INTO posts (title) VALUES (?)",
      [.text("First Post")]
    )
    
    // Wait a bit to ensure no notification
    try await Task.sleep(nanoseconds: 100_000_000) // 100ms
    
    // Insert into users (should trigger)
    try await connection.query(
      "INSERT INTO users (name, email) VALUES (?, ?)",
      [.text("Dave"), .text("dave@example.com")]
    )
    
    // Wait for notification
    try await Task.sleep(nanoseconds: 100_000_000) // 100ms
    
    // Verify we only got the users table change
    #expect(receivedChanges.count == 1)
    #expect(receivedChanges.first?.tableName == "users")
    
    subscription.cancel()
    try await connection.close()
  }
  
  @Test func multipleSubscribers() async throws {
    let connection = try await createTestConnection()
    let observer = SQLiteNIOObserver(connection: connection)
    
    var subscriber1Notified = false
    var subscriber2Notified = false
    
    // Subscribe first
    let subscription1 = try await observer.subscribe(tables: ["users"]) { _ in
      subscriber1Notified = true
    }
    
    // Subscribe second
    let subscription2 = try await observer.subscribe(tables: ["users"]) { _ in
      subscriber2Notified = true
    }
    
    // Insert a row - both should be notified
    try await connection.query(
      "INSERT INTO users (name, email) VALUES (?, ?)",
      [.text("Eve"), .text("eve@example.com")]
    )
    
    // Wait for notifications
    try await Task.sleep(nanoseconds: 100_000_000) // 100ms
    
    #expect(subscriber1Notified)
    #expect(subscriber2Notified)
    
    subscription1.cancel()
    subscription2.cancel()
    try await connection.close()
  }
  
  @Test func subscriptionCancellation() async throws {
    let connection = try await createTestConnection()
    let observer = SQLiteNIOObserver(connection: connection)
    
    var notificationCount = 0
    
    // Subscribe
    let subscription = try await observer.subscribe(tables: ["users"]) { _ in
      notificationCount += 1
    }
    
    // Insert first row - should trigger
    try await connection.query(
      "INSERT INTO users (name, email) VALUES (?, ?)",
      [.text("Frank"), .text("frank@example.com")]
    )
    
    // Wait for notification
    try await Task.sleep(nanoseconds: 100_000_000) // 100ms
    
    // Cancel subscription
    subscription.cancel()
    
    // Insert second row - should not trigger
    try await connection.query(
      "INSERT INTO users (name, email) VALUES (?, ?)",
      [.text("Grace"), .text("grace@example.com")]
    )
    
    // Wait a bit to ensure no additional notification
    try await Task.sleep(nanoseconds: 100_000_000) // 100ms
    
    // Verify we only got one notification
    #expect(notificationCount == 1)
    
    try await connection.close()
  }
}

#endif
