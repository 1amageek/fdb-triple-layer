# TripleLayer API Design

## Public API Overview

TripleLayer provides a simple, type-safe API built around the `TripleStore` actor.

## Core API: TripleStore

```swift
public actor TripleStore {
    public init(
        database: any DatabaseProtocol,
        rootPrefix: String,
        logger: Logger? = nil
    ) async throws

    // CRUD Operations
    public func insert(_ triple: Triple) async throws
    public func insertBatch(_ triples: [Triple]) async throws
    public func delete(_ triple: Triple) async throws
    public func query(subject: Value?, predicate: Value?, object: Value?) async throws -> [Triple]

    // Utility
    public func count() async throws -> UInt64
    public func contains(_ triple: Triple) async throws -> Bool
}
```

## Initialization

### Creating a Store

```swift
import TripleLayer
import FoundationDB

// Initialize FoundationDB
try await FDBClient.initialize()
let database = try FDBClient.openDatabase()

// Create store
let store = try await TripleStore(
    database: database,
    rootPrefix: "myapp"
)
```

**Parameters:**
- `database`: FoundationDB database instance
- `rootPrefix`: Unique namespace for this store (e.g., "myapp", "prod", "test")
- `logger`: Optional custom logger (default: auto-created)

## Insert Operations

### Insert Single Triple

```swift
public func insert(_ triple: Triple) async throws
```

**Behavior:**
- Idempotent: Inserting same triple twice has no effect
- Creates new Value IDs if needed
- Updates all 4 indexes atomically
- Increments triple count

**Example:**
```swift
let alice = Value.uri("http://example.org/person/Alice")
let knows = Value.uri("http://xmlns.com/foaf/0.1/knows")
let bob = Value.uri("http://example.org/person/Bob")

let triple = Triple(subject: alice, predicate: knows, object: bob)
try await store.insert(triple)
```

**Throws:**
- `TripleError.transactionTooLarge` if value exceeds limits
- `TripleError.internalError` for FoundationDB errors

### Insert Multiple Triples (Batch)

```swift
public func insertBatch(_ triples: [Triple]) async throws
```

**Behavior:**
- Automatically batches into transactions of 1000 triples
- Much faster than inserting individually (50-100x speedup)
- Each batch is atomic
- Skips duplicates within batch

**Example:**
```swift
var triples: [Triple] = []
for i in 0..<10000 {
    let person = Value.uri("http://example.org/person/\(i)")
    let name = Value.uri("http://xmlns.com/foaf/0.1/name")
    let nameLiteral = Value.text("Person \(i)")
    triples.append(Triple(subject: person, predicate: name, object: nameLiteral))
}

try await store.insertBatch(triples)  // ~1 second for 10K triples
```

**Performance:**
- ~10,000-50,000 triples/sec (depends on value reuse)
- Uses single transaction per 1000-triple batch

## Query Operations

### Pattern-Based Query

```swift
public func query(
    subject: Value? = nil,
    predicate: Value? = nil,
    object: Value? = nil
) async throws -> [Triple]
```

**Parameters:**
- Use `nil` for any component to match all values (wildcard)
- Bound values must match exactly

**Query Patterns:**

| Pattern | Example | Index Used |
|---------|---------|------------|
| `(S, ?, ?)` | All triples about Alice | SPO |
| `(?, P, ?)` | All "knows" relationships | PSO |
| `(?, ?, O)` | All pointing to Bob | OSP |
| `(S, P, ?)` | Alice's names | SPO |
| `(?, P, O)` | Who knows Bob | POS |
| `(S, ?, O)` | Alice→Bob relationships | SPO (scan) |
| `(?, ?, ?)` | All triples | SPO (full scan) |

**Examples:**

```swift
// 1. Find all triples about Alice
let alice = Value.uri("http://example.org/person/Alice")
let triples = try await store.query(subject: alice)

// 2. Find all "knows" relationships
let knows = Value.uri("http://xmlns.com/foaf/0.1/knows")
let triples = try await store.query(predicate: knows)

// 3. Find who Alice knows
let triples = try await store.query(subject: alice, predicate: knows)

// 4. Full scan (use with caution!)
let allTriples = try await store.query()
```

**Performance:**
- Exact match: O(1) lookup
- Single-bound: O(log N + M) where M = result count
- Two-bound: O(log N + M)
- Full scan: O(N) - avoid on large datasets

## Delete Operations

### Delete Single Triple

```swift
public func delete(_ triple: Triple) async throws
```

**Behavior:**
- Idempotent: Deleting non-existent triple has no effect
- Removes from all 4 indexes atomically
- Decrements triple count
- Does NOT delete dictionary entries (reused by other triples)

**Example:**
```swift
let alice = Value.uri("http://example.org/person/Alice")
let knows = Value.uri("http://xmlns.com/foaf/0.1/knows")
let bob = Value.uri("http://example.org/person/Bob")

let triple = Triple(subject: alice, predicate: knows, object: bob)
try await store.delete(triple)
```

## Utility Operations

### Count Triples

```swift
public func count() async throws -> UInt64
```

**Returns:** Total number of triples in the store.

**Example:**
```swift
let total = try await store.count()
print("Store contains \(total) triples")
```

**Performance:** O(1) - reads metadata counter

### Check Triple Existence

```swift
public func contains(_ triple: Triple) async throws -> Bool
```

**Returns:** `true` if triple exists, `false` otherwise.

**Example:**
```swift
let exists = try await store.contains(triple)
if exists {
    print("Triple is in the store")
}
```

**Performance:** O(log N) - single index lookup

## Convenience Extensions

### Querying by Subject/Predicate/Object

