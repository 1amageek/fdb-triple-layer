# TripleLayer Implementation Plan

## Project Structure

```
fdb-triple-layer/
├── Package.swift
├── README.md
├── LICENSE
├── .gitignore
├── docs/
│   ├── ARCHITECTURE.md
│   ├── DATA_MODEL.md
│   ├── STORAGE_LAYOUT.md
│   ├── API_DESIGN.md
│   ├── PERFORMANCE.md
│   └── IMPLEMENTATION_PLAN.md (this file)
├── Sources/
│   └── TripleLayer/
│       ├── Models/
│       │   ├── Triple.swift
│       │   ├── Value.swift
│       │   ├── Metadata.swift
│       │   └── Errors.swift
│       ├── Storage/
│       │   ├── DictionaryStore.swift
│       │   ├── TripleStorage.swift
│       │   └── IndexManager.swift
│       ├── Encoding/
│       │   └── TupleHelpers.swift
│       └── TripleStore.swift
└── Tests/
    └── TripleLayerTests/
        ├── TripleStoreTests.swift
        ├── ValueTests.swift
        ├── QueryTests.swift
        ├── PerformanceTests.swift
        └── ConcurrencyTests.swift
```

## Implementation Phases

### Phase 1: Core Data Models (Week 1)

**Goal:** Define all core types and protocols

#### Tasks

1. **Models/Value.swift**
   - Define `Value` enum with all cases
   - Implement `Hashable`, `Codable`, `Sendable`
   - Add convenience initializers
   - Add string representation for debugging

2. **Models/Triple.swift**
   - Define `Triple` struct
   - Implement equality (ignoring metadata)
   - Add `CustomStringConvertible` (N-Triples format)

3. **Models/Metadata.swift**
   - Define `Metadata` struct
   - Support standard fields (confidence, source, timestamp)
   - Support custom fields (dictionary)

4. **Models/Errors.swift**
   - Define `TripleError` enum
   - Implement `LocalizedError` for user-friendly messages

**Deliverables:**
- ✅ All model types compile
- ✅ Unit tests for Value equality and encoding
- ✅ Documentation comments

**Estimated Time:** 2-3 days

---

### Phase 2: Storage Layer (Week 2)

**Goal:** Implement FoundationDB storage primitives

#### Tasks

1. **Encoding/TupleHelpers.swift**
   - Implement Value → Tuple encoding
   - Implement dictionary key encoding (v2i, i2v)
   - Implement index key encoding (SPO, PSO, POS, OSP)
   - Implement range key generation

2. **Storage/DictionaryStore.swift**
   - Actor with cache (Value → ID, ID → Value)
   - `getOrCreateID(for: Value)` method
   - `getTerm(for: UInt64)` method
   - LRU cache implementation
   - Atomic ID counter

3. **Storage/IndexManager.swift** (optional, can merge into TripleStorage)
   - Index selection logic
   - Range key building for queries

4. **Storage/TripleStorage.swift**
   - Actor managing triple CRUD
   - `insert(triple:)` method
   - `insertBatch(triples:)` method
   - `delete(triple:)` method
   - `query(subject:predicate:object:)` method
   - Triple count management

**Deliverables:**
- ✅ Storage layer compiles
- ✅ Can insert and retrieve triples from FDB
- ✅ Unit tests for encoding/decoding
- ✅ Integration tests with FoundationDB

**Estimated Time:** 5-7 days

---

### Phase 3: Public API (Week 3)

**Goal:** Complete public-facing TripleStore actor

#### Tasks

1. **TripleStore.swift**
   - Public actor wrapping TripleStorage
   - Clean API surface
   - Error handling and logging
   - Convenience methods

2. **API Documentation**
   - DocC comments for all public APIs
   - Usage examples in comments
   - Migration guide (if applicable)

3. **Integration Testing**
   - End-to-end tests
   - Batch insert tests
   - Query pattern tests
   - Error handling tests

**Deliverables:**
- ✅ Complete public API
- ✅ All tests passing
- ✅ API documentation complete

**Estimated Time:** 3-4 days

---

