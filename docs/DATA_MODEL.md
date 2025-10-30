# TripleLayer Data Model

## Overview

The TripleLayer data model is designed to be **simple, flexible, and type-safe**, supporting common knowledge graph patterns while avoiding the complexity of full RDF semantics.

## Core Types

### 1. Triple

The fundamental unit of storage representing a relationship between three values.

```swift
public struct Triple: Hashable, Codable, Sendable {
    public let subject: Value
    public let predicate: Value
    public let object: Value
    public var metadata: Metadata?

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
}
```

**Properties:**
- **Hashable**: Enables use in Sets and as Dictionary keys
- **Codable**: Supports JSON/binary serialization
- **Sendable**: Safe to share across concurrency boundaries (Swift 6 compatibility)

**Key Differences from RDF:**
- No restrictions on subject/predicate types (any `Value` allowed)
- Metadata is built-in (no reification needed)
- Simpler mental model for developers

### 2. Value

Represents different types of values that can appear in triples.

```swift
public enum Value: Hashable, Codable, Sendable {
    case uri(String)
    case text(String, language: String? = nil)
    case integer(Int64)
    case float(Double)
    case boolean(Bool)
    case binary(Data)

    // Future extensions:
    // case date(Date)
    // case timestamp(Date)
    // case uuid(UUID)
    // case json(Data)
}
```

#### 2.1 URI Type

Represents identifiers (IRIs, URLs, URIs).

```swift
case uri(String)
```

**Examples:**
```swift
.uri("http://example.org/person/Alice")
.uri("http://xmlns.com/foaf/0.1/knows")
.uri("urn:uuid:12345678-1234-1234-1234-123456789abc")
```

**Usage:**
- Entity identifiers
- Predicate identifiers
- Reference to external resources

**Validation:**
- No validation enforced (flexibility)
- Applications can validate if needed
- Can use any string-based identifier scheme

#### 2.2 Text Type

Represents human-readable text with optional language tag.

```swift
case text(String, language: String? = nil)
```

**Examples:**
```swift
.text("Alice Smith")                    // Plain text
.text("東京", language: "ja")            // Japanese
.text("Tokyo", language: "en")          // English
.text("Description of entity")          // Long text
```

**Usage:**
- Names, labels, descriptions
- Natural language text from knowledge extraction
- Multi-language content

**Language Tags:**
- Optional: `nil` means language-unspecified
- Format: ISO 639-1 two-letter codes ("en", "ja", "de")
- Extended tags supported: "en-US", "zh-CN"
- Case-insensitive comparison

**Storage Considerations:**
- Small strings (<128 bytes): Inlined in dictionary keys
- Large strings (>128 bytes): Stored separately with ID reference
- Encoding: UTF-8

#### 2.3 Integer Type

Represents whole numbers.

```swift
case integer(Int64)
```

**Examples:**
```swift
.integer(42)
.integer(2024)
.integer(-1000)
.integer(9223372036854775807)  // Max Int64
```

**Usage:**
- Counts, ages, IDs
- Timestamps (Unix epoch seconds)
- Enumeration values

**Range:**
- `-9,223,372,036,854,775,808` to `9,223,372,036,854,775,807`

**Comparison:**
- Numeric comparison (sortable)
- Stored in big-endian format for correct lexicographic ordering

#### 2.4 Float Type

Represents floating-point numbers.

```swift
case float(Double)
```

**Examples:**
```swift
.float(0.95)            // Confidence score
.float(3.14159)         // Pi
.float(1.23e10)         // Scientific notation
.float(.infinity)       // Special values
.float(.nan)            // Not-a-number
```

**Usage:**
- Confidence scores
- Measurements, weights
- Statistical values
- Percentages

**Precision:**
- IEEE 754 double-precision (64-bit)
- ~15 decimal digits of precision

**Special Values:**
- `.infinity`, `-.infinity`, `.nan` are supported
- NaN comparisons follow IEEE 754 (NaN != NaN)

#### 2.5 Boolean Type

Represents true/false values.

```swift
case boolean(Bool)
```

**Examples:**
```swift
.boolean(true)
.boolean(false)
```

**Usage:**
- Flags, feature toggles
- Existence checks
- Binary properties

**Storage:**
- Efficiently encoded as single byte

#### 2.6 Binary Type

Represents arbitrary binary data.

```swift
case binary(Data)
```

**Examples:**
```swift
.binary(imageData)
.binary(encryptedData)
.binary(serializedProtobuf)
```

**Usage:**
- Embeddings (vector data)
- Serialized structures
- Opaque data blobs
- Hashes, signatures

**Size Limits:**
- Recommended: <10KB per value
- Maximum: 100KB (FoundationDB value limit)
- Large data: Store reference URI instead

**Note:** Binary data is not human-readable in queries. Consider storing as URI reference for large objects.

### 3. Metadata

Optional metadata attached to triples.

```swift
public struct Metadata: Hashable, Codable, Sendable {
    public var confidence: Double?
    public var source: String?
    public var timestamp: Date?
    public var custom: [String: CodableValue]?

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
```

