#if canImport(CloudKit) && SQLITE_ENGINE_GRDB
  import Foundation
  import StructuredQueriesCore

  @Table
  package struct ForeignKey {
    let table: String
    let from: String
    let to: String
    let onUpdate: ForeignKeyAction
    let onDelete: ForeignKeyAction
    let isNotNull: Bool
  }
#endif