### Phase 4: Testing & Optimization (Week 4)

**Goal:** Comprehensive testing and performance tuning

#### Tasks

1. **Test Coverage**
   - Unit tests: >85% coverage
   - Integration tests: All major workflows
   - Concurrency tests: Race condition checks
   - Performance tests: Benchmarks

2. **Performance Optimization**
   - Profile slow operations
   - Optimize cache hit rates
   - Tune batch sizes
   - Minimize allocations

3. **Documentation**
   - README with quick start
   - Usage examples
   - Performance guidelines
   - Troubleshooting guide

**Deliverables:**
- ✅ >85% test coverage
- ✅ Performance meets targets
- ✅ Complete documentation
- ✅ Ready for production use

**Estimated Time:** 5-7 days

---

## Detailed Implementation Guide

### Step 1: Package.swift Setup

```swift
// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "fdb-triple-layer",
    platforms: [
        .macOS(.v15),
    ],
    products: [
        .library(
            name: "TripleLayer",
            targets: ["TripleLayer"]
        ),
    ],
    dependencies: [
        .package(
            url: "https://github.com/apple/swift-log.git",
            from: "1.0.0"
        ),
        .package(
            url: "https://github.com/foundationdb/fdb-swift-bindings.git",
            branch: "main"
        ),
    ],
    targets: [
        .target(
            name: "TripleLayer",
            dependencies: [
                .product(name: "FoundationDB", package: "fdb-swift-bindings"),
                .product(name: "Logging", package: "swift-log")
            ]
        ),
        .testTarget(
            name: "TripleLayerTests",
            dependencies: ["TripleLayer"]
        ),
    ],
    swiftLanguageModes: [.v6]
)
```

### Step 2: Models/Value.swift

```swift
import Foundation

public enum Value: Hashable, Codable, Sendable {
    case uri(String)
    case text(String, language: String? = nil)
    case integer(Int64)
    case float(Double)
    case boolean(Bool)
    case binary(Data)

    // Convenience computed properties
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

    public var isURI: Bool {
        if case .uri = self { return true }
        return false
    }

    public var isText: Bool {
        if case .text = self { return true }
        return false
    }
}

extension Value: CustomStringConvertible {
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
```

### Step 3: Models/Triple.swift

```swift
import Foundation

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

    // Equality ignores metadata
    public static func == (lhs: Triple, rhs: Triple) -> Bool {
        return lhs.subject == rhs.subject &&
               lhs.predicate == rhs.predicate &&
               lhs.object == rhs.object
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(subject)
        hasher.combine(predicate)
        hasher.combine(object)
    }
}

extension Triple: CustomStringConvertible {
    public var description: String {
        return "\(subject) \(predicate) \(object) ."
    }
}
```

### Step 4: Encoding/TupleHelpers.swift

```swift
import FoundationDB

enum TupleHelpers {

    // MARK: - Value Encoding

    static func encodeValue(_ value: Value) -> Tuple {
        switch value {
        case .uri(let s):
            return Tuple("uri", s)
        case .text(let s, let lang):
            return Tuple("text", s, lang ?? TupleNil())
        case .integer(let i):
            return Tuple("int", i)
        case .float(let f):
            return Tuple("float", f)
        case .boolean(let b):
            return Tuple("bool", b)
        case .binary(let d):
            // Hash large binary data
            return Tuple("bin", hashData(d))
        }
    }

    // MARK: - Dictionary Keys

    static func encodeValueToIDKey(
        rootPrefix: String,
        value: Value
    ) -> FDB.Bytes {
        let valueTuple = encodeValue(value)
        return Tuple(rootPrefix, "dict", "v2i").appending(valueTuple).encode()
    }

    static func encodeIDToValueKey(
        rootPrefix: String,
        id: UInt64
    ) -> FDB.Bytes {
        return Tuple(rootPrefix, "dict", "i2v", Int64(bitPattern: id)).encode()
    }

    static func encodeCounterKey(rootPrefix: String) -> FDB.Bytes {
        return Tuple(rootPrefix, "dict", "cnt").encode()
    }

    // MARK: - Index Keys

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

    static func encodeRangeKeys(
        rootPrefix: String,
        indexType: String,
        id1: UInt64?,
        id2: UInt64?,
        id3: UInt64?
    ) -> (beginKey: FDB.Bytes, endKey: FDB.Bytes) {
        // Build prefix with bound IDs
        var prefix = Tuple(rootPrefix, "idx", indexType)

        if let id1 = id1 {
            prefix = prefix.appending(Int64(bitPattern: id1))
            if let id2 = id2 {
                prefix = prefix.appending(Int64(bitPattern: id2))
                if let id3 = id3 {
                    prefix = prefix.appending(Int64(bitPattern: id3))
                }
            }
        }

        let beginKey = prefix.encode()
        let endKey = prefix.encode() + [0xFF]

        return (beginKey, endKey)
    }

    // MARK: - Helpers

    private static func hashData(_ data: Data) -> Int64 {
        var hasher = Hasher()
        hasher.combine(data)
        return Int64(truncatingIfNeeded: hasher.finalize())
    }
}
```

