# Phase 4: Direct @FetchAll/@FetchOne Integration - Complete Guide

## Overview

Phase 4 enables direct use of @FetchAll and @FetchOne property wrappers with SQLiteNIO connections, providing the same convenient API you're used to with GRDB, but with SQLiteNIO's cross-platform benefits.

## Status: ✅ COMPLETE

## What's New

You can now use @FetchAll and @FetchOne directly with SQLiteConnection:

```swift
// Before Phase 4 (using @SharedReader)
@SharedReader(.fetchNIO(AllUsersRequest(), connection: connection))
var users: [User] = []

// After Phase 4 (using @FetchAll directly)
@FetchAll(User.all, connection: connection) var users
```

## Basic Usage

### @FetchAll with SQLiteConnection

```swift
import SQLiteNIO
import SwiftUI

struct User: Codable, Hashable, Sendable {
  let id: Int
  let name: String
  let email: String
}

struct ContentView: View {
  let connection: SQLiteConnection
  
  // Fetch all users
  @FetchAll(User.all, connection: connection) var users
  
  var body: some View {
    List(users, id: \.id) { user in
      VStack(alignment: .leading) {
        Text(user.name).font(.headline)
        Text(user.email).font(.caption)
      }
    }
  }
}
```

### @FetchOne with SQLiteConnection

```swift
struct DashboardView: View {
  let connection: SQLiteConnection
  
  // Fetch single values
  @FetchOne(User.count, connection: connection) var userCount = 0
  @FetchOne(Post.count, connection: connection) var postCount = 0
  
  var body: some View {
    VStack {
      Text("Users: \(userCount)")
      Text("Posts: \(postCount)")
    }
  }
}
```

## Advanced Examples

### Filtered Queries

```swift
struct ActiveUsersView: View {
  let connection: SQLiteConnection
  
  @FetchAll(
    User.where { $0.active == true }.order(by: \.name),
    connection: connection
  ) var activeUsers
  
  var body: some View {
    List(activeUsers, id: \.id) { user in
      Text(user.name)
    }
  }
}
```

### Optional Values

```swift
struct UserDetailView: View {
  let connection: SQLiteConnection
  let userId: Int
  
  @FetchOne(
    User.where { $0.id == userId }.limit(1),
    connection: connection
  ) var user: User?
  
  var body: some View {
    if let user = user {
      VStack {
        Text(user.name).font(.title)
        Text(user.email)
      }
    } else {
      Text("User not found")
    }
  }
}
```

### Complex Queries

```swift
struct StatisticsView: View {
  let connection: SQLiteConnection
  
  @FetchOne(
    User.where { $0.active == true }.count,
    connection: connection
  ) var activeUserCount = 0
  
  @FetchOne(
    Post.where { $0.publishedAt != nil }.count,
    connection: connection
  ) var publishedPostCount = 0
  
  @FetchAll(
    User.order(by: \.createdAt, .descending).limit(10),
    connection: connection
  ) var recentUsers
  
  var body: some View {
    VStack(spacing: 20) {
      Text("Active Users: \(activeUserCount)")
      Text("Published Posts: \(publishedPostCount)")
      
      Section("Recent Users") {
        ForEach(recentUsers, id: \.id) { user in
          Text(user.name)
        }
      }
    }
  }
}
```

## Reactive Updates

The property wrappers automatically update when the database changes:

```swift
struct UserManagementView: View {
  let connection: SQLiteConnection
  
  @FetchAll(User.all, connection: connection) var users
  @State private var newName = ""
  
  var body: some View {
    VStack {
      // User list automatically updates when data changes
      List(users, id: \.id) { user in
        Text(user.name)
      }
      
      // Add new user
      HStack {
        TextField("Name", text: $newName)
        Button("Add") {
          addUser()
        }
      }
    }
  }
  
  func addUser() {
    Task {
      try await connection.transaction { conn in
        try await conn.query(
          "INSERT INTO users (name) VALUES (?)",
          [.text(newName)]
        )
      }
      // @FetchAll automatically updates the UI!
      await MainActor.run {
        newName = ""
      }
    }
  }
}
```

## Complete Example App

Here's a full app showing Phase 4 features:

