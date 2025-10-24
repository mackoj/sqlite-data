#if canImport(CloudKit) && SQLITE_ENGINE_GRDB
  import StructuredQueriesCore

  @Table
  package struct TableInfo: Codable, Hashable {
    let defaultValue: String?
    let isPrimaryKey: Bool
    package let name: String
    let isNotNull: Bool
    let type: String
  }
#endif