## Testing Strategy

### Unit Tests

**Test Coverage Areas:**
1. Value equality and hashing
2. Triple equality (metadata ignored)
3. Tuple encoding correctness
4. Dictionary Store ID allocation
5. Index key generation

### Integration Tests

**Test Scenarios:**
1. Insert and retrieve single triple
2. Batch insert 10,000 triples
3. Query all patterns (7 patterns)
4. Delete triples
5. Count accuracy

### Performance Tests

**Benchmarks:**
1. Insert throughput (triples/sec)
2. Query latency (ms)
3. Memory usage
4. Cache hit rates

### Concurrency Tests

**Race Conditions:**
1. Concurrent inserts to same triple
2. Concurrent queries during inserts
3. Actor isolation verification

## Development Workflow

### 1. Setup

```bash
cd /Users/1amageek/Desktop/fdb-triple-layer
swift package resolve
swift build
```

### 2. Run Tests

```bash
swift test
```

### 3. Generate Documentation

```bash
swift package generate-documentation
```

### 4. Performance Profiling

```bash
swift test --filter PerformanceTests
```

## Milestones

| Milestone | Deliverable | Target Date |
|-----------|-------------|-------------|
| M1: Models Complete | All model types implemented | Week 1 |
| M2: Storage Layer | TripleStorage functional | Week 2 |
| M3: Public API | TripleStore complete | Week 3 |
| M4: Production Ready | Tests + docs complete | Week 4 |

## Dependencies

### External

- **FoundationDB**: Database backend
- **fdb-swift-bindings**: Swift bindings for FDB
- **swift-log**: Logging framework

### System Requirements

- macOS 15.0+
- Swift 6.0+
- FoundationDB 7.1.0+

## Risks and Mitigation

| Risk | Impact | Mitigation |
|------|--------|------------|
| FDB version compatibility | High | Pin to specific FDB version |
| Performance targets not met | Medium | Early benchmarking, profiling |
| Complex query optimization | Low | Start with simple index selection |
| Cache memory usage | Medium | Implement LRU with configurable size |

## Success Criteria

- ✅ All tests pass (>85% coverage)
- ✅ Performance targets met
- ✅ Documentation complete
- ✅ Zero memory leaks
- ✅ Thread-safe (Actor model)
- ✅ Production-ready error handling

## Next Steps After Implementation

1. **Benchmarking**: Compare with other triple stores
2. **Optimization**: Profile and optimize hot paths
3. **Advanced Features**: Streaming queries, transactions
4. **Integration Examples**: Sample apps using TripleLayer
5. **Production Deployment**: Deploy in knowledge extraction pipeline

## Summary

This implementation plan provides:

- ✅ **Clear structure**: Organized file layout
- ✅ **Phased approach**: 4-week timeline
- ✅ **Detailed tasks**: Step-by-step implementation
- ✅ **Testing strategy**: Comprehensive test coverage
- ✅ **Risk mitigation**: Identified risks and solutions

Follow this plan to build a production-ready, high-performance triple store optimized for knowledge extraction systems.
