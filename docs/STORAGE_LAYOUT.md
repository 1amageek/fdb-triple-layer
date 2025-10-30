# TripleLayer Storage Layout

## FoundationDB Key Structure

TripleLayer uses FoundationDB's Tuple encoding to create structured, sortable keys that enable efficient range queries.

## Key Spaces

All keys use a `rootPrefix` to isolate different applications/tenants.

```
<rootPrefix>:
  ├─ dict/         # Dictionary Store (Value ↔ ID mappings)
  ├─ idx/          # Triple Indexes (SPO, PSO, POS, OSP)
  └─ meta/         # Metadata (counters, configuration)
```

### 1. Dictionary Store Keys

**Purpose**: Bidirectional mapping between `Value` instances and numeric IDs (UInt64).

#### Value → ID Mapping

```
Key:   Tuple(rootPrefix, "dict", "v2i", <value_type>, <value_data>)
Value: UInt64 (8 bytes, little-endian)
```

**Examples:**

```swift
// URI
Tuple("myapp", "dict", "v2i", "uri", "http://example.org/Alice") → 1

// Plain text
Tuple("myapp", "dict", "v2i", "text", "Alice Smith", TupleNil) → 2

// Language-tagged text
Tuple("myapp", "dict", "v2i", "text", "東京", "ja") → 3

// Integer
Tuple("myapp", "dict", "v2i", "int", 42) → 4

// Float
Tuple("myapp", "dict", "v2i", "float", 3.14) → 5

// Boolean
Tuple("myapp", "dict", "v2i", "bool", true) → 6

// Binary
Tuple("myapp", "dict", "v2i", "bin", <hash(data)>) → 7
```

**Value Type Encoding:**

| Value Type | Tuple Components |
|------------|------------------|
| `.uri(s)` | `("uri", s)` |
| `.text(s, nil)` | `("text", s, TupleNil)` |
| `.text(s, lang)` | `("text", s, lang)` |
| `.integer(i)` | `("int", i)` |
| `.float(f)` | `("float", f)` |
| `.boolean(b)` | `("bool", b)` |
| `.binary(d)` | `("bin", hash(d))` |

#### ID → Value Mapping

```
Key:   Tuple(rootPrefix, "dict", "i2v", UInt64_as_Int64)
Value: JSON-encoded Value
```

**Example:**
```
Tuple("myapp", "dict", "i2v", 1) → {"uri": "http://example.org/Alice"}
Tuple("myapp", "dict", "i2v", 2) → {"text": "Alice Smith"}
Tuple("myapp", "dict", "i2v", 3) → {"text": "東京", "language": "ja"}
```

**Why JSON?**
- Flexible: Supports all Value types
- Human-readable: Easy debugging
- Compact: Smaller than some binary formats for small values

#### ID Counter

```
Key:   Tuple(rootPrefix, "dict", "cnt")
Value: UInt64 (8 bytes, little-endian)
```

Atomically incremented when allocating new IDs.

### 2. Triple Index Keys

**Purpose**: Four indexes for optimal query performance on different patterns.

**General Structure:**
```
Key:   Tuple(rootPrefix, "idx", <index_name>, <id1>, <id2>, <id3>)
Value: Empty (existence indicates triple presence)
```

#### SPO Index (Subject-Predicate-Object)

```
Key:   Tuple(rootPrefix, "idx", "spo", subject_id, predicate_id, object_id)
Value: Empty
```

**Optimized for:**
- `(S, ?, ?)` - All triples for a subject
- `(S, P, ?)` - All objects for subject+predicate
- `(S, P, O)` - Exact triple lookup

**Example:**
```
Tuple("myapp", "idx", "spo", 1, 2, 3) → []
```

#### PSO Index (Predicate-Subject-Object)

```
Key:   Tuple(rootPrefix, "idx", "pso", predicate_id, subject_id, object_id)
Value: Empty
```

**Optimized for:**
- `(?, P, ?)` - All triples with a predicate (predicate scan)
- `(?, P, O)` - All subjects for predicate+object

**Example:**
```
Tuple("myapp", "idx", "pso", 2, 1, 3) → []
```

#### POS Index (Predicate-Object-Subject)

```
Key:   Tuple(rootPrefix, "idx", "pos", predicate_id, object_id, subject_id)
Value: Empty
```

**Optimized for:**
- `(?, P, O)` - All subjects for predicate+object (most efficient)

**Example:**
```
Tuple("myapp", "idx", "pos", 2, 3, 1) → []
```

#### OSP Index (Object-Subject-Predicate)

```
Key:   Tuple(rootPrefix, "idx", "osp", object_id, subject_id, predicate_id)
Value: Empty
```

**Optimized for:**
- `(?, ?, O)` - All triples with an object (reverse lookup)

**Example:**
```
Tuple("myapp", "idx", "osp", 3, 1, 2) → []
```

### 3. Metadata Keys

#### Triple Count

```
Key:   Tuple(rootPrefix, "meta", "cnt")
Value: UInt64 (8 bytes, little-endian)
```

Tracks total number of triples. Atomically updated on insert/delete.

#### Schema Version

```
Key:   Tuple(rootPrefix, "meta", "ver")
Value: UTF-8 string (e.g., "1.0")
```

Enables future schema migrations.

## Range Query Patterns

### Example: Query all triples for subject ID 1

