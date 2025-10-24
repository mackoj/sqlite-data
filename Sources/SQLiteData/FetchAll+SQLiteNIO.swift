#if canImport(SQLiteNIO)
import Foundation
import SQLiteNIO
import Sharing
import StructuredQueriesCore

/// SQLiteNIO extensions for FetchAll property wrapper
extension FetchAll {
  
  /// Initializes this property with a query that fetches every row from a table using SQLiteNIO.
  ///
  /// Example:
  /// ```swift
  /// @FetchAll(Item.all, connection: sqliteConnection) var items
  /// ```
  ///
  /// - Parameters:
  ///   - wrappedValue: A default collection to associate with this property.
  ///   - connection: The SQLiteNIO connection to read from.
  public init(
    wrappedValue: [Element] = [],
    connection: SQLiteConnection
  )
  where Element: StructuredQueriesCore.Table, Element.QueryOutput == Element, Element: Decodable {
    let statement = Element.all.selectStar().asSelect()
    self.init(wrappedValue: wrappedValue, statement, connection: connection)
  }
  
  /// Initializes this property with a query associated with the wrapped value using SQLiteNIO.
  ///
  /// Example:
  /// ```swift
  /// @FetchAll(User.where { $0.active == true }, connection: sqliteConnection) var activeUsers
  /// ```
  ///
  /// - Parameters:
  ///   - wrappedValue: A default collection to associate with this property.
  ///   - statement: A query associated with the wrapped value.
  ///   - connection: The SQLiteNIO connection to read from.
  public init<S: SelectStatement>(
    wrappedValue: [Element] = [],
    _ statement: S,
    connection: SQLiteConnection
  )
  where
    Element == S.From.QueryOutput,
    S.QueryValue == (),
    S.From.QueryOutput: Sendable,
    S.From.QueryOutput: Decodable,
    S.Joins == ()
  {
    let statement = statement.selectStar()
    self.init(wrappedValue: wrappedValue, statement, connection: connection)
  }
  
  /// Initializes this property with a query associated with the wrapped value using SQLiteNIO.
  ///
  /// - Parameters:
  ///   - wrappedValue: A default collection to associate with this property.
  ///   - statement: A query associated with the wrapped value.
  ///   - connection: The SQLiteNIO connection to read from.
  public init<V: QueryRepresentable & Decodable>(
    wrappedValue: [Element] = [],
    _ statement: some StructuredQueriesCore.Statement<V>,
    connection: SQLiteConnection
  )
  where
    Element == V.QueryOutput,
    V.QueryOutput: Sendable,
    V.QueryOutput: Decodable
  {
    sharedReader = SharedReader(
      wrappedValue: wrappedValue,
      .fetchNIO(
        FetchAllStatementNIORequest(statement: statement),
        connection: connection
      )
    )
  }
  
  /// Initializes this property with a query associated with the wrapped value using SQLiteNIO.
  ///
  /// - Parameters:
  ///   - wrappedValue: A default collection to associate with this property.
  ///   - statement: A query associated with the wrapped value.
  ///   - connection: The SQLiteNIO connection to read from.
  public init<S: StructuredQueriesCore.Statement<Element>>(
    wrappedValue: [Element] = [],
    _ statement: S,
    connection: SQLiteConnection
  )
  where
    Element: QueryRepresentable,
    Element: Decodable,
    Element == S.QueryValue.QueryOutput
  {
    sharedReader = SharedReader(
      wrappedValue: wrappedValue,
      .fetchNIO(
        FetchAllStatementNIORequest(statement: statement),
        connection: connection
      )
    )
  }
}

/// Request type for FetchAll with SQLiteNIO
private struct FetchAllStatementNIORequest<V: QueryRepresentable & Decodable>: SQLiteNIOFetchRequest {
  typealias Value = [V.QueryOutput]
  
  let statement: SQLQueryExpression<V>
  
  init(statement: some StructuredQueriesCore.Statement<V>) {
    self.statement = SQLQueryExpression(statement)
  }
  
  // SQLiteNIO fetch method
  func fetch(_ connection: SQLiteConnection) async throws -> [V.QueryOutput] {
    try await statement.fetchAll(connection)
  }
  
  var observedTables: Set<String> {
    // TODO: Extract table names from statement
    // For now, observe all changes (empty set means observe nothing, but we'll refine this)
    []
  }
  
  // Hashable conformance
  func hash(into hasher: inout Hasher) {
    hasher.combine(ObjectIdentifier(V.self))
    hasher.combine(statement.sql)
  }
  
  static func == (lhs: Self, rhs: Self) -> Bool {
    lhs.statement.sql == rhs.statement.sql
  }
}

#endif
