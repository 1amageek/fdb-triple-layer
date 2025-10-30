import Foundation
@preconcurrency import FoundationDB
import Logging

/// Public API for the Triple Store
///
/// This actor provides a thread-safe interface for inserting, deleting,
/// and querying triples stored in FoundationDB.
///
/// ## Example Usage
///
/// ```swift
/// // Initialize FoundationDB
/// try await FDBClient.initialize()
/// let database = try FDBClient.openDatabase()
///
/// // Create triple store
/// let store = try await TripleStore(database: database, rootPrefix: "myapp")
///
/// // Insert a triple
/// let alice = Value.uri("http://example.org/person/Alice")
/// let knows = Value.uri("http://xmlns.com/foaf/0.1/knows")
/// let bob = Value.uri("http://example.org/person/Bob")
///
/// let triple = Triple(subject: alice, predicate: knows, object: bob)
/// try await store.insert(triple)
///
/// // Query triples
/// let results = try await store.query(subject: alice)
/// for triple in results {
///     print(triple)
/// }
/// ```
public actor TripleStore {

    // MARK: - Properties

    private let storage: TripleStorage
    private let logger: Logger

    /// The root prefix for all keys in FoundationDB
    public let rootPrefix: String

    // MARK: - Initialization

    /// Creates a new triple store
    ///
    /// - Parameters:
    ///   - database: The FoundationDB database instance
    ///   - rootPrefix: A unique prefix for this store's keys (e.g., "myapp", "prod")
    ///   - logger: Optional custom logger
    public init(
        database: any DatabaseProtocol,
        rootPrefix: String,
        logger: Logger? = nil
    ) {
        self.rootPrefix = rootPrefix
        self.logger = logger ?? Logger(label: "com.triplelayer.store")
        self.storage = TripleStorage(
            database: database,
            rootPrefix: rootPrefix,
            logger: self.logger
        )

        self.logger.info("TripleStore initialized with prefix: \(rootPrefix)")
    }

    // MARK: - Public API

    /// Inserts a triple into the store
    ///
    /// If the triple already exists, this operation is idempotent and will not fail.
    ///
    /// - Parameter triple: The triple to insert
    /// - Throws: `TripleError` if the operation fails
    public func insert(_ triple: Triple) async throws {
        logger.info("Inserting triple", metadata: [
            "subject": "\(triple.subject)",
            "predicate": "\(triple.predicate)",
            "object": "\(triple.object)"
        ])
        try await storage.insert(triple)
    }

    /// Inserts multiple triples in batches
    ///
    /// This method automatically batches the inserts to respect FoundationDB's
    /// 10MB transaction limit. Each batch is processed in a single transaction
    /// for optimal performance (50-100x faster than individual inserts).
    ///
    /// - Parameter triples: The triples to insert
    /// - Throws: `TripleError` if any operation fails
    public func insertBatch(_ triples: [Triple]) async throws {
        logger.info("Inserting batch of triples", metadata: [
            "count": "\(triples.count)"
        ])

        // Insert in batches of 1000 to avoid transaction size limits
        let batchSize = 1000

        for batchIndex in stride(from: 0, to: triples.count, by: batchSize) {
            let endIndex = min(batchIndex + batchSize, triples.count)
            let batch = Array(triples[batchIndex..<endIndex])

            // Use the batch insert method which uses a single transaction
            try await storage.insertBatch(batch)

            logger.debug("Inserted batch", metadata: [
                "batch_number": "\(batchIndex/batchSize + 1)",
                "batch_size": "\(batch.count)"
            ])
        }

        logger.info("Batch insert complete", metadata: [
            "total_count": "\(triples.count)"
        ])
    }

    /// Deletes a triple from the store
    ///
    /// If the triple does not exist, this operation is idempotent and will not fail.
    ///
    /// - Parameter triple: The triple to delete
    /// - Throws: `TripleError` if the operation fails
    public func delete(_ triple: Triple) async throws {
        logger.info("Deleting triple", metadata: [
            "subject": "\(triple.subject)",
            "predicate": "\(triple.predicate)",
            "object": "\(triple.object)"
        ])
        try await storage.delete(triple)
    }

    /// Queries triples matching the given pattern
    ///
    /// Use `nil` for any component to match all values (wildcard).
    ///
    /// ## Query Patterns
    ///
    /// - `(S, ?, ?)` - All triples about a subject
    /// - `(?, P, ?)` - All triples with a predicate
    /// - `(?, ?, O)` - All triples pointing to an object
    /// - `(S, P, ?)` - Subject and predicate bound
    /// - `(?, P, O)` - Predicate and object bound
    /// - `(S, ?, O)` - Subject and object bound
    /// - `(?, ?, ?)` - Full scan (use with caution!)
    ///
    /// - Parameters:
    ///   - subject: The subject value to match, or nil to match all
    ///   - predicate: The predicate value to match, or nil to match all
    ///   - object: The object value to match, or nil to match all
    /// - Returns: An array of matching triples
    /// - Throws: `TripleError` if the operation fails
    public func query(
        subject: Value? = nil,
        predicate: Value? = nil,
        object: Value? = nil
    ) async throws -> [Triple] {
        logger.info("Querying triples", metadata: [
            "subject": "\(subject?.description ?? "?")",
            "predicate": "\(predicate?.description ?? "?")",
            "object": "\(object?.description ?? "?")"
        ])
        let results = try await storage.query(
            subject: subject,
            predicate: predicate,
            object: object
        )
        logger.info("Query returned results", metadata: [
            "count": "\(results.count)"
        ])
        return results
    }

    /// Returns the total number of triples in the store
    ///
    /// - Returns: The count of triples
    /// - Throws: `TripleError` if the operation fails
    public func count() async throws -> UInt64 {
        let count = try await storage.count()
        logger.debug("Retrieved triple count", metadata: [
            "count": "\(count)"
        ])
        return count
    }

    /// Checks if a specific triple exists in the store
    ///
    /// This method is optimized for existence checking and does not fetch the full triple data.
    ///
    /// - Parameter triple: The triple to check
    /// - Returns: `true` if the triple exists, `false` otherwise
    /// - Throws: `TripleError` if the operation fails
    public func contains(_ triple: Triple) async throws -> Bool {
        return try await storage.exists(triple)
    }
}

// MARK: - Convenience Extensions

extension TripleStore {
    /// Queries all triples (full scan)
    ///
    /// **Warning:** This can be expensive for large datasets. Consider using
    /// pattern-based queries instead.
    ///
    /// - Returns: All triples in the store
    public func all() async throws -> [Triple] {
        return try await query(subject: nil, predicate: nil, object: nil)
    }

    /// Queries all triples for a given subject
    ///
    /// - Parameter subject: The subject value
    /// - Returns: All triples with the given subject
    public func triplesFor(subject: Value) async throws -> [Triple] {
        return try await query(subject: subject, predicate: nil, object: nil)
    }

    /// Queries all triples for a given predicate
    ///
    /// - Parameter predicate: The predicate value
    /// - Returns: All triples with the given predicate
    public func triplesFor(predicate: Value) async throws -> [Triple] {
        return try await query(subject: nil, predicate: predicate, object: nil)
    }

    /// Queries all triples for a given object
    ///
    /// - Parameter object: The object value
    /// - Returns: All triples with the given object
    public func triplesFor(object: Value) async throws -> [Triple] {
        return try await query(subject: nil, predicate: nil, object: object)
    }
}
