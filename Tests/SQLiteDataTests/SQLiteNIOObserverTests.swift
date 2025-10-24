import XCTest

#if canImport(SQLiteNIO)
import NIOCore
import NIOPosix
import SQLiteNIO
@testable import SQLiteData

final class SQLiteNIOObserverTests: XCTestCase {
  
  var threadPool: NIOThreadPool!
  var eventLoopGroup: EventLoopGroup!
  var connection: SQLiteConnection!
  
  override func setUp() async throws {
    try await super.setUp()
    
    // Setup NIO infrastructure
    threadPool = NIOThreadPool(numberOfThreads: 1)
    threadPool.start()
    eventLoopGroup = MultiThreadedEventLoopGroup(numberOfThreads: 1)
    
    // Create in-memory database
    connection = try await SQLiteConnection.open(
      storage: .memory,
      threadPool: threadPool,
      on: eventLoopGroup.any()
    ).get()
    
    // Create test table
    try await connection.query("""
      CREATE TABLE users (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        email TEXT NOT NULL
      )
    """, [])
  }
  
  override func tearDown() async throws {
    try await connection.close()
    try await eventLoopGroup.shutdownGracefully()
    try threadPool.syncShutdownGracefully()
    try await super.tearDown()
  }
  
  func testObserverReceivesInsertNotification() async throws {
    let observer = SQLiteNIOObserver(connection: connection)
    
    let expectation = XCTestExpectation(description: "Observer receives insert notification")
    var receivedChange: SQLiteNIOObserver.Change?
    
    // Subscribe to changes
    let subscription = try await observer.subscribe(tables: ["users"]) { change in
      receivedChange = change
      expectation.fulfill()
    }
    
    // Insert a row
    try await connection.query(
      "INSERT INTO users (name, email) VALUES (?, ?)",
      [.text("Alice"), .text("alice@example.com")]
    )
    
    // Wait for notification
    await fulfillment(of: [expectation], timeout: 2.0)
    
    // Verify the change
    XCTAssertNotNil(receivedChange)
    XCTAssertEqual(receivedChange?.tableName, "users")
    XCTAssertEqual(receivedChange?.type, .insert)
    XCTAssertTrue(receivedChange?.rowID ?? 0 > 0)
    
    subscription.cancel()
  }
  
  func testObserverReceivesUpdateNotification() async throws {
    let observer = SQLiteNIOObserver(connection: connection)
    
    // Insert initial data
    try await connection.query(
      "INSERT INTO users (name, email) VALUES (?, ?)",
      [.text("Bob"), .text("bob@example.com")]
    )
    
    let expectation = XCTestExpectation(description: "Observer receives update notification")
    var receivedChange: SQLiteNIOObserver.Change?
    
    // Subscribe to changes
    let subscription = try await observer.subscribe(tables: ["users"]) { change in
      if change.type == .update {
        receivedChange = change
        expectation.fulfill()
      }
    }
    
    // Update the row
    try await connection.query(
      "UPDATE users SET name = ? WHERE name = ?",
      [.text("Robert"), .text("Bob")]
    )
    
    // Wait for notification
    await fulfillment(of: [expectation], timeout: 2.0)
    
    // Verify the change
    XCTAssertNotNil(receivedChange)
    XCTAssertEqual(receivedChange?.tableName, "users")
    XCTAssertEqual(receivedChange?.type, .update)
    
    subscription.cancel()
  }
  
  func testObserverReceivesDeleteNotification() async throws {
    let observer = SQLiteNIOObserver(connection: connection)
    
    // Insert initial data
    try await connection.query(
      "INSERT INTO users (name, email) VALUES (?, ?)",
      [.text("Charlie"), .text("charlie@example.com")]
    )
    
    let expectation = XCTestExpectation(description: "Observer receives delete notification")
    var receivedChange: SQLiteNIOObserver.Change?
    
    // Subscribe to changes
    let subscription = try await observer.subscribe(tables: ["users"]) { change in
      if change.type == .delete {
        receivedChange = change
        expectation.fulfill()
      }
    }
    
    // Delete the row
    try await connection.query(
      "DELETE FROM users WHERE name = ?",
      [.text("Charlie")]
    )
    
    // Wait for notification
    await fulfillment(of: [expectation], timeout: 2.0)
    
    // Verify the change
    XCTAssertNotNil(receivedChange)
    XCTAssertEqual(receivedChange?.tableName, "users")
    XCTAssertEqual(receivedChange?.type, .delete)
    
    subscription.cancel()
  }
  
  func testObserverFiltersTableChanges() async throws {
    let observer = SQLiteNIOObserver(connection: connection)
    
    // Create another table
    try await connection.query("""
      CREATE TABLE posts (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        title TEXT NOT NULL
      )
    """, [])
    
    let expectation = XCTestExpectation(description: "Observer receives only users table changes")
    expectation.expectedFulfillmentCount = 1
    var receivedChanges: [SQLiteNIOObserver.Change] = []
    
    // Subscribe only to users table
    let subscription = try await observer.subscribe(tables: ["users"]) { change in
      receivedChanges.append(change)
      expectation.fulfill()
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
    await fulfillment(of: [expectation], timeout: 2.0)
    
    // Verify we only got the users table change
    XCTAssertEqual(receivedChanges.count, 1)
    XCTAssertEqual(receivedChanges.first?.tableName, "users")
    
    subscription.cancel()
  }
  
  func testMultipleSubscribers() async throws {
    let observer = SQLiteNIOObserver(connection: connection)
    
    let expectation1 = XCTestExpectation(description: "First subscriber receives notification")
    let expectation2 = XCTestExpectation(description: "Second subscriber receives notification")
    
    // Subscribe first
    let subscription1 = try await observer.subscribe(tables: ["users"]) { _ in
      expectation1.fulfill()
    }
    
    // Subscribe second
    let subscription2 = try await observer.subscribe(tables: ["users"]) { _ in
      expectation2.fulfill()
    }
    
    // Insert a row - both should be notified
    try await connection.query(
      "INSERT INTO users (name, email) VALUES (?, ?)",
      [.text("Eve"), .text("eve@example.com")]
    )
    
    // Wait for both notifications
    await fulfillment(of: [expectation1, expectation2], timeout: 2.0)
    
    subscription1.cancel()
    subscription2.cancel()
  }
  
  func testSubscriptionCancellation() async throws {
    let observer = SQLiteNIOObserver(connection: connection)
    
    let expectation = XCTestExpectation(description: "Observer receives notification before cancellation")
    expectation.expectedFulfillmentCount = 1
    expectation.assertForOverFulfill = true
    
    var notificationCount = 0
    
    // Subscribe
    let subscription = try await observer.subscribe(tables: ["users"]) { _ in
      notificationCount += 1
      expectation.fulfill()
    }
    
    // Insert first row - should trigger
    try await connection.query(
      "INSERT INTO users (name, email) VALUES (?, ?)",
      [.text("Frank"), .text("frank@example.com")]
    )
    
    // Wait for notification
    await fulfillment(of: [expectation], timeout: 2.0)
    
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
    XCTAssertEqual(notificationCount, 1)
  }
}

#endif