```swift
import SwiftUI
import SQLiteNIO
import NIOPosix
import NIOCore

// MARK: - Model

struct User: Codable, Hashable, Sendable {
  let id: Int
  let name: String
  let email: String
  let active: Bool
}

// MARK: - App

@main
struct MyApp: App {
  let connection: SQLiteConnection
  let threadPool: NIOThreadPool
  let eventLoopGroup: EventLoopGroup
  
  init() {
    // Setup NIO infrastructure
    threadPool = NIOThreadPool(numberOfThreads: 2)
    threadPool.start()
    eventLoopGroup = MultiThreadedEventLoopGroup(numberOfThreads: 2)
    
    // Open database
    connection = try! SQLiteConnection.open(
      storage: .file(path: "users.db"),
      threadPool: threadPool,
      on: eventLoopGroup.any()
    ).wait()
    
    // Create table
    Task {
      try await connection.query("""
        CREATE TABLE IF NOT EXISTS users (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          name TEXT NOT NULL,
          email TEXT NOT NULL UNIQUE,
          active INTEGER NOT NULL DEFAULT 1
        )
      """, [])
    }
  }
  
  var body: some Scene {
    WindowGroup {
      ContentView(connection: connection)
    }
  }
}

// MARK: - Main View

struct ContentView: View {
  let connection: SQLiteConnection
  
  var body: some View {
    TabView {
      UsersListView(connection: connection)
        .tabItem {
          Label("Users", systemImage: "person.2")
        }
      
      StatisticsView(connection: connection)
        .tabItem {
          Label("Stats", systemImage: "chart.bar")
        }
    }
  }
}

// MARK: - Users List

struct UsersListView: View {
  let connection: SQLiteConnection
  
  // Fetch all users - automatically updates!
  @FetchAll(User.order(by: \.name), connection: connection) var users
  
  @State private var newName = ""
  @State private var newEmail = ""
  @State private var showingAddUser = false
  
  var body: some View {
    NavigationView {
      List {
        ForEach(users, id: \.id) { user in
          NavigationLink(destination: UserDetailView(connection: connection, userId: user.id)) {
            HStack {
              VStack(alignment: .leading) {
                Text(user.name).font(.headline)
                Text(user.email).font(.caption).foregroundColor(.gray)
              }
              Spacer()
              if user.active {
                Image(systemName: "checkmark.circle.fill")
                  .foregroundColor(.green)
              }
            }
          }
        }
      }
      .navigationTitle("Users")
      .toolbar {
        Button(action: { showingAddUser = true }) {
          Image(systemName: "plus")
        }
      }
      .sheet(isPresented: $showingAddUser) {
        AddUserView(connection: connection, isPresented: $showingAddUser)
      }
    }
  }
}

// MARK: - User Detail

struct UserDetailView: View {
  let connection: SQLiteConnection
  let userId: Int
  
  @FetchOne(
    User.where { $0.id == userId },
    connection: connection
  ) var user: User?
  
  var body: some View {
    if let user = user {
      Form {
        Section("Profile") {
          LabeledContent("Name", value: user.name)
          LabeledContent("Email", value: user.email)
          LabeledContent("Status", value: user.active ? "Active" : "Inactive")
        }
        
        Section {
          Button("Toggle Active Status") {
            toggleActive()
          }
          
          Button("Delete User", role: .destructive) {
            deleteUser()
          }
        }
      }
      .navigationTitle(user.name)
    } else {
      Text("User not found")
    }
  }
  
  func toggleActive() {
    guard let user = user else { return }
    Task {
      try await connection.transaction { conn in
        try await conn.query(
          "UPDATE users SET active = ? WHERE id = ?",
          [.integer(user.active ? 0 : 1), .integer(userId)]
        )
      }
    }
  }
  
  func deleteUser() {
    Task {
      try await connection.transaction { conn in
        try await conn.query("DELETE FROM users WHERE id = ?", [.integer(userId)])
      }
    }
  }
}

// MARK: - Statistics

struct StatisticsView: View {
  let connection: SQLiteConnection
  
  @FetchOne(User.count, connection: connection) var totalUsers = 0
  @FetchOne(
    User.where { $0.active == true }.count,
    connection: connection
  ) var activeUsers = 0
  @FetchOne(
    User.where { $0.active == false }.count,
    connection: connection
  ) var inactiveUsers = 0
  
  var body: some View {
    NavigationView {
      List {
        Section("User Statistics") {
          HStack {
            Text("Total Users")
            Spacer()
            Text("\(totalUsers)")
              .font(.headline)
          }
          
          HStack {
            Text("Active")
            Spacer()
            Text("\(activeUsers)")
              .foregroundColor(.green)
              .font(.headline)
          }
          
          HStack {
            Text("Inactive")
            Spacer()
            Text("\(inactiveUsers)")
              .foregroundColor(.orange)
              .font(.headline)
          }
        }
      }
      .navigationTitle("Statistics")
    }
  }
}

// MARK: - Add User

struct AddUserView: View {
  let connection: SQLiteConnection
  @Binding var isPresented: Bool
  
  @State private var name = ""
  @State private var email = ""
  @State private var active = true
  
  var body: some View {
    NavigationView {
      Form {
        TextField("Name", text: $name)
        TextField("Email", text: $email)
          .textContentType(.emailAddress)
          .keyboardType(.emailAddress)
        Toggle("Active", isOn: $active)
      }
      .navigationTitle("Add User")
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("Cancel") {
            isPresented = false
          }
        }
        ToolbarItem(placement: .confirmationAction) {
          Button("Add") {
            addUser()
          }
          .disabled(name.isEmpty || email.isEmpty)
        }
      }
    }
  }
  
  func addUser() {
    Task {
      do {
        try await connection.transaction { conn in
          try await conn.query(
            "INSERT INTO users (name, email, active) VALUES (?, ?, ?)",
            [.text(name), .text(email), .integer(active ? 1 : 0)]
          )
        }
        await MainActor.run {
          isPresented = false
        }
      } catch {
        print("Error adding user: \(error)")
      }
    }
  }
}
```

