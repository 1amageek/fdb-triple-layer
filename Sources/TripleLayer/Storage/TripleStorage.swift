import Foundation
@preconcurrency import FoundationDB
import Logging

/// Actor responsible for managing triple storage with 4 indexes
///
/// TripleStorage coordinates:
/// - Converting Values to IDs via DictionaryStore
/// - Maintaining 4 indexes (SPO, PSO, POS, OSP) for optimal queries
/// - Managing triple count metadata
/// - Ensuring ACID properties through FoundationDB transactions
actor TripleStorage {

    // MARK: - Properties

    private nonisolated(unsafe) let db: any DatabaseProtocol
    private let rootPrefix: String
    private let logger: Logger
    private let dictionaryStore: DictionaryStore

    /// The four enabled indexes
    private let enabledIndexes: [String] = ["spo", "pso", "pos", "osp"]

    // MARK: - Initialization

    init(
        database: any DatabaseProtocol,
        rootPrefix: String,
        logger: Logger? = nil
    ) {
        self.db = database
        self.rootPrefix = rootPrefix
        self.logger = logger ?? Logger(label: "com.triplelayer.storage")
        self.dictionaryStore = DictionaryStore(
            database: database,
            rootPrefix: rootPrefix,
            logger: logger
        )
    }

    // MARK: - Insert Operations

    /// Inserts a single triple into the store
    func insert(_ triple: Triple) async throws {
        logger.debug("Inserting triple: \(triple)")

        try await db.withTransaction { transaction in
            // 1. Convert Values to IDs
            let subjectID = try await self.dictionaryStore.getOrCreateID(
                for: triple.subject,
                transaction: transaction
            )
            let predicateID = try await self.dictionaryStore.getOrCreateID(
                for: triple.predicate,
                transaction: transaction
            )
            let objectID = try await self.dictionaryStore.getOrCreateID(
                for: triple.object,
                transaction: transaction
            )

            // 2. Check if triple already exists (using SPO index)
            let spoKey = TupleHelpers.encodeTripleKey(
                rootPrefix: self.rootPrefix,
                indexType: "spo",
                id1: subjectID,
                id2: predicateID,
                id3: objectID
            )

            if let _ = try await transaction.getValue(for: spoKey) {
                // Triple already exists, nothing to do
                self.logger.debug("Triple already exists, skipping")
                return
            }

            // 3. Insert into all 4 indexes
            for indexType in self.enabledIndexes {
                let key = self.encodeIndexKey(
                    indexType: indexType,
                    subjectID: subjectID,
                    predicateID: predicateID,
                    objectID: objectID
                )
                // Empty value (existence indicates triple is present)
                transaction.setValue(FDB.Bytes(), for: key)
            }

            // 4. Increment triple count
            let countKey = TupleHelpers.encodeTripleCountKey(rootPrefix: self.rootPrefix)
            let increment = TupleHelpers.encodeUInt64(1)
            transaction.atomicOp(key: countKey, param: increment, mutationType: .add)

            self.logger.debug("Triple inserted successfully")
        }
    }

    /// Inserts multiple triples in a single transaction (more efficient)
    func insertBatch(_ triples: [Triple]) async throws {
        logger.debug("Inserting batch of \(triples.count) triples")

        try await db.withTransaction { transaction in
            var insertedCount: UInt64 = 0

            for triple in triples {
                // 1. Convert Values to IDs
                let subjectID = try await self.dictionaryStore.getOrCreateID(
                    for: triple.subject,
                    transaction: transaction
                )
                let predicateID = try await self.dictionaryStore.getOrCreateID(
                    for: triple.predicate,
                    transaction: transaction
                )
                let objectID = try await self.dictionaryStore.getOrCreateID(
                    for: triple.object,
                    transaction: transaction
                )

                // 2. Check if triple already exists
                let spoKey = TupleHelpers.encodeTripleKey(
                    rootPrefix: self.rootPrefix,
                    indexType: "spo",
                    id1: subjectID,
                    id2: predicateID,
                    id3: objectID
                )

                if let _ = try await transaction.getValue(for: spoKey) {
                    // Triple already exists, skip to next
                    self.logger.trace("Triple already exists, skipping: \(triple)")
                    continue
                }

                // 3. Insert into all 4 indexes
                for indexType in self.enabledIndexes {
                    let key = self.encodeIndexKey(
                        indexType: indexType,
                        subjectID: subjectID,
                        predicateID: predicateID,
                        objectID: objectID
                    )
                    transaction.setValue(FDB.Bytes(), for: key)
                }

                insertedCount += 1
            }

            // 4. Increment triple count by the number of actually inserted triples
            if insertedCount > 0 {
                let countKey = TupleHelpers.encodeTripleCountKey(rootPrefix: self.rootPrefix)
                let increment = TupleHelpers.encodeUInt64(insertedCount)
                transaction.atomicOp(key: countKey, param: increment, mutationType: .add)
                self.logger.debug("Batch inserted \(insertedCount) new triples")
            } else {
                self.logger.debug("No new triples inserted (all existed)")
            }
        }
    }

    // MARK: - Delete Operations

    /// Deletes a triple from the store
    func delete(_ triple: Triple) async throws {
        logger.debug("Deleting triple: \(triple)")

        try await db.withTransaction { transaction in
            // 1. Convert Values to IDs (must exist)
            guard let subjectID = try await self.dictionaryStore.getExistingID(
                for: triple.subject,
                transaction: transaction
            ),
            let predicateID = try await self.dictionaryStore.getExistingID(
                for: triple.predicate,
                transaction: transaction
            ),
            let objectID = try await self.dictionaryStore.getExistingID(
                for: triple.object,
                transaction: transaction
            ) else {
                self.logger.debug("Triple does not exist, skipping")
                return
            }

            // 2. Check if triple exists (using SPO index)
            let spoKey = TupleHelpers.encodeTripleKey(
                rootPrefix: self.rootPrefix,
                indexType: "spo",
                id1: subjectID,
                id2: predicateID,
                id3: objectID
            )

            guard let _ = try await transaction.getValue(for: spoKey) else {
                self.logger.debug("Triple does not exist, skipping")
                return
            }

            // 3. Delete from all 4 indexes
            for indexType in self.enabledIndexes {
                let key = self.encodeIndexKey(
                    indexType: indexType,
                    subjectID: subjectID,
                    predicateID: predicateID,
                    objectID: objectID
                )
                transaction.clear(key: key)
            }

            // 4. Decrement triple count
            let countKey = TupleHelpers.encodeTripleCountKey(rootPrefix: self.rootPrefix)
            let decrementValue = UInt64(bitPattern: Int64(-1))
            let decrement = TupleHelpers.encodeUInt64(decrementValue)
            transaction.atomicOp(key: countKey, param: decrement, mutationType: .add)

            self.logger.debug("Triple deleted successfully")
        }
    }

    // MARK: - Query Operations

    /// Queries triples matching the given pattern
    func query(
        subject: Value?,
        predicate: Value?,
        object: Value?
    ) async throws -> [Triple] {
        logger.debug("Querying: s=\(subject?.description ?? "?"), p=\(predicate?.description ?? "?"), o=\(object?.description ?? "?")")

        return try await db.withTransaction { transaction in
            // 1. Convert bound Values to IDs
            let subjectID = try await subject.asyncMap {
                try await self.dictionaryStore.getExistingID(for: $0, transaction: transaction)
            }
            let predicateID = try await predicate.asyncMap {
                try await self.dictionaryStore.getExistingID(for: $0, transaction: transaction)
            }
            let objectID = try await object.asyncMap {
                try await self.dictionaryStore.getExistingID(for: $0, transaction: transaction)
            }

            // If any bound Value doesn't exist, return empty results
            if (subject != nil && subjectID == nil) ||
               (predicate != nil && predicateID == nil) ||
               (object != nil && objectID == nil) {
                self.logger.debug("One or more Values not found, returning empty results")
                return []
            }

            // 2. Select optimal index
            let indexType = self.selectOptimalIndex(
                subjectBound: subject != nil,
                predicateBound: predicate != nil,
                objectBound: object != nil
            )
            self.logger.debug("Using index: \(indexType)")

            // 3. Build range keys
            let (beginKey, endKey) = self.buildRangeKeys(
                indexType: indexType,
                subjectID: subjectID,
                predicateID: predicateID,
                objectID: objectID
            )

            // 4. Scan the range
            var results: [Triple] = []

            let sequence = transaction.getRange(
                beginSelector: .firstGreaterOrEqual(beginKey),
                endSelector: .firstGreaterThan(endKey),
                snapshot: true  // Read-only query
            )

            for try await (key, _) in sequence {
                // Decode the key to get IDs
                let (sID, pID, oID) = try self.decodeIndexKey(
                    key: key,
                    indexType: indexType
                )

                // Apply post-scan filtering for patterns not fully covered by the index
                // This handles cases like (S, ?, O) where index only covers S
                if let reqSubjectID = subjectID, sID != reqSubjectID {
                    continue
                }
                if let reqPredicateID = predicateID, pID != reqPredicateID {
                    continue
                }
                if let reqObjectID = objectID, oID != reqObjectID {
                    continue
                }

                // Convert IDs back to Values
                let sValue = try await self.dictionaryStore.getValue(for: sID, transaction: transaction)
                let pValue = try await self.dictionaryStore.getValue(for: pID, transaction: transaction)
                let oValue = try await self.dictionaryStore.getValue(for: oID, transaction: transaction)

                let triple = Triple(
                    subject: sValue,
                    predicate: pValue,
                    object: oValue
                )
                results.append(triple)
            }

            self.logger.debug("Query returned \(results.count) triples")
            return results
        }
    }

    /// Returns the total number of triples in the store
    func count() async throws -> UInt64 {
        return try await db.withTransaction { transaction in
            let countKey = TupleHelpers.encodeTripleCountKey(rootPrefix: self.rootPrefix)

            guard let bytes = try await transaction.getValue(for: countKey, snapshot: true) else {
                return 0
            }

            return TupleHelpers.decodeUInt64(bytes)
        }
    }

    /// Checks if a specific triple exists (efficient, does not return full data)
    func exists(_ triple: Triple) async throws -> Bool {
        logger.debug("Checking triple existence")

        return try await db.withTransaction { transaction in
            // Convert Values to IDs
            guard let subjectID = try await self.dictionaryStore.getExistingID(
                for: triple.subject,
                transaction: transaction
            ),
            let predicateID = try await self.dictionaryStore.getExistingID(
                for: triple.predicate,
                transaction: transaction
            ),
            let objectID = try await self.dictionaryStore.getExistingID(
                for: triple.object,
                transaction: transaction
            ) else {
                // If any value doesn't exist, triple doesn't exist
                return false
            }

            // Check SPO index
            let spoKey = TupleHelpers.encodeTripleKey(
                rootPrefix: self.rootPrefix,
                indexType: "spo",
                id1: subjectID,
                id2: predicateID,
                id3: objectID
            )

            let value = try await transaction.getValue(for: spoKey, snapshot: true)
            return value != nil
        }
    }

    // MARK: - Helper Methods

    private func encodeIndexKey(
        indexType: String,
        subjectID: UInt64,
        predicateID: UInt64,
        objectID: UInt64
    ) -> FDB.Bytes {
        switch indexType {
        case "spo":
            return TupleHelpers.encodeTripleKey(
                rootPrefix: rootPrefix,
                indexType: "spo",
                id1: subjectID,
                id2: predicateID,
                id3: objectID
            )
        case "pso":
            return TupleHelpers.encodeTripleKey(
                rootPrefix: rootPrefix,
                indexType: "pso",
                id1: predicateID,
                id2: subjectID,
                id3: objectID
            )
        case "pos":
            return TupleHelpers.encodeTripleKey(
                rootPrefix: rootPrefix,
                indexType: "pos",
                id1: predicateID,
                id2: objectID,
                id3: subjectID
            )
        case "osp":
            return TupleHelpers.encodeTripleKey(
                rootPrefix: rootPrefix,
                indexType: "osp",
                id1: objectID,
                id2: subjectID,
                id3: predicateID
            )
        default:
            fatalError("Invalid index type: \(indexType)")
        }
    }

    private func decodeIndexKey(
        key: FDB.Bytes,
        indexType: String
    ) throws -> (subjectID: UInt64, predicateID: UInt64, objectID: UInt64) {
        let (id1, id2, id3) = try TupleHelpers.decodeTripleKey(
            key,
            rootPrefix: rootPrefix,
            indexType: indexType
        )

        switch indexType {
        case "spo":
            return (id1, id2, id3)
        case "pso":
            return (id2, id1, id3)
        case "pos":
            return (id3, id1, id2)
        case "osp":
            return (id2, id3, id1)
        default:
            throw TripleError.internalError("Invalid index type: \(indexType)")
        }
    }

    private func selectOptimalIndex(
        subjectBound: Bool,
        predicateBound: Bool,
        objectBound: Bool
    ) -> String {
        switch (subjectBound, predicateBound, objectBound) {
        case (true, _, _):          return "spo"  // Subject is bound
        case (false, true, true):   return "pos"  // Predicate and Object are bound
        case (false, true, false):  return "pso"  // Only Predicate is bound
        case (false, false, true):  return "osp"  // Only Object is bound
        case (false, false, false): return "spo"  // Full scan, any index works
        }
    }

    private func buildRangeKeys(
        indexType: String,
        subjectID: UInt64?,
        predicateID: UInt64?,
        objectID: UInt64?
    ) -> (beginKey: FDB.Bytes, endKey: FDB.Bytes) {
        switch indexType {
        case "spo":
            return TupleHelpers.encodeRangeKeys(
                rootPrefix: rootPrefix,
                indexType: "spo",
                id1: subjectID,
                id2: predicateID,
                id3: objectID
            )
        case "pso":
            return TupleHelpers.encodeRangeKeys(
                rootPrefix: rootPrefix,
                indexType: "pso",
                id1: predicateID,
                id2: subjectID,
                id3: objectID
            )
        case "pos":
            return TupleHelpers.encodeRangeKeys(
                rootPrefix: rootPrefix,
                indexType: "pos",
                id1: predicateID,
                id2: objectID,
                id3: subjectID
            )
        case "osp":
            return TupleHelpers.encodeRangeKeys(
                rootPrefix: rootPrefix,
                indexType: "osp",
                id1: objectID,
                id2: subjectID,
                id3: predicateID
            )
        default:
            fatalError("Invalid index type: \(indexType)")
        }
    }
}

// MARK: - Optional Extension

extension Optional {
    fileprivate func asyncMap<T>(_ transform: @Sendable (Wrapped) async throws -> T?) async throws -> T? {
        switch self {
        case .some(let value):
            return try await transform(value)
        case .none:
            return nil
        }
    }
}
