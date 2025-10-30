import Foundation

/// Optional metadata that can be attached to triples.
///
/// Metadata provides additional information about the triple itself (not the relationship it represents).
/// Common uses include confidence scores from knowledge extraction, provenance tracking, and timestamps.
///
/// ## Example
/// ```swift
/// let metadata = Metadata(
///     confidence: 0.87,
///     source: "document_456",
///     timestamp: Date()
/// )
///
/// let triple = Triple(
///     subject: .uri("http://example.org/Alice"),
///     predicate: .uri("http://example.org/worksAt"),
///     object: .uri("http://example.org/TechCorp"),
///     metadata: metadata
/// )
/// ```
public struct Metadata: Hashable, Codable, Sendable {
    /// Confidence score (typically 0.0 to 1.0) indicating certainty of the triple
    ///
    /// Commonly used in knowledge extraction to track extraction confidence.
    public var confidence: Double?

    /// Source identifier (document ID, URL, system name, etc.)
    ///
    /// Tracks where this triple came from for provenance and debugging.
    public var source: String?

    /// Timestamp when the triple was created or extracted
    public var timestamp: Date?

    /// Extensible custom fields for application-specific metadata
    ///
    /// Use this for any metadata not covered by the standard fields.
    /// Values must be JSON-encodable.
    public var custom: [String: CodableValue]?

    /// Creates metadata with the specified fields
    ///
    /// - Parameters:
    ///   - confidence: Optional confidence score
    ///   - source: Optional source identifier
    ///   - timestamp: Optional timestamp
    ///   - custom: Optional custom fields
    public init(
        confidence: Double? = nil,
        source: String? = nil,
        timestamp: Date? = nil,
        custom: [String: CodableValue]? = nil
    ) {
        self.confidence = confidence
        self.source = source
        self.timestamp = timestamp
        self.custom = custom
    }
}

/// A type-erased wrapper for codable values
///
/// This allows storing various types in the custom metadata dictionary
/// while maintaining Codable conformance.
public enum CodableValue: Hashable, Codable, Sendable {
    case string(String)
    case int(Int)
    case double(Double)
    case bool(Bool)
    case null

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()

        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode(Int.self) {
            self = .int(value)
        } else if let value = try? container.decode(Double.self) {
            self = .double(value)
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "CodableValue cannot be decoded"
            )
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()

        switch self {
        case .string(let value):
            try container.encode(value)
        case .int(let value):
            try container.encode(value)
        case .double(let value):
            try container.encode(value)
        case .bool(let value):
            try container.encode(value)
        case .null:
            try container.encodeNil()
        }
    }
}

// MARK: - Convenience Extensions

extension Metadata {
    /// Returns true if this metadata indicates high confidence (>= 0.9)
    public var isHighConfidence: Bool {
        guard let confidence = confidence else { return false }
        return confidence >= 0.9
    }

    /// Returns true if this metadata has a source specified
    public var hasSource: Bool {
        return source != nil
    }
}
