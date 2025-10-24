#if SQLITE_ENGINE_SQLITENIO
import CustomDump
import Dependencies
import Foundation
import InlineSnapshotTesting
import SQLiteData
import SQLiteNIO
import StructuredQueriesCore
import StructuredQueriesTestSupport

/// An end-to-end snapshot testing helper for database content using SQLiteNIO.
///
/// This helper can be used to generate snapshots of both the given query and the results of the
/// query decoded back into Swift, using SQLiteNIO instead of GRDB.
///
/// ```swift
/// assertQueryNIO(
///   Reminder.select(\.title).order(by: \.title)
/// } results: {
///   """
///   ┌────────────────────────────┐
///   │ "Buy concert tickets"      │
///   │ "Call accountant"          │
///   │ "Doctor appointment"       │
///   │ "Get laundry"              │
///   │ "Groceries"                │
///   │ "Haircut"                  │
///   │ "Pick up kids from school" │
///   │ "Send weekly emails"       │
///   │ "Take a walk"              │
///   │ "Take out trash"           │
///   └────────────────────────────┘
///   """
/// }
/// ```
///
/// - Parameters:
///   - includeSQL: Whether to snapshot the SQL fragment in addition to the results.
///   - query: A statement.
///   - connection: The SQLiteNIO connection to use. A value of `nil` will use
///     `@Dependency(\.defaultSQLiteConnection)`.
///   - sql: A snapshot of the SQL produced by the statement.
///   - results: A snapshot of the results.
///   - fileID: The source `#fileID` associated with the assertion.
///   - filePath: The source `#filePath` associated with the assertion.
///   - function: The source `#function` associated with the assertion
///   - line: The source `#line` associated with the assertion.
///   - column: The source `#column` associated with the assertion.
@available(iOS 17, macOS 14, tvOS 17, watchOS 10, *)
@_disfavoredOverload
public func assertQueryNIO<V: QueryRepresentable & Decodable, S: StructuredQueriesCore.Statement<V>>(
  includeSQL: Bool = false,
  _ query: S,
  connection: SQLiteConnection? = nil,
  sql: (() -> String)? = nil,
  results: (() -> String)? = nil,
  fileID: StaticString = #fileID,
  filePath: StaticString = #filePath,
  function: StaticString = #function,
  line: UInt = #line,
  column: UInt = #column
) async where V.QueryOutput: Decodable {
  if includeSQL {
    assertInlineSnapshot(
      of: query,
      as: .sql,
      message: "Query did not match",
      syntaxDescriptor: InlineSnapshotSyntaxDescriptor(
        trailingClosureLabel: "sql",
        trailingClosureOffset: 0
      ),
      matches: sql,
      fileID: fileID,
      file: filePath,
      function: function,
      line: line,
      column: column
    )
  }
  let results = includeSQL ? results : sql
  do {
    @Dependency(\.defaultSQLiteConnection) var defaultConnection
    let conn = connection ?? defaultConnection
    
    // Fetch using SQLiteNIO
    let rows = try await query.fetchAll(conn)
    var table = ""
    if rows.isEmpty {
      table = "(No results)"
    } else {
      // Format as simple table
      printTableSimple(rows, to: &table)
    }
    if !table.isEmpty {
      assertInlineSnapshot(
        of: table,
        as: .lines,
        message: "Results did not match",
        syntaxDescriptor: InlineSnapshotSyntaxDescriptor(
          trailingClosureLabel: "results",
          trailingClosureOffset: includeSQL ? 1 : 0
        ),
        matches: results,
        fileID: fileID,
        file: filePath,
        function: function,
        line: line,
        column: column
      )
    } else if results != nil {
      assertInlineSnapshot(
        of: table,
        as: .lines,
        message: "Results expected to be empty",
        syntaxDescriptor: InlineSnapshotSyntaxDescriptor(
          trailingClosureLabel: "results",
          trailingClosureOffset: includeSQL ? 1 : 0
        ),
        matches: results,
        fileID: fileID,
        file: filePath,
        function: function,
        line: line,
        column: column
      )
    }
  } catch {
    assertInlineSnapshot(
      of: error.localizedDescription,
      as: .lines,
      message: "Results did not match",
      syntaxDescriptor: InlineSnapshotSyntaxDescriptor(
        trailingClosureLabel: "results",
        trailingClosureOffset: includeSQL ? 1 : 0
      ),
      matches: results,
      fileID: fileID,
      file: filePath,
      function: function,
      line: line,
      column: column
    )
  }
}

private func printTableSimple<T>(_ rows: [T], to output: inout some TextOutputStream) {
  var maxWidth = 0
  var formattedRows: [String] = []
  
  for row in rows {
    var cell = ""
    customDump(row, to: &cell)
    formattedRows.append(cell)
    maxWidth = max(maxWidth, cell.count)
  }
  
  guard !formattedRows.isEmpty else { return }
  
  // Top border
  output.write("┌─")
  output.write(String(repeating: "─", count: maxWidth))
  output.write("─┐\n")
  
  // Rows
  for (index, row) in formattedRows.enumerated() {
    output.write("│ ")
    output.write(row)
    output.write(String(repeating: " ", count: maxWidth - row.count))
    output.write(" │")
    if index < formattedRows.count - 1 {
      output.write("\n")
    }
  }
  
  // Bottom border
  output.write("\n└─")
  output.write(String(repeating: "─", count: maxWidth))
  output.write("─┘")
}

#endif
