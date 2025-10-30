import Foundation

/// Represents a triple: a relationship between three values (subject, predicate, object).
///
/// Unlike RDF, TripleLayer imposes no restrictions on which value types can appear in which position.
/// Any `Value` can be a subject, predicate, or object, providing maximum flexibility.
///
/// ## Example
/// ```swift
/// let alice = Value.uri("http://example.org/person/Alice")
/// let knows = Value.uri("http://xmlns.com/foaf/0.1/knows")
/// let bob = Value.uri("http://example.org/person/Bob")
///
/// let triple = Triple(subject: alice, predicate: knows, object: bob)
/// ```
public struct Triple: Hashable, Codable, Sendable {
    /// The subject of the triple
    public let subject: Value

    /// The predicate of the triple
    public let predicate: Value

    /// The object of the triple
    public let object: Value

    /// Optional metadata (confidence, source, timestamp, etc.)
    ///
    /// Note: Metadata does not affect equality or hashing. Two triples with different metadata
    /// but the same subject/predicate/object are considered equal.
    public var metadata: Metadata?

    /// Creates a new triple
    ///
    /// - Parameters:
    ///   - subject: The subject value
    ///   - predicate: The predicate value
    ///   - object: The object value
    ///   - metadata: Optional metadata
    public init(
        subject: Value,
        predicate: Value,
        object: Value,
        metadata: Metadata? = nil
    ) {
        self.subject = subject
        self.predicate = predicate
        self.object = object
        self.metadata = metadata
    }

    // MARK: - Hashable & Equatable

    /// Equality ignores metadata - only subject/predicate/object matter
    public static func == (lhs: Triple, rhs: Triple) -> Bool {
        return lhs.subject == rhs.subject &&
               lhs.predicate == rhs.predicate &&
               lhs.object == rhs.object
    }

    /// Hashing ignores metadata
    public func hash(into hasher: inout Hasher) {
        hasher.combine(subject)
        hasher.combine(predicate)
        hasher.combine(object)
    }
}

// MARK: - CustomStringConvertible

extension Triple: CustomStringConvertible {
    /// Returns a human-readable string representation in N-Triples-like format
    ///
    /// Example: `<http://example.org/Alice> <http://xmlns.com/foaf/0.1/knows> <http://example.org/Bob> .`
    public var description: String {
        return "\(subject) \(predicate) \(object) ."
    }
}

// MARK: - Convenience Initializers

extension Triple {
    /// Creates a triple with URI subject, predicate, and object
    public init(subjectURI: String, predicateURI: String, objectURI: String) {
        self.init(
            subject: .uri(subjectURI),
            predicate: .uri(predicateURI),
            object: .uri(objectURI)
        )
    }

    /// Creates a triple with URI subject and predicate, and text object
    public init(subjectURI: String, predicateURI: String, objectText: String, language: String? = nil) {
        self.init(
            subject: .uri(subjectURI),
            predicate: .uri(predicateURI),
            object: .text(objectText, language: language)
        )
    }

    /// Creates a triple with URI subject and predicate, and integer object
    public init(subjectURI: String, predicateURI: String, objectInt: Int64) {
        self.init(
            subject: .uri(subjectURI),
            predicate: .uri(predicateURI),
            object: .integer(objectInt)
        )
    }

    /// Creates a triple with URI subject and predicate, and float object
    public init(subjectURI: String, predicateURI: String, objectFloat: Double) {
        self.init(
            subject: .uri(subjectURI),
            predicate: .uri(predicateURI),
            object: .float(objectFloat)
        )
    }

    /// Creates a triple with URI subject and predicate, and boolean object
    public init(subjectURI: String, predicateURI: String, objectBool: Bool) {
        self.init(
            subject: .uri(subjectURI),
            predicate: .uri(predicateURI),
            object: .boolean(objectBool)
        )
    }
}