```swift
extension TripleStore {
    public func triplesFor(subject: Value) async throws -> [Triple] {
        return try await query(subject: subject)
    }

    public func triplesFor(predicate: Value) async throws -> [Triple] {
        return try await query(predicate: predicate)
    }

    public func triplesFor(object: Value) async throws -> [Triple] {
        return try await query(object: object)
    }
}
```

**Example:**
```swift
let alice = Value.uri("http://example.org/person/Alice")
let triples = try await store.triplesFor(subject: alice)
```

## Error Handling

### Error Types

```swift
public enum TripleError: Error, LocalizedError {
    case invalidValue(String)
    case tripleNotFound
    case dictionaryLookupFailed(value: Value)
    case transactionTooLarge
    case maxRetriesExceeded
    case internalError(String)
}
```

### Error Examples

```swift
do {
    try await store.insert(triple)
} catch TripleError.transactionTooLarge {
    print("Triple data exceeds 10MB limit")
} catch TripleError.internalError(let message) {
    print("Internal error: \(message)")
} catch {
    print("Unexpected error: \(error)")
}
```

## Usage Patterns

### Pattern 1: Knowledge Extraction System

```swift
// Extract triples from text
let extractor = KnowledgeExtractor()
let document = loadDocument()
let extractedTriples = extractor.extract(from: document)

// Store with confidence scores
for (triple, confidence) in extractedTriples {
    var enrichedTriple = triple
    enrichedTriple.metadata = Metadata(
        confidence: confidence,
        source: document.id,
        timestamp: Date()
    )
    try await store.insert(enrichedTriple)
}
```

### Pattern 2: Multi-Language Entities

```swift
let tokyo = Value.uri("http://example.org/place/Tokyo")
let label = Value.uri("http://www.w3.org/2000/01/rdf-schema#label")

let languages = [
    ("Tokyo", "en"),
    ("東京", "ja"),
    ("Tokio", "de"),
    ("Токио", "ru")
]

for (name, lang) in languages {
    let triple = Triple(
        subject: tokyo,
        predicate: label,
        object: .text(name, language: lang)
    )
    try await store.insert(triple)
}

// Query all labels
let allLabels = try await store.query(subject: tokyo, predicate: label)
// Returns 4 triples with different language tags
```

### Pattern 3: Graph Navigation

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
friendsOfFriends.subtract(friends)  // Exclude direct friends
friendsOfFriends.remove(alice)      // Exclude Alice herself
```

### Pattern 4: Bulk Import with Progress

```swift
func importDataset(triples: [Triple]) async throws {
    let batchSize = 1000
    let totalBatches = (triples.count + batchSize - 1) / batchSize

    for (index, batch) in triples.chunked(into: batchSize).enumerated() {
        try await store.insertBatch(Array(batch))
        print("Progress: \(index + 1)/\(totalBatches) batches")
    }
}
```

## Thread Safety

### Actor Isolation

`TripleStore` is an Actor, providing automatic thread safety:

```swift
// Safe to call from multiple tasks concurrently
Task {
    try await store.insert(triple1)
}
Task {
    try await store.insert(triple2)
}
```

### Shared State

Do NOT share `TripleStore` instances across processes or serialize them. Each process should create its own instance:

```swift
// ✅ Correct
let store = try await TripleStore(database: db, rootPrefix: "app")

// ❌ Incorrect
let encodedStore = try JSONEncoder().encode(store)  // Won't compile (not Codable)
```

## Performance Tips

### 1. Use Batch Inserts

```swift
// ❌ Slow (10,000 transactions)
for triple in triples {
    try await store.insert(triple)
}

// ✅ Fast (10 transactions of 1000 each)
try await store.insertBatch(triples)
```

### 2. Query with Most Specific Pattern

```swift
// ❌ Slower (full scan + filter)
let all = try await store.query()
let filtered = all.filter { $0.subject == alice }

// ✅ Faster (index lookup)
let results = try await store.query(subject: alice)
```

### 3. Reuse Value Instances

```swift
// ✅ Good (one Value instance)
let knows = Value.uri("http://xmlns.com/foaf/0.1/knows")
for person in people {
    let triple = Triple(subject: person, predicate: knows, object: friend)
    try await store.insert(triple)
}
```

### 4. Use Metadata Sparingly

Metadata increases storage size. Only include when necessary:

```swift
// For high-confidence extractions, metadata may not be needed
if confidence > 0.95 {
    try await store.insert(Triple(subject: s, predicate: p, object: o))
} else {
    try await store.insert(Triple(
        subject: s, predicate: p, object: o,
        metadata: Metadata(confidence: confidence)
    ))
}
```

## Future API Extensions

Possible additions in future versions:

### Streaming Query Results

```swift
public func queryStream(
    subject: Value?,
    predicate: Value?,
    object: Value?
) -> AsyncThrowingStream<Triple, Error>
```

### Filtered Queries

```swift
public func query(
    subject: Value?,
    predicate: Value?,
    object: Value?,
    filter: (Triple) -> Bool
) async throws -> [Triple]
```

### Transaction Blocks

```swift
public func withTransaction<T>(
    _ body: (TripleTransaction) async throws -> T
) async throws -> T
```

### Metadata Queries

```swift
public func query(
    subject: Value?,
    predicate: Value?,
    object: Value?,
    minConfidence: Double
) async throws -> [Triple]
```

## Summary

TripleLayer's API provides:

- ✅ **Simplicity**: Straightforward CRUD operations
- ✅ **Type Safety**: Compile-time checking via Swift's type system
- ✅ **Async/Await**: Modern concurrency support
- ✅ **Actor Isolation**: Thread-safe by default
- ✅ **Performance**: Optimized batch operations
- ✅ **Flexibility**: Pattern-based querying for various use cases

The API is designed for **ease of use** while providing the performance characteristics needed for production knowledge extraction systems.
