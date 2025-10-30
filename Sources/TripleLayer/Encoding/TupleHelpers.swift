import Foundation
@preconcurrency import FoundationDB

/// Helper functions for encoding and decoding tuple-based keys for FoundationDB storage
enum TupleHelpers {

    // MARK: - Dictionary Keys

    /// Encodes a key for Value → ID mapping
    /// Format: (rootPrefix, "dict", "v2i", <value_encoding>)
    static func encodeValueToIDKey(rootPrefix: String, value: Value) throws -> FDB.Bytes {
        switch value {
        case .uri(let s):
            return Tuple(rootPrefix, "dict", "v2i", "uri", s).encode()
        case .text(let s, let lang):
            if let lang = lang {
                return Tuple(rootPrefix, "dict", "v2i", "text", s, lang).encode()
            } else {
                return Tuple(rootPrefix, "dict", "v2i", "text", s).encode()
            }
        case .integer(let i):
            return Tuple(rootPrefix, "dict", "v2i", "int", i).encode()
        case .float(let f):
            return Tuple(rootPrefix, "dict", "v2i", "float", f).encode()
        case .boolean(let b):
            return Tuple(rootPrefix, "dict", "v2i", "bool", b).encode()
        case .binary(let d):
            let bytes: FDB.Bytes = [UInt8](d)
            // FoundationDB has a 10KB key size limit
            // We reserve some space for the tuple prefix, so limit binary data to 8KB
            guard bytes.count <= 8192 else {
                throw TripleError.invalidValue("Binary data too large for dictionary key (max 8KB, got \(bytes.count) bytes)")
            }
            return Tuple(rootPrefix, "dict", "v2i", "bin", bytes).encode()
        }
    }

    /// Encodes a key for ID → Value mapping
    /// Format: (rootPrefix, "dict", "i2v", id)
    static func encodeIDToValueKey(rootPrefix: String, id: UInt64) -> FDB.Bytes {
        return Tuple(rootPrefix, "dict", "i2v", Int64(bitPattern: id)).encode()
    }

    /// Encodes the ID counter key
    /// Format: (rootPrefix, "dict", "cnt")
    static func encodeCounterKey(rootPrefix: String) -> FDB.Bytes {
        return Tuple(rootPrefix, "dict", "cnt").encode()
    }

    // MARK: - Index Keys

    /// Encodes a triple key for a specific index
    /// Format: (rootPrefix, "idx", <index_type>, id1, id2, id3)
    static func encodeTripleKey(
        rootPrefix: String,
        indexType: String,
        id1: UInt64,
        id2: UInt64,
        id3: UInt64
    ) -> FDB.Bytes {
        return Tuple(
            rootPrefix,
            "idx",
            indexType,
            Int64(bitPattern: id1),
            Int64(bitPattern: id2),
            Int64(bitPattern: id3)
        ).encode()
    }

    /// Decodes a triple key and returns the three IDs
    static func decodeTripleKey(
        _ key: FDB.Bytes,
        rootPrefix: String,
        indexType: String
    ) throws -> (id1: UInt64, id2: UInt64, id3: UInt64) {
        let prefixBytes = Tuple(rootPrefix, "idx", indexType).encode()

        guard key.starts(with: prefixBytes) else {
            throw TripleError.internalError("Invalid key prefix for index \(indexType)")
        }

        let suffix = Array(key.dropFirst(prefixBytes.count))
        let elements = try Tuple.decode(from: suffix)

        guard elements.count == 3,
              let first = elements[0] as? Int64,
              let second = elements[1] as? Int64,
              let third = elements[2] as? Int64 else {
            throw TripleError.internalError("Failed to decode triple key")
        }

        return (
            UInt64(bitPattern: first),
            UInt64(bitPattern: second),
            UInt64(bitPattern: third)
        )
    }

    /// Encodes range keys for querying with optional bound IDs
    /// Returns (beginKey, endKey) for range scanning
    static func encodeRangeKeys(
        rootPrefix: String,
        indexType: String,
        id1: UInt64?,
        id2: UInt64?,
        id3: UInt64?
    ) -> (beginKey: FDB.Bytes, endKey: FDB.Bytes) {
        // Build prefix tuple based on which IDs are bound
        let beginKey: FDB.Bytes

        if let id1 = id1 {
            let id1Signed = Int64(bitPattern: id1)
            if let id2 = id2 {
                let id2Signed = Int64(bitPattern: id2)
                if let id3 = id3 {
                    let id3Signed = Int64(bitPattern: id3)
                    beginKey = Tuple(rootPrefix, "idx", indexType, id1Signed, id2Signed, id3Signed).encode()
                } else {
                    beginKey = Tuple(rootPrefix, "idx", indexType, id1Signed, id2Signed).encode()
                }
            } else {
                beginKey = Tuple(rootPrefix, "idx", indexType, id1Signed).encode()
            }
        } else {
            beginKey = Tuple(rootPrefix, "idx", indexType).encode()
        }

        let endKey = beginKey + [0xFF]
        return (beginKey, endKey)
    }

    // MARK: - Metadata Keys

    /// Encodes the triple count key
    /// Format: (rootPrefix, "meta", "cnt")
    static func encodeTripleCountKey(rootPrefix: String) -> FDB.Bytes {
        return Tuple(rootPrefix, "meta", "cnt").encode()
    }

    /// Encodes the schema version key
    /// Format: (rootPrefix, "meta", "ver")
    static func encodeSchemaVersionKey(rootPrefix: String) -> FDB.Bytes {
        return Tuple(rootPrefix, "meta", "ver").encode()
    }

    /// Encodes a key for storing triple metadata
    /// Format: (rootPrefix, "tmeta", subjectID, predicateID, objectID)
    static func encodeTripleMetadataKey(
        rootPrefix: String,
        subjectID: UInt64,
        predicateID: UInt64,
        objectID: UInt64
    ) -> FDB.Bytes {
        return Tuple(
            rootPrefix,
            "tmeta",
            Int64(bitPattern: subjectID),
            Int64(bitPattern: predicateID),
            Int64(bitPattern: objectID)
        ).encode()
    }

    // MARK: - Helpers

    /// Encodes an unsigned integer as little-endian bytes
    static func encodeUInt64(_ value: UInt64) -> FDB.Bytes {
        return withUnsafeBytes(of: value.littleEndian) { Array($0) }
    }

    /// Decodes an unsigned integer from little-endian bytes
    static func decodeUInt64(_ bytes: FDB.Bytes) -> UInt64 {
        return bytes.withUnsafeBytes { $0.load(as: UInt64.self).littleEndian }
    }
}