## Migration from GRDB

### Before (GRDB)

```swift
import GRDB

let dbQueue = try DatabaseQueue(path: "app.db")

struct ContentView: View {
  @FetchAll(User.all, database: dbQueue) var users
  
  var body: some View {
    List(users, id: \.id) { user in
      Text(user.name)
    }
  }
}
```

### After (SQLiteNIO)

```swift
import SQLiteNIO

let connection = try await SQLiteConnection.open(
  storage: .file(path: "app.db"),
  threadPool: threadPool,
  on: eventLoop
).get()

struct ContentView: View {
  @FetchAll(User.all, connection: connection) var users
  
  var body: some View {
    List(users, id: \.id) { user in
      Text(user.name)
    }
  }
}
```

**Key Differences:**
- Use `connection:` parameter instead of `database:`
- Connection setup uses async/await
- Everything else stays the same!

## Best Practices

### 1. Connection Lifecycle

Manage connection lifecycle at the app level:

```swift
@main
struct MyApp: App {
  let connection: SQLiteConnection
  // ... setup in init()
  
  var body: some Scene {
    WindowGroup {
      ContentView(connection: connection)
    }
  }
}
```

### 2. Sharing Connection

Pass connection through environment or as parameters:

```swift
// Via parameter
struct MyView: View {
  let connection: SQLiteConnection
  @FetchAll(User.all, connection: connection) var users
}

// Or via environment (custom implementation)
struct MyView: View {
  @Environment(\.sqliteConnection) var connection
  @FetchAll(User.all, connection: connection) var users
}
```

### 3. Transaction for Writes

Always use transactions for write operations:

```swift
func addUser(name: String) {
  Task {
    try await connection.transaction { conn in
      try await conn.query(
        "INSERT INTO users (name) VALUES (?)",
        [.text(name)]
      )
    }
    // @FetchAll updates automatically
  }
}
```

### 4. Error Handling

Handle errors appropriately:

```swift
struct MyView: View {
  @FetchAll(User.all, connection: connection) var users
  
  var body: some View {
    if let error = $users.loadError {
      Text("Error: \(error.localizedDescription)")
    } else if $users.isLoading {
      ProgressView()
    } else {
      List(users, id: \.id) { user in
        Text(user.name)
      }
    }
  }
}
```

## Troubleshooting

### Issue: Property wrapper not updating

**Solution**: Ensure your model conforms to required protocols:

```swift
struct User: Codable, Hashable, Sendable, Decodable {
  // All fields must be Decodable
}
```

### Issue: Connection not available in View

**Solution**: Pass connection as parameter or store in environment:

```swift
struct ContentView: View {
  let connection: SQLiteConnection
  
  var body: some View {
    ChildView(connection: connection)
  }
}
```

### Issue: Queries not filtering correctly

**Solution**: Check your StructuredQueries syntax:

```swift
// Correct
@FetchAll(User.where { $0.active == true }, connection: connection)

// Also correct
@FetchAll(User.filter { $0.active == true }, connection: connection)
```

## Performance Tips

1. **Use specific queries** - Don't fetch all data if you only need a subset
2. **Leverage indexes** - Create database indexes for frequently queried fields
3. **Batch operations** - Use transactions for multiple writes
4. **Avoid N+1 queries** - Fetch related data in a single query when possible

## Summary

Phase 4 provides:
- ✅ Direct @FetchAll/@FetchOne integration with SQLiteConnection
- ✅ Automatic UI updates via SQLiteNIOObserver
- ✅ Same convenient API as GRDB
- ✅ Full type safety and compile-time checks
- ✅ Cross-platform support (Linux, macOS, iOS, etc.)

With Phase 4 complete, you can now build production-ready SwiftUI apps using SQLiteNIO with the familiar property wrapper syntax!
