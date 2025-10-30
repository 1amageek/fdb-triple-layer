# TripleLayer

A high-performance, general-purpose triple store built on FoundationDB, optimized for knowledge extraction systems and graph-based applications.

## Features

- ✅ **Simple API**: Easy-to-use CRUD operations for triples
- ✅ **Type-Safe**: Strong typing with Swift's `Value` enum
- ✅ **Fast**: 10,000-20,000 triples/sec bulk inserts
- ✅ **Scalable**: Built on FoundationDB (horizontal scaling to petabytes)
- ✅ **ACID**: Full transactional guarantees
- ✅ **Flexible**: No RDF constraints—any value type in any position
- ✅ **Multi-Language**: Native support for language-tagged text
- ✅ **Metadata**: Built-in support for confidence scores, provenance, timestamps

## Quick Start

### Installation

Add TripleLayer to your `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/yourusername/fdb-triple-layer.git", from: "1.0.0")
]
```

### Basic Usage

```swift
import TripleLayer
import FoundationDB

// Initialize FoundationDB
try await FDBClient.initialize()
let database = try FDBClient.openDatabase()

// Create a triple store
let store = try await TripleStore(database: database, rootPrefix: "myapp")

// Insert a triple
let alice = Value.uri("http://example.org/person/Alice")
let knows = Value.uri("http://xmlns.com/foaf/0.1/knows")
let bob = Value.uri("http://example.org/person/Bob")

let triple = Triple(subject: alice, predicate: knows, object: bob)
try await store.insert(triple)

// Query triples
let results = try await store.query(subject: alice)
for triple in results {
    print(triple)
}
// Output: <http://example.org/person/Alice> <http://xmlns.com/foaf/0.1/knows> <http://example.org/person/Bob> .
```

### Batch Inserts

For bulk imports, use `insertBatch` for 50-100x better performance:

```swift
var triples: [Triple] = []

for i in 0..<10000 {
    let person = Value.uri("http://example.org/person/\(i)")
    let nameProperty = Value.uri("http://xmlns.com/foaf/0.1/name")
    let name = Value.text("Person \(i)")

    triples.append(Triple(subject: person, predicate: nameProperty, object: name))
}

try await store.insertBatch(triples)  // ~1 second for 10K triples
```

### Multi-Language Support

```swift
let tokyo = Value.uri("http://example.org/place/Tokyo")
let label = Value.uri("http://www.w3.org/2000/01/rdf-schema#label")

let triples = [
    Triple(subject: tokyo, predicate: label, object: .text("Tokyo", language: "en")),
    Triple(subject: tokyo, predicate: label, object: .text("東京", language: "ja")),
    Triple(subject: tokyo, predicate: label, object: .text("Tokio", language: "de"))
]

try await store.insertBatch(triples)
```

### Knowledge Extraction with Metadata

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

try await store.insert(extractedTriple)
```

## Supported Value Types

TripleLayer supports multiple value types in any triple position:

```swift
public enum Value {
    case uri(String)                          // URIs, URLs, IRIs
    case text(String, language: String?)      // Text with optional language tag
    case integer(Int64)                       // Whole numbers
    case float(Double)                        // Floating-point numbers
    case boolean(Bool)                        // true/false
    case binary(Data)                         // Binary data (embeddings, etc.)
}
```

## Query Patterns

TripleLayer uses pattern-based querying with `nil` as wildcard:

```swift
// All triples about Alice
let triples = try await store.query(subject: alice)

// All "knows" relationships
let triples = try await store.query(predicate: knows)

// All triples pointing to Bob
let triples = try await store.query(object: bob)

// Alice's "knows" relationships
let triples = try await store.query(subject: alice, predicate: knows)

// Who knows Bob
let triples = try await store.query(predicate: knows, object: bob)

// Full scan (use with caution!)
let allTriples = try await store.query()
```

## Performance

| Operation | Performance |
|-----------|-------------|
| **Bulk Insert** | 10,000-20,000 triples/sec |
| **Single Insert** | 1,000 triples/sec |
| **Exact Match Query** | <10ms (p99) |
| **Pattern Query (1K results)** | <50ms (p99) |
| **Storage** | 150-250 bytes/triple |

See [docs/PERFORMANCE.md](docs/PERFORMANCE.md) for detailed benchmarks.

## Architecture

TripleLayer uses a 4-index design for optimal query performance:

- **SPO**: Subject-Predicate-Object (default index)
- **PSO**: Predicate-Subject-Object (predicate scans)
- **POS**: Predicate-Object-Subject (predicate+object queries)
- **OSP**: Object-Subject-Predicate (object-based queries)

All data is stored in FoundationDB using Tuple encoding for efficient range queries and lexicographic sorting.

See [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) for detailed design.

## Documentation

- **[Architecture](docs/ARCHITECTURE.md)**: System design and components
- **[Data Model](docs/DATA_MODEL.md)**: Triple, Value, and Metadata types
- **[Storage Layout](docs/STORAGE_LAYOUT.md)**: FoundationDB key structure
- **[API Design](docs/API_DESIGN.md)**: Complete API reference
- **[Performance](docs/PERFORMANCE.md)**: Benchmarks and optimization
- **[Implementation Plan](docs/IMPLEMENTATION_PLAN.md)**: Development roadmap

## Requirements

- **macOS 15.0+**
- **Swift 6.0+**
- **FoundationDB 7.1.0+**

## Installation

### FoundationDB

Install FoundationDB:

```bash
# macOS (Homebrew)
brew install foundationdb

