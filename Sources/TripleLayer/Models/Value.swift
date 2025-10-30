import Foundation

/// Represents different types of values that can appear in triples.
///
/// Unlike RDF, TripleLayer allows any value type in any position (subject, predicate, or object),
/// providing maximum flexibility for knowledge extraction and graph applications.
public enum Value: Hashable, Codable, Sendable {
    /// A URI/IRI identifier
    case uri(String)

    /// A text value with optional language tag
    case text(String, language: String? = nil)

    /// A 64-bit signed integer
    case integer(Int64)

    /// A double-precision floating-point number
    case float(Double)

    /// A boolean value
    case boolean(Bool)

    /// Binary data (e.g., embeddings, serialized structures)
    case binary(Data)

    // MARK: - Convenience Properties

    /// Returns the string representation of the value if applicable
    public var stringValue: String? {
        switch self {
        case .uri(let s): return s
        case .text(let s, _): return s
        case .integer(let i): return String(i)
        case .float(let f): return String(f)
        case .boolean(let b): return String(b)
        case .binary: return nil
        }
    }

    /// Returns true if this value is a URI
    public var isURI: Bool {
        if case .uri = self { return true }
        return false
    }

    /// Returns true if this value is text
    public var isText: Bool {
        if case .text = self { return true }
        return false
    }

    /// Returns true if this value is an integer
    public var isInteger: Bool {
        if case .integer = self { return true }
        return false
    }

    /// Returns true if this value is a float
    public var isFloat: Bool {
        if case .float = self { return true }
        return false
    }

    /// Returns true if this value is a boolean
    public var isBoolean: Bool {
        if case .boolean = self { return true }
        return false
    }

    /// Returns true if this value is binary data
    public var isBinary: Bool {
        if case .binary = self { return true }
        return false
    }

    /// Returns the language tag if this is a language-tagged text value
    public var languageTag: String? {
        if case .text(_, let lang) = self {
            return lang
        }
        return nil
    }
}

// MARK: - CustomStringConvertible

extension Value: CustomStringConvertible {
    /// Returns a human-readable string representation in N-Triples-like format
    public var description: String {
        switch self {
        case .uri(let s):
            return "<\(s)>"
        case .text(let s, let lang):
            if let lang = lang {
                return "\"\(s)\"@\(lang)"
            } else {
                return "\"\(s)\""
            }
        case .integer(let i):
            return "\(i)"
        case .float(let f):
            return "\(f)"
        case .boolean(let b):
            return "\(b)"
        case .binary(let d):
            return "(binary data, \(d.count) bytes)"
        }
    }
}

// MARK: - Codable Implementation

extension Value {
    private enum CodingKeys: String, CodingKey {
        case type
        case value
        case language
    }

    private enum ValueType: String, Codable {
        case uri
        case text
        case integer
        case float
        case boolean
        case binary
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(ValueType.self, forKey: .type)

        switch type {
        case .uri:
            let value = try container.decode(String.self, forKey: .value)
            self = .uri(value)
        case .text:
            let value = try container.decode(String.self, forKey: .value)
            let language = try container.decodeIfPresent(String.self, forKey: .language)
            self = .text(value, language: language)
        case .integer:
            let value = try container.decode(Int64.self, forKey: .value)
            self = .integer(value)
        case .float:
            let value = try container.decode(Double.self, forKey: .value)
            self = .float(value)
        case .boolean:
            let value = try container.decode(Bool.self, forKey: .value)
            self = .boolean(value)
        case .binary:
            let value = try container.decode(Data.self, forKey: .value)
            self = .binary(value)
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        switch self {
        case .uri(let value):
            try container.encode(ValueType.uri, forKey: .type)
            try container.encode(value, forKey: .value)
        case .text(let value, let language):
            try container.encode(ValueType.text, forKey: .type)
            try container.encode(value, forKey: .value)
            if let language = language {
                try container.encode(language, forKey: .language)
            }
        case .integer(let value):
            try container.encode(ValueType.integer, forKey: .type)
            try container.encode(value, forKey: .value)
        case .float(let value):
            try container.encode(ValueType.float, forKey: .type)
            try container.encode(value, forKey: .value)
        case .boolean(let value):
            try container.encode(ValueType.boolean, forKey: .type)
            try container.encode(value, forKey: .value)
        case .binary(let value):
            try container.encode(ValueType.binary, forKey: .type)
            try container.encode(value, forKey: .value)
        }
    }
}

// Note: No convenience initializers needed - enum cases serve as constructors