#### 3.1 Standard Fields

**confidence**: Probability or confidence score (0.0 to 1.0)
```swift
.confidence = 0.95  // 95% confident
```

**source**: Origin of the triple (document ID, URL, system name)
```swift
.source = "doc_12345"
.source = "https://example.com/article"
```

**timestamp**: When the triple was created/extracted
```swift
.timestamp = Date()
```

#### 3.2 Custom Fields

**custom**: Extensible key-value map for application-specific metadata

```swift
metadata.custom = [
    "extractor": "GPT-4",
    "version": "1.0",
    "domain": "medical"
]
```

**Storage:**
- Metadata is JSON-encoded and stored separately
- Not indexed (cannot query by metadata directly)
- Retrieved only with triple results

## Type Identity and Equality

### Value Equality

Two `Value` instances are equal if:

1. **Same case**: Both are `.text`, both are `.integer`, etc.
2. **Same associated data**: Exact string/number/binary match
3. **Language/type match** (for text):
   - `.text("Tokyo", language: "en")` ≠ `.text("Tokyo", language: "ja")`
   - `.text("Tokyo", language: nil)` ≠ `.text("Tokyo", language: "en")`

**Examples:**
```swift
// Equal
.uri("http://example.org/Alice") == .uri("http://example.org/Alice")
.integer(42) == .integer(42)
.text("Hello") == .text("Hello")

// Not equal
.uri("Alice") != .text("Alice")           // Different types
.text("Tokyo", language: "en") != .text("Tokyo", language: "ja")
.float(0.1 + 0.2) != .float(0.3)          // Floating-point precision
```

### Triple Equality

Two `Triple` instances are equal if:

1. `subject` values are equal
2. `predicate` values are equal
3. `object` values are equal
4. **Metadata is ignored** for equality/hashing

This means:
```swift
let t1 = Triple(subject: .uri("A"), predicate: .uri("knows"), object: .uri("B"))
let t2 = Triple(subject: .uri("A"), predicate: .uri("knows"), object: .uri("B"),
                metadata: Metadata(confidence: 0.9))

t1 == t2  // true - metadata doesn't affect equality
```

**Rationale:**
- Metadata represents properties *about* the triple, not the triple itself
- Allows updating metadata without creating duplicates
- Consistent with graph database semantics

## Serialization Formats

### 1. Binary (Internal)

**Dictionary Storage:**
```
Value → Bytes (for dictionary keys)
```

| Type | Encoding |
|------|----------|
| `uri(s)` | `Tuple("uri", s)` |
| `text(s, lang)` | `Tuple("text", s, lang ?? TupleNil)` |
| `integer(i)` | `Tuple("int", i)` |
| `float(f)` | `Tuple("float", f)` |
| `boolean(b)` | `Tuple("bool", b)` |
| `binary(d)` | `Tuple("bin", d)` |

**Advantages:**
- Type-safe
- Sortable (lexicographic ordering preserved)
- Efficient range queries

### 2. Human-Readable (N-Triples style)

For debugging and logging:

```
<http://example.org/Alice> <http://xmlns.com/foaf/0.1/name> "Alice Smith" .
<http://example.org/Alice> <http://example.org/age> 30 .
<http://example.org/Tokyo> <http://www.w3.org/2000/01/rdf-schema#label> "東京"@ja .
```

**Format Rules:**
- URIs: `<uri>`
- Text (plain): `"text"`
- Text (with language): `"text"@lang`
- Integers: `42`
- Floats: `3.14`
- Booleans: `true` or `false`
- Binary: `(binary data, N bytes)`

### 3. JSON

```json
{
  "subject": {"uri": "http://example.org/Alice"},
  "predicate": {"uri": "http://xmlns.com/foaf/0.1/name"},
  "object": {"text": "Alice Smith"},
  "metadata": {
    "confidence": 0.95,
    "source": "doc_123",
    "timestamp": "2024-01-15T10:30:00Z"
  }
}
```

**Usage:**
- API responses
- Import/export
- Integration with JSON-based systems

## Type Coercion and Conversion

### Automatic Coercion: NOT SUPPORTED

TripleLayer does not perform automatic type coercion. Each value retains its exact type.

```swift
// These are different values:
.integer(42) != .text("42")
.float(3.0) != .integer(3)
.boolean(true) != .text("true")
```

**Rationale:**
- Type safety
- Predictable behavior
- Explicit is better than implicit

### Manual Conversion

Applications must explicitly convert types if needed:

```swift
extension Value {
    func asText() -> String? {
        switch self {
        case .uri(let s): return s
        case .text(let s, _): return s
        case .integer(let i): return String(i)
        case .float(let f): return String(f)
        case .boolean(let b): return String(b)
        case .binary: return nil
        }
    }

    func asInteger() -> Int64? {
        switch self {
        case .integer(let i): return i
        case .text(let s, _): return Int64(s)
        case .float(let f): return Int64(f)
        default: return nil
        }
    }
}
```

