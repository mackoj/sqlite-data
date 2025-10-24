/// SQLiteRow Decoder
///
/// Provides Decodable support for SQLiteNIO's SQLiteRow, similar to GRDB's FetchableRecord.

import Foundation

#if canImport(SQLiteNIO)
import SQLiteNIO
import NIOCore
import NIOFoundationCompat

/// Decoder that decodes a Decodable type from a SQLiteRow
public struct SQLiteRowDecoder {
  
  public init() {}
  
  /// Decode a Decodable type from a SQLiteRow
  public func decode<T: Decodable>(_ type: T.Type, from row: SQLiteRow) throws -> T {
    let decoder = _SQLiteRowDecoder(row: row)
    return try T(from: decoder)
  }
}

// MARK: - Private Implementation

private struct _SQLiteRowDecoder: Decoder {
  let row: SQLiteRow
  var codingPath: [CodingKey] = []
  var userInfo: [CodingUserInfoKey: Any] = [:]
  
  func container<Key>(keyedBy type: Key.Type) throws -> KeyedDecodingContainer<Key> where Key: CodingKey {
    KeyedDecodingContainer(SQLiteKeyedDecodingContainer(row: row, codingPath: codingPath))
  }
  
  func unkeyedContainer() throws -> UnkeyedDecodingContainer {
    throw DecodingError.dataCorrupted(
      DecodingError.Context(
        codingPath: codingPath,
        debugDescription: "Unkeyed containers are not supported for SQLiteRow"
      )
    )
  }
  
  func singleValueContainer() throws -> SingleValueDecodingContainer {
    throw DecodingError.dataCorrupted(
      DecodingError.Context(
        codingPath: codingPath,
        debugDescription: "Single value containers are not supported for SQLiteRow"
      )
    )
  }
}

private struct SQLiteKeyedDecodingContainer<Key: CodingKey>: KeyedDecodingContainerProtocol {
  let row: SQLiteRow
  var codingPath: [CodingKey]
  var allKeys: [Key] { [] } // Would need to enumerate columns
  
  func contains(_ key: Key) -> Bool {
    row.column(key.stringValue) != nil
  }
  
  func decodeNil(forKey key: Key) throws -> Bool {
    guard let column = row.column(key.stringValue) else {
      throw DecodingError.keyNotFound(
        key,
        DecodingError.Context(
          codingPath: codingPath + [key],
          debugDescription: "No column found for key '\(key.stringValue)'"
        )
      )
    }
    return column.isNull
  }
  
  func decode(_ type: Bool.Type, forKey key: Key) throws -> Bool {
    try decodeValue(forKey: key) { data in
      guard let bool = data.bool else {
        throw DecodingError.typeMismatch(Bool.self, DecodingError.Context(
          codingPath: codingPath + [key],
          debugDescription: "Could not convert to Bool"
        ))
      }
      return bool
    }
  }
  
  func decode(_ type: String.Type, forKey key: Key) throws -> String {
    try decodeValue(forKey: key) { data in
      guard let string = data.string else {
        throw DecodingError.typeMismatch(String.self, DecodingError.Context(
          codingPath: codingPath + [key],
          debugDescription: "Could not convert to String"
        ))
      }
      return string
    }
  }
  
  func decode(_ type: Double.Type, forKey key: Key) throws -> Double {
    try decodeValue(forKey: key) { data in
      guard let double = data.double else {
        throw DecodingError.typeMismatch(Double.self, DecodingError.Context(
          codingPath: codingPath + [key],
          debugDescription: "Could not convert to Double"
        ))
      }
      return double
    }
  }
  
  func decode(_ type: Float.Type, forKey key: Key) throws -> Float {
    Float(try decode(Double.self, forKey: key))
  }
  
  func decode(_ type: Int.Type, forKey key: Key) throws -> Int {
    try decodeValue(forKey: key) { data in
      guard let int = data.integer else {
        throw DecodingError.typeMismatch(Int.self, DecodingError.Context(
          codingPath: codingPath + [key],
          debugDescription: "Could not convert to Int"
        ))
      }
      return int
    }
  }
  
  func decode(_ type: Int8.Type, forKey key: Key) throws -> Int8 {
    Int8(try decode(Int.self, forKey: key))
  }
  
  func decode(_ type: Int16.Type, forKey key: Key) throws -> Int16 {
    Int16(try decode(Int.self, forKey: key))
  }
  
  func decode(_ type: Int32.Type, forKey key: Key) throws -> Int32 {
    Int32(try decode(Int.self, forKey: key))
  }
  
  func decode(_ type: Int64.Type, forKey key: Key) throws -> Int64 {
    Int64(try decode(Int.self, forKey: key))
  }
  
