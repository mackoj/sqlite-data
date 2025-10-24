#if SQLITE_ENGINE_SQLITENO
import Dependencies
import Foundation
import SQLiteNIO

extension DependencyValues {
  /// The default SQLiteNIO connection used by `@FetchAll` and `@FetchOne` property wrappers.
  ///
  /// Configure this as early as possible in your app's lifetime, like the app entry point in
  /// SwiftUI, using `prepareDependencies`:
  ///
  /// ```swift
  /// import SQLiteData
  /// import SQLiteNIO
  /// import SwiftUI
  ///
  /// @main
  /// struct MyApp: App {
  ///   init() {
  ///     prepareDependencies {
  ///       // Create SQLiteNIO connection and run migrations...
  ///       $0.defaultSQLiteConnection = try! await SQLiteConnection.open(
  ///         path: "path/to/database.db"
  ///       )
  ///     }
  ///   }
  ///   // ...
  /// }
  /// ```
  ///
  /// > Note: You can only prepare the connection a single time in the lifetime of your app.
  /// > Attempting to do so more than once will produce a runtime warning.
  ///
  /// Once configured, access the connection anywhere using `@Dependency`:
  ///
  /// ```swift
  /// @Dependency(\.defaultSQLiteConnection) var connection
  ///
  /// // Use with property wrappers
  /// @FetchAll(User.all, connection: connection) var users
  /// @FetchOne(User.count, connection: connection) var userCount = 0
  ///
  /// // Or use directly
  /// try await connection.transaction { conn in
  ///   try await conn.query("INSERT INTO users (name) VALUES (?)", [.text("Alice")])
  /// }
  /// ```
  ///
  /// See the SQLiteNIO phase documentation for more info.
  public var defaultSQLiteConnection: SQLiteConnection {
    get { self[DefaultSQLiteConnectionKey.self] }
    set { self[DefaultSQLiteConnectionKey.self] = newValue }
  }

  private enum DefaultSQLiteConnectionKey: DependencyKey {
    static var liveValue: SQLiteConnection {
      testValue
    }
    
    static var testValue: SQLiteConnection {
      var message: String {
        @Dependency(\.context) var context
        switch context {
        case .live:
          return """
            No default SQLiteNIO connection is configured. To set the connection that is used by \
            'SQLiteData' with SQLiteNIO, use the 'prepareDependencies' tool as early as possible \
            in the lifetime of your app, such as in your app or scene delegate in UIKit, or the \
            app entry point in SwiftUI:

                @main
                struct MyApp: App {
                  init() {
                    prepareDependencies {
                      $0.defaultSQLiteConnection = try! await SQLiteConnection.open(
                        path: "path/to/database.db"
                      )
                    }
                  }
                  // ...
                }
            """

        case .preview:
          return """
            No default SQLiteNIO connection is configured. To set the connection that is used by \
            'SQLiteData' in a preview, use a tool like 'prepareDependencies':

                #Preview {
                  let _ = prepareDependencies {
                    $0.defaultSQLiteConnection = try! await SQLiteConnection.open(
                      storage: .memory
                    )
                  }
                  // ...
                }
            """

        case .test:
          return """
            No default SQLiteNIO connection is configured. To set the connection that is used by \
            'SQLiteData' in a test, use a tool like the 'dependency' trait from \
            'DependenciesTestSupport':

                import DependenciesTestSupport

                @Suite(
                  .dependency(
                    \\.defaultSQLiteConnection,
                    try await SQLiteConnection.open(storage: .memory)
                  )
                )
                struct MyTests {
                  // ...
                }
            """
        }
      }
      if shouldReportUnimplemented {
        reportIssue(message)
      }
      // Note: This is a placeholder. In real usage, this would need to be an actual connection.
      // For now, we'll trigger the error above and let the user know they need to configure it.
      fatalError("Default SQLiteNIO connection not configured")
    }
  }
}

#endif