## Common Patterns

### 1. Entity with Properties

```swift
let alice = Value.uri("http://example.org/person/Alice")
let nameProperty = Value.uri("http://xmlns.com/foaf/0.1/name")
let ageProperty = Value.uri("http://example.org/age")

let triples = [
    Triple(subject: alice, predicate: nameProperty, object: .text("Alice Smith")),
    Triple(subject: alice, predicate: ageProperty, object: .integer(30))
]
```

### 2. Multi-Language Labels

```swift
let tokyo = Value.uri("http://example.org/place/Tokyo")
let labelProperty = Value.uri("http://www.w3.org/2000/01/rdf-schema#label")

let triples = [
    Triple(subject: tokyo, predicate: labelProperty, object: .text("Tokyo", language: "en")),
    Triple(subject: tokyo, predicate: labelProperty, object: .text("東京", language: "ja")),
    Triple(subject: tokyo, predicate: labelProperty, object: .text("Tokio", language: "de"))
]
```

### 3. Knowledge Extraction with Confidence

```swift
let extractedTriple = Triple(
    subject: .uri("http://example.org/person/Alice"),
    predicate: .uri("http://example.org/worksAt"),
    object: .uri("http://example.org/company/TechCorp"),
    metadata: Metadata(
        confidence: 0.87,
        source: "document_456",
        timestamp: Date()
    )
)
```

### 4. Temporal Information

```swift
let event = Value.uri("http://example.org/event/Meeting123")
let startTimeProperty = Value.uri("http://example.org/startTime")

let triple = Triple(
    subject: event,
    predicate: startTimeProperty,
    object: .integer(1705320000)  // Unix timestamp
)
```

### 5. Embeddings and Vector Data

```swift
let document = Value.uri("http://example.org/doc/Article1")
let embeddingProperty = Value.uri("http://example.org/embedding")

// Serialize vector as binary data
let vectorData = withUnsafeBytes(of: [0.1, 0.2, 0.3, ...]) { Data($0) }

let triple = Triple(
    subject: document,
    predicate: embeddingProperty,
    object: .binary(vectorData)
)
```

## Design Rationale

### Why Not Just Strings?

Using a typed `Value` enum provides:

1. **Type Safety**: Compiler catches type errors
2. **Efficient Storage**: Native types (Int64, Double) stored compactly
3. **Correct Sorting**: Integers sort numerically, not lexicographically
4. **Language Support**: Built-in language tags without parsing
5. **Future Extensibility**: Easy to add new types

### Why Allow Any Type in Subject/Predicate?

Unlike RDF, TripleLayer allows flexibility:

**Use Case: Text-to-Text Relationships**
```swift
// Document similarity
Triple(
    subject: .text("Machine learning is..."),
    predicate: .uri("http://example.org/similarTo"),
    object: .text("Artificial intelligence is...")
)
```

**Use Case: Numeric Predicates**
```swift
// Time-based predicates
Triple(
    subject: .uri("http://example.org/user/Alice"),
    predicate: .integer(1705320000),  // Timestamp as predicate
    object: .text("logged in")
)
```

**Trade-off**: Flexibility vs. Conventions
- Applications should establish their own conventions
- Most use cases still use URIs for subjects/predicates
- But the option exists when needed

## Limitations and Constraints

### Size Limits

| Type | Limit | Notes |
|------|-------|-------|
| URI string | 10KB | FoundationDB key limit |
| Text string | 100KB | Value limit (or stored separately) |
| Binary data | 100KB | Value limit |
| Metadata JSON | 10KB | Reasonable limit |

### Unsupported Features

1. **No Blank Nodes**: All values must be concrete
2. **No Collections**: Lists/arrays not natively supported (model as multiple triples)
3. **No Nested Structures**: Values are flat (use JSON in `binary` if needed)

## Future Extensions

### Possible New Types

```swift
case date(Date)                  // Calendar date (without time)
case timestamp(Date)             // Full date + time
case duration(TimeInterval)      // Time span
case uuid(UUID)                  // UUIDs
case json(Data)                  // Structured JSON
case geo(latitude: Double, longitude: Double)  // Geographic coordinates
```

### Possible Metadata Extensions

```swift
public struct Metadata {
    // Existing fields...

    // Provenance
    public var creator: String?
    public var created: Date?
    public var modified: Date?

    // Quality indicators
    public var verified: Bool?
    public var accuracy: Double?

    // Versioning
    public var version: Int?
}
```

## Summary

The TripleLayer data model provides:

- ✅ **Simplicity**: Easy to understand and use
- ✅ **Flexibility**: No arbitrary RDF restrictions
- ✅ **Type Safety**: Compile-time checks
- ✅ **Extensibility**: Easy to add new types
- ✅ **Performance**: Efficient storage and queries
- ✅ **Interoperability**: JSON serialization for integration

This model is optimized for **knowledge extraction systems** where flexibility and ease of use are paramount, while still maintaining the benefits of a structured graph database.