  func decode(_ type: UInt.Type, forKey key: Key) throws -> UInt {
    UInt(try decode(Int.self, forKey: key))
  }
  
  func decode(_ type: UInt8.Type, forKey key: Key) throws -> UInt8 {
    UInt8(try decode(Int.self, forKey: key))
  }
  
  func decode(_ type: UInt16.Type, forKey key: Key) throws -> UInt16 {
    UInt16(try decode(Int.self, forKey: key))
  }
  
  func decode(_ type: UInt32.Type, forKey key: Key) throws -> UInt32 {
    UInt32(try decode(Int.self, forKey: key))
  }
  
  func decode(_ type: UInt64.Type, forKey key: Key) throws -> UInt64 {
    UInt64(try decode(Int.self, forKey: key))
  }
  
  func decode<T>(_ type: T.Type, forKey key: Key) throws -> T where T: Decodable {
    // Handle special types like Date, UUID, etc.
    if type == Date.self {
      // Try to decode as timestamp or ISO8601 string
      if let timestamp = try? decodeValue(forKey: key, { data -> Double in
        guard let double = data.double else {
          throw DecodingError.typeMismatch(Double.self, DecodingError.Context(
            codingPath: codingPath + [key],
            debugDescription: "Could not convert to Double"
          ))
        }
        return double
      }) {
        return Date(timeIntervalSince1970: timestamp) as! T
      } else if let string = try? decodeValue(forKey: key, { data -> String in
        guard let string = data.string else {
          throw DecodingError.typeMismatch(String.self, DecodingError.Context(
            codingPath: codingPath + [key],
            debugDescription: "Could not convert to String"
          ))
        }
        return string
      }) {
        if let date = ISO8601DateFormatter().date(from: string) {
          return date as! T
        }
      }
    }
    
    if type == UUID.self {
      let string = try decode(String.self, forKey: key)
      guard let uuid = UUID(uuidString: string) else {
        throw DecodingError.dataCorruptedError(
          forKey: key,
          in: self,
          debugDescription: "Invalid UUID string: \(string)"
        )
      }
      return uuid as! T
    }
    
    if type == Data.self {
      return try decodeValue(forKey: key) { data in
        guard let blob = data.blob else {
          throw DecodingError.typeMismatch(Data.self, DecodingError.Context(
            codingPath: codingPath + [key],
            debugDescription: "Could not convert to Data"
          ))
        }
        return Data(buffer: blob)
      } as! T
    }
    
    // For other Decodable types, create a nested decoder
    throw DecodingError.dataCorruptedError(
      forKey: key,
      in: self,
      debugDescription: "Decoding nested types from SQLiteRow is not yet supported"
    )
  }
  
  func nestedContainer<NestedKey>(keyedBy type: NestedKey.Type, forKey key: Key) throws -> KeyedDecodingContainer<NestedKey> where NestedKey: CodingKey {
    throw DecodingError.dataCorruptedError(
      forKey: key,
      in: self,
      debugDescription: "Nested containers are not supported for SQLiteRow"
    )
  }
  
  func nestedUnkeyedContainer(forKey key: Key) throws -> UnkeyedDecodingContainer {
    throw DecodingError.dataCorruptedError(
      forKey: key,
      in: self,
      debugDescription: "Nested unkeyed containers are not supported for SQLiteRow"
    )
  }
  
  func superDecoder() throws -> Decoder {
    throw DecodingError.dataCorrupted(
      DecodingError.Context(
        codingPath: codingPath,
        debugDescription: "Super decoders are not supported for SQLiteRow"
      )
    )
  }
  
  func superDecoder(forKey key: Key) throws -> Decoder {
    throw DecodingError.dataCorruptedError(
      forKey: key,
      in: self,
      debugDescription: "Super decoders are not supported for SQLiteRow"
    )
  }
  
  private func decodeValue<T>(forKey key: Key, _ decode: (SQLiteData) throws -> T) throws -> T {
    guard let column = row.column(key.stringValue) else {
      throw DecodingError.keyNotFound(
        key,
        DecodingError.Context(
          codingPath: codingPath + [key],
          debugDescription: "No column found for key '\(key.stringValue)'"
        )
      )
    }
    
    do {
      return try decode(column)
    } catch {
      throw DecodingError.typeMismatch(
        T.self,
        DecodingError.Context(
          codingPath: codingPath + [key],
          debugDescription: "Could not decode value for key '\(key.stringValue)': \(error)"
        )
      )
    }
  }
}

// MARK: - SQLiteRow Extensions

extension SQLiteRow {
  /// Decode this row as a Decodable type
  public func decode<T: Decodable>(_ type: T.Type) throws -> T {
    try SQLiteRowDecoder().decode(type, from: self)
  }
}

#endif