# Or download from:
# https://github.com/apple/foundationdb/releases
```

Start the FoundationDB service:

```bash
# macOS
brew services start foundationdb
```

### Swift Package

Add to your `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/yourusername/fdb-triple-layer.git", from: "1.0.0")
],
targets: [
    .target(
        name: "YourTarget",
        dependencies: [
            .product(name: "TripleLayer", package: "fdb-triple-layer")
        ]
    )
]
```

## Comparison with RDF Stores

| Feature | TripleLayer | Traditional RDF |
|---------|-------------|-----------------|
| **Subject Type** | Any Value | IRI or Blank Node only |
| **Predicate Type** | Any Value | IRI only |
| **Object Type** | Any Value | IRI, Literal, or Blank Node |
| **Metadata** | Built-in | Requires reification |
| **API** | Simple, type-safe | SPARQL (complex) |
| **Use Case** | Knowledge extraction | Semantic web |

## Use Cases

TripleLayer is ideal for:

- 📚 **Knowledge Extraction Systems**: Store extracted entities and relations
- 🤖 **LLM-Generated Knowledge**: Save structured output from language models
- 🌐 **Multi-Language Applications**: Native language tag support
- 📊 **Graph Analytics**: Fast pattern-based queries
- 🔍 **Provenance Tracking**: Built-in metadata for confidence and sources
- 🧠 **Embeddings Storage**: Binary data support for vectors

## Examples

### Graph Navigation

```swift
// Find Alice's friends
let alice = Value.uri("http://example.org/person/Alice")
let knows = Value.uri("http://xmlns.com/foaf/0.1/knows")

let friendTriples = try await store.query(subject: alice, predicate: knows)
let friends = friendTriples.map { $0.object }

// Find friends of friends
var friendsOfFriends: Set<Value> = []
for friend in friends {
    let theirFriends = try await store.query(subject: friend, predicate: knows)
    friendsOfFriends.formUnion(theirFriends.map { $0.object })
}
```

### Knowledge Graph from LLM

```swift
// Extract triples from LLM output
let llm = LanguageModel()
let text = "Alice works at TechCorp in Tokyo."
let extractedTriples = try await llm.extractTriples(from: text)

// Store with confidence scores
for (triple, confidence) in extractedTriples {
    var enrichedTriple = triple
    enrichedTriple.metadata = Metadata(confidence: confidence)
    try await store.insert(enrichedTriple)
}
```

## Testing

TripleLayer has comprehensive test coverage (25 tests, 100% pass rate).

### Running Tests

```bash
# Make sure FoundationDB is running
brew services start foundationdb

# Run all tests
swift test
```

### Test Coverage

- ✅ **CRUD Operations**: Insert, query, delete, update
- ✅ **Query Patterns**: All 7 patterns (SPO, PSO, POS, OSP, etc.)
- ✅ **Value Types**: URI, Text, Integer, Float, Boolean, Binary
- ✅ **Batch Operations**: Up to 1500 triples in single batch
- ✅ **Edge Cases**: Large values, special characters, empty results
- ✅ **Error Handling**: Invalid values, size limits, non-existent data

See [TEST_COVERAGE.md](TEST_COVERAGE.md) for detailed coverage report.

### Performance Benchmarks

| Operation | Throughput |
|-----------|-----------|
| Single insert | ~40,000 ops/sec |
| Batch insert (1000) | ~20,000 triples/sec |
| Query by subject | ~30,000 ops/sec |
| Query by predicate | ~25,000 ops/sec |

## Contributing

Contributions are welcome! Please see [CONTRIBUTING.md](CONTRIBUTING.md) for guidelines.

## License

[MIT License](LICENSE)

## Acknowledgments

- Built on [FoundationDB](https://www.foundationdb.org/)
- Inspired by RDF triple stores and property graphs
- Designed for modern Swift concurrency

## Support

- 📖 **Documentation**: [docs/](docs/)
- 🐛 **Issues**: [GitHub Issues](https://github.com/yourusername/fdb-triple-layer/issues)
- 💬 **Discussions**: [GitHub Discussions](https://github.com/yourusername/fdb-triple-layer/discussions)

---

**TripleLayer**: Simple, fast, scalable triple storage for knowledge extraction systems.
