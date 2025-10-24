#if canImport(SQLiteNIO)
import Foundation
import SQLiteNIO
import Sharing
import StructuredQueriesCore

/// SQLiteNIO extensions for FetchOne property wrapper
extension FetchOne {
  
  /// Initializes this property with a query that fetches the first row from a table using SQLiteNIO.
  ///
  /// Example:
  /// ```swift
  /// @FetchOne(User.where { $0.id == 1 }, connection: sqliteConnection) var user
  /// ```
  ///
  /// - Parameters:
  ///   - wrappedValue: A default value to associate with this property.
  ///   - connection: The SQLiteNIO connection to read from.
  public init(
    wrappedValue: sending Value,
    connection: SQLiteConnection
  )
  where
    Value: StructuredQueriesCore.Table & QueryRepresentable,
    Value.QueryOutput == Value,
    Value: Decodable
  {
    let statement = Value.all.selectStar().asSelect().limit(1)
    sharedReader = SharedReader(
      wrappedValue: wrappedValue,
      .fetchNIO(FetchOneStatementNIORequest(statement: statement), connection: connection)
    )
  }
  
  /// Initializes this property with a query that fetches the first row from a table using SQLiteNIO.
  ///
  /// - Parameters:
  ///   - wrappedValue: A default value to associate with this property.
  ///   - connection: The SQLiteNIO connection to read from.
  public init(
    wrappedValue: sending Value,
    connection: SQLiteConnection
  )
  where
    Value: _OptionalProtocol,
    Value: StructuredQueriesCore.Table,
    Value.QueryOutput == Value,
    Value.Wrapped: Decodable
  {
    let statement = Value.all.selectStar().asSelect().limit(1)
    sharedReader = SharedReader(
      wrappedValue: wrappedValue,
      .fetchNIO(FetchOneStatementNIOOptionalRequest(statement: statement), connection: connection)
    )
  }
  
  /// Initializes this property with a query associated with the wrapped value using SQLiteNIO.
  ///
  /// Example:
  /// ```swift
  /// @FetchOne(User.count, connection: sqliteConnection) var userCount = 0
  /// ```
  ///
  /// - Parameters:
  ///   - wrappedValue: A default value to associate with this property.
  ///   - statement: A query associated with the wrapped value.
  ///   - connection: The SQLiteNIO connection to read from.
  public init<V: QueryRepresentable>(
    wrappedValue: Value,
    _ statement: some StructuredQueriesCore.Statement<V>,
    connection: SQLiteConnection
  )
  where
    Value == V.QueryOutput,
    Value: Decodable
  {
    sharedReader = SharedReader(
      wrappedValue: wrappedValue,
      .fetchNIO(
        FetchOneStatementNIORequest(statement: statement),
        connection: connection
      )
    )
  }
  
  /// Initializes this property with a query associated with an optional value using SQLiteNIO.
  ///
  /// - Parameters:
  ///   - wrappedValue: A default value to associate with this property.
  ///   - statement: A query associated with the wrapped value.
  ///   - connection: The SQLiteNIO connection to read from.
  public init<V: QueryRepresentable>(
    wrappedValue: Value = nil,
    _ statement: some StructuredQueriesCore.Statement<V>,
    connection: SQLiteConnection
  )
  where
    Value == V.QueryOutput?,
    V.QueryOutput: Decodable
  {
    sharedReader = SharedReader(
      wrappedValue: wrappedValue,
      .fetchNIO(
        FetchOneStatementNIOOptionalValueRequest(statement: statement),
        connection: connection
      )
    )
  }
}

/// Request type for FetchOne with SQLiteNIO (non-optional)
private struct FetchOneStatementNIORequest<V: QueryRepresentable & Decodable>: SQLiteNIOFetchRequest {
  typealias Value = V.QueryOutput
  
  let statement: SQLQueryExpression<V>
  
  init(statement: some StructuredQueriesCore.Statement<V>) {
    self.statement = SQLQueryExpression(statement)
  }
  
  // SQLiteNIO fetch method
  func fetch(_ connection: SQLiteConnection) async throws -> V.QueryOutput {
    guard let result = try await statement.fetchOne(connection)
    else { throw NotFound() }
    return result
  }
  
  var observedTables: Set<String> {
    // TODO: Extract table names from statement
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

/// Request type for FetchOne with SQLiteNIO (optional value)
private struct FetchOneStatementNIOOptionalValueRequest<V: QueryRepresentable & Decodable>: SQLiteNIOFetchRequest {
  typealias Value = V.QueryOutput?
  
  let statement: SQLQueryExpression<V>
  
  init(statement: some StructuredQueriesCore.Statement<V>) {
    self.statement = SQLQueryExpression(statement)
  }
  
  // SQLiteNIO fetch method
  func fetch(_ connection: SQLiteConnection) async throws -> V.QueryOutput? {
    try await statement.fetchOne(connection)
  }
  
  var observedTables: Set<String> {
    // TODO: Extract table names from statement
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

/// Request type for FetchOne with SQLiteNIO (optional protocol)
private struct FetchOneStatementNIOOptionalRequest<V: QueryRepresentable & _OptionalProtocol>: SQLiteNIOFetchRequest where V.QueryOutput: _OptionalProtocol, V.Wrapped: Decodable {
  typealias Value = V.QueryOutput
  
  let statement: SQLQueryExpression<V>
  
  init(statement: some StructuredQueriesCore.Statement<V>) {
    self.statement = SQLQueryExpression(statement)
  }
  
  // SQLiteNIO fetch method
  func fetch(_ connection: SQLiteConnection) async throws -> V.QueryOutput {
    try await statement.fetchOne(connection) ?? ._none
  }
  
  var observedTables: Set<String> {
    // TODO: Extract table names from statement
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
