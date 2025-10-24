#if canImport(CloudKit) && SQLITE_ENGINE_GRDB
  #if swift(>=6.2)
    public typealias _SendableMetatype = SendableMetatype
  #else
    public typealias _SendableMetatype = Any
  #endif
#endif
