import Foundation
@preconcurrency import FoundationDB
import Logging
import Synchronization

/// Class responsible for managing bidirectional Value ↔ ID mappings
///
/// DictionaryStore provides:
/// - Atomic ID allocation using a counter
/// - Bidirectional lookups (Value → ID and ID → Value)
/// - In-memory LRU cache for performance
/// - Thread-safe access via Mutex
///
/// Thread safety is provided by:
/// - Swift Synchronization.Mutex for cache access (~1μs overhead vs ~10μs for actor)
/// - FoundationDB transaction model for database operations
final class DictionaryStore: Sendable {

    // MARK: - Properties

    private nonisolated(unsafe) let db: any DatabaseProtocol
    private let rootPrefix: String
    private let logger: Logger

    /// Cache state protected by Mutex
    private struct CacheState {
        var valueToIdCache: [Value: UInt64] = [:]
        var idToValueCache: [UInt64: Value] = [:]
    }

    /// Maximum cache size (LRU eviction when exceeded)
    private let maxCacheSize: Int

    /// Mutex-protected cache state
    private let cache: Mutex<CacheState>

    // MARK: - Initialization

    init(
        database: any DatabaseProtocol,
        rootPrefix: String,
        maxCacheSize: Int = 10_000,
        logger: Logger? = nil
    ) {
        self.db = database
        self.rootPrefix = rootPrefix
        self.maxCacheSize = maxCacheSize
        self.logger = logger ?? Logger(label: "com.triplelayer.dictionarystore")
        self.cache = Mutex(CacheState())
    }

    // MARK: - Public API

    /// Gets an existing ID for a value, or returns nil if not found
    func getExistingID(for value: Value, transaction: any TransactionProtocol) async throws -> UInt64? {
        // Check cache first (with Mutex)
        let cachedID = cache.withLock { $0.valueToIdCache[value] }

        if let id = cachedID {
            logger.trace("Cache hit for value → ID: \(value)")
            return id
        }

        // Lookup in database
        let key = try TupleHelpers.encodeValueToIDKey(rootPrefix: rootPrefix, value: value)
        guard let bytes = try await transaction.getValue(for: key) else {
            return nil
        }

        let id = TupleHelpers.decodeUInt64(bytes)

        // Update cache (with Mutex)
        updateCache(value: value, id: id)

        return id
    }

    /// Gets or creates an ID for a value
    func getOrCreateID(for value: Value, transaction: any TransactionProtocol) async throws -> UInt64 {
        // Check cache first (with Mutex)
        let cachedID = cache.withLock { $0.valueToIdCache[value] }

        if let id = cachedID {
            logger.trace("Cache hit for value → ID: \(value)")
            return id
        }

        // Check if ID already exists in database
        let valueKey = try TupleHelpers.encodeValueToIDKey(rootPrefix: rootPrefix, value: value)

        if let idBytes = try await transaction.getValue(for: valueKey) {
            let id = TupleHelpers.decodeUInt64(idBytes)

            // Update cache (with Mutex)
            updateCache(value: value, id: id)

            return id
        }

        // Generate new ID using atomic counter
        let counterKey = TupleHelpers.encodeCounterKey(rootPrefix: rootPrefix)

        // Initialize counter if it doesn't exist
        if try await transaction.getValue(for: counterKey) == nil {
            let initialValue = TupleHelpers.encodeUInt64(0)
            transaction.setValue(initialValue, for: counterKey)
        }

        // Atomic increment
        let increment = TupleHelpers.encodeUInt64(1)
        transaction.atomicOp(key: counterKey, param: increment, mutationType: .add)

        // Read the new ID (read-your-writes guarantee)
        guard let newIDBytes = try await transaction.getValue(for: counterKey) else {
            throw TripleError.internalError("Failed to read counter after atomic increment")
        }
        let newID = TupleHelpers.decodeUInt64(newIDBytes)

        // Store both mappings: Value → ID and ID → Value
        let idBytes = TupleHelpers.encodeUInt64(newID)
        transaction.setValue(idBytes, for: valueKey)

        let idKey = TupleHelpers.encodeIDToValueKey(rootPrefix: rootPrefix, id: newID)
        let valueData = try encodeValue(value)
        transaction.setValue(valueData, for: idKey)

        // Update cache (with Mutex)
        updateCache(value: value, id: newID)

        logger.debug("Created new ID \(newID) for value: \(value)")
        return newID
    }

    /// Gets the value for an ID
    func getValue(for id: UInt64, transaction: any TransactionProtocol) async throws -> Value {
        // Check cache first (with Mutex)
        let cachedValue = cache.withLock { $0.idToValueCache[id] }

        if let value = cachedValue {
            logger.trace("Cache hit for ID → value: \(id)")
            return value
        }

        // Lookup in database
        let key = TupleHelpers.encodeIDToValueKey(rootPrefix: rootPrefix, id: id)
        guard let bytes = try await transaction.getValue(for: key) else {
            throw TripleError.dictionaryLookupFailed(value: .integer(Int64(id)))
        }

        let value = try decodeValue(bytes)

        // Update cache (with Mutex)
        updateCache(value: value, id: id)

        return value
    }

    // MARK: - Cache Management

    private func updateCache(value: Value, id: UInt64) {
        cache.withLock { state in
            // Simple cache management: if over limit, clear some entries
            if state.valueToIdCache.count >= maxCacheSize {
                // Remove oldest ~10% of entries (simple strategy)
                let toRemove = maxCacheSize / 10
                let keysToRemove = Array(state.valueToIdCache.keys.prefix(toRemove))
                for key in keysToRemove {
                    if let idToRemove = state.valueToIdCache[key] {
                        state.idToValueCache.removeValue(forKey: idToRemove)
                    }
                    state.valueToIdCache.removeValue(forKey: key)
                }
                logger.debug("Cache evicted \(toRemove) entries")
            }

            state.valueToIdCache[value] = id
            state.idToValueCache[id] = value
        }
    }

    /// Clears all cached entries
    func clearCache() {
        cache.withLock { state in
            state.valueToIdCache.removeAll()
            state.idToValueCache.removeAll()
        }
        logger.debug("Cache cleared")
    }

    // MARK: - Encoding/Decoding

    private func encodeValue(_ value: Value) throws -> FDB.Bytes {
        let encoder = JSONEncoder()
        return try [UInt8](encoder.encode(value))
    }

    private func decodeValue(_ bytes: FDB.Bytes) throws -> Value {
        let decoder = JSONDecoder()
        return try decoder.decode(Value.self, from: Data(bytes))
    }
}