```swift
// Pattern: (1, ?, ?)
// Use SPO index

let beginKey = Tuple("myapp", "idx", "spo", 1).encode()
let endKey = Tuple("myapp", "idx", "spo", 1).encode() + [0xFF]

// Scan range [beginKey, endKey)
// Results:
//   Tuple("myapp", "idx", "spo", 1, 2, 3)
//   Tuple("myapp", "idx", "spo", 1, 5, 10)
//   Tuple("myapp", "idx", "spo", 1, 7, 15)
//   ...
```

### Example: Query all triples with predicate ID 2

```swift
// Pattern: (?, 2, ?)
// Use PSO index

let beginKey = Tuple("myapp", "idx", "pso", 2).encode()
let endKey = Tuple("myapp", "idx", "pso", 2).encode() + [0xFF]

// Scan range [beginKey, endKey)
// Results:
//   Tuple("myapp", "idx", "pso", 2, 1, 3)
//   Tuple("myapp", "idx", "pso", 2, 4, 8)
//   Tuple("myapp", "idx", "pso", 2, 6, 12)
//   ...
```

## Space Efficiency

### Per-Triple Storage

For a single triple with IDs (1, 2, 3):

**Indexes (4 × index):**
```
SPO: ~40 bytes (prefix + 3 IDs + overhead)
PSO: ~40 bytes
POS: ~40 bytes
OSP: ~40 bytes
---
Total: ~160 bytes
```

**Dictionary (amortized across all triples):**
```
3 unique values × 2 (bidirectional) = 6 dictionary entries
Average: ~50 bytes per entry × 6 = ~300 bytes

For 1000 triples reusing values:
Dictionary: ~1800 entries × 50 bytes = 90 KB
Per triple: ~90 bytes
```

**Total per triple: ~250 bytes** (with moderate value reuse)

### Optimizations

1. **Value Deduplication**: Shared IDs for repeated values
2. **Empty Index Values**: No redundant data in index values
3. **Tuple Encoding**: Compact binary representation
4. **Compression**: FoundationDB compresses data at rest

## Transaction Patterns

### Insert Triple

```
1. Check if value IDs exist in dictionary
   - If not, allocate new IDs (atomic increment)
   - Write value→ID and ID→value mappings

2. Check if triple exists (SPO index lookup)
   - If exists, return early

3. Write to all 4 indexes:
   - SPO: write key
   - PSO: write key
   - POS: write key
   - OSP: write key

4. Atomically increment triple count

All in one transaction (atomic, consistent)
```

### Delete Triple

```
1. Lookup value IDs in dictionary
   - If any ID not found, return early (triple doesn't exist)

2. Check if triple exists (SPO index lookup)
   - If not exists, return early

3. Delete from all 4 indexes:
   - SPO: clear key
   - PSO: clear key
   - POS: clear key
   - OSP: clear key

4. Atomically decrement triple count

Note: Dictionary entries are NOT deleted (intentional - reused by other triples)
```

### Query Triples

```
1. Convert bound Values to IDs (dictionary lookup)
   - If any ID not found, return empty results

2. Select optimal index based on pattern

3. Build range keys (begin, end)

4. Stream results via getRange:
   - Decode (id1, id2, id3) from each key
   - Convert IDs back to Values (dictionary lookup)
   - Construct Triple objects

5. Return results
```

## Caching Strategy

### Dictionary Cache (In-Memory)

- **Value → ID cache**: LRU, max 10,000 entries
- **ID → Value cache**: LRU, max 10,000 entries
- **Hit rate target**: >90% for typical workloads

**Cache Invalidation:**
- Never required (values are immutable once assigned an ID)
- New values added during transaction are immediately cached

## Performance Characteristics

### Read Operations

| Operation | FDB Reads | Notes |
|-----------|-----------|-------|
| Insert (new values) | 3 (check) + 3 (dict) | Worst case |
| Insert (cached) | 1 (check) | Best case |
| Query exact | 1 (index) + 3 (dict) | With cache hits: 1 read |
| Query range (N results) | N (scan) + 3N (dict) | With cache: N reads |
| Delete | 1 (check) + 3 (dict) | With cache: 1 read |

### Write Operations

| Operation | FDB Writes | Notes |
|-----------|------------|-------|
| Insert (new values) | 6 (dict) + 4 (indexes) + 1 (count) = 11 | Worst case |
| Insert (existing values) | 4 (indexes) + 1 (count) = 5 | Best case |
| Delete | 4 (indexes) + 1 (count) = 5 | Dict not deleted |

### Transaction Size

**Limits:**
- Max transaction size: 10 MB
- Max key size: 10 KB
- Max value size: 100 KB

**Typical triple transaction:**
- ~200-300 bytes per triple (with indexes)
- Can batch ~30,000 triples per transaction (safe estimate)

## Migration and Versioning

### Schema Version

Current version: `1.0`

Stored in:
```
Tuple(rootPrefix, "meta", "ver") → "1.0"
```

### Future Migrations

If schema changes are needed:

1. Check version on startup
2. If version < current, run migration
3. Update version metadata

Example migration (if adding new index):
```swift
if currentVersion < "2.0" {
    // Build new index from existing triples
    migrateToVersion2()
    setVersion("2.0")
}
```

## Summary

TripleLayer's storage layout provides:

- ✅ **Efficient encoding**: Tuple-based, compact binary
- ✅ **Multiple indexes**: 4 indexes cover all query patterns
- ✅ **Value deduplication**: Shared IDs reduce storage
- ✅ **Atomic operations**: All mutations in single transaction
- ✅ **Scalability**: Leverages FoundationDB distribution
- ✅ **Debuggability**: Human-readable with `fdbcli`

The design is optimized for **read-heavy workloads** with good write performance, making it ideal for knowledge extraction systems that import data in bulk and query frequently.
