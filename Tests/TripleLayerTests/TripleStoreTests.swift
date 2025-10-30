import Testing
import Foundation
import FoundationDB
@testable import TripleLayer

@Suite("Triple Store Tests")
struct TripleStoreTests {

    // MARK: - Setup

    private static func createStore() async throws -> TripleStore {
        // Initialize FoundationDB (ignore error if already initialized)
        do {
            try await FDBClient.initialize()
        } catch {
            // Already initialized, ignore
        }

        let database = try FDBClient.openDatabase()

        // Create triple store with unique prefix for this test run
        let prefix = "test-\(UUID().uuidString.prefix(8))"
        return TripleStore(database: database, rootPrefix: prefix)
    }

    // MARK: - Basic Operations

    @Test("Insert and query single triple")
    func insertAndQuerySingle() async throws {
        let store = try await Self.createStore()

        let triple = Triple(
            subject: .uri("http://example.org/Alice"),
            predicate: .uri("http://xmlns.com/foaf/0.1/knows"),
            object: .uri("http://example.org/Bob")
        )

        // Insert
        try await store.insert(triple)

        // Query by subject
        let results = try await store.query(subject: .uri("http://example.org/Alice"))

        #expect(results.count == 1)
        #expect(results[0] == triple)
    }

    @Test("Insert duplicate triple is idempotent")
    func insertDuplicate() async throws {
        let store = try await Self.createStore()

        let triple = Triple(
            subject: .uri("http://example.org/Alice"),
            predicate: .uri("http://xmlns.com/foaf/0.1/knows"),
            object: .uri("http://example.org/Bob")
        )

        // Insert twice
        try await store.insert(triple)
        try await store.insert(triple)

        // Should still have only one triple
        let count = try await store.count()
        #expect(count == 1)
    }

    @Test("Delete triple")
    func deleteTriple() async throws {
        let store = try await Self.createStore()

        let triple = Triple(
            subject: .uri("http://example.org/Alice"),
            predicate: .uri("http://xmlns.com/foaf/0.1/knows"),
            object: .uri("http://example.org/Bob")
        )

        // Insert and verify
        try await store.insert(triple)
        #expect(try await store.count() == 1)

        // Delete and verify
        try await store.delete(triple)
        #expect(try await store.count() == 0)
    }

    // MARK: - Query Patterns

    @Test("Query by subject")
    func queryBySubject() async throws {
        let store = try await Self.createStore()

        let alice = Value.uri("http://example.org/Alice")
        let bob = Value.uri("http://example.org/Bob")
        let knows = Value.uri("http://xmlns.com/foaf/0.1/knows")

        // Insert multiple triples
        try await store.insert(Triple(subject: alice, predicate: knows, object: bob))
        try await store.insert(Triple(subject: alice, predicate: knows, object: .uri("http://example.org/Charlie")))
        try await store.insert(Triple(subject: bob, predicate: knows, object: alice))

        // Query by subject
        let results = try await store.query(subject: alice)

        #expect(results.count == 2)
        #expect(results.allSatisfy { $0.subject == alice })
    }

    @Test("Query by predicate")
    func queryByPredicate() async throws {
        let store = try await Self.createStore()

        let alice = Value.uri("http://example.org/Alice")
        let knows = Value.uri("http://xmlns.com/foaf/0.1/knows")
        let name = Value.uri("http://xmlns.com/foaf/0.1/name")

        // Insert triples with different predicates
        try await store.insert(Triple(subject: alice, predicate: knows, object: .uri("http://example.org/Bob")))
        try await store.insert(Triple(subject: alice, predicate: name, object: .text("Alice")))

        // Query by predicate
        let results = try await store.query(predicate: knows)

        #expect(results.count == 1)
        #expect(results[0].predicate == knows)
    }

    @Test("Query by object")
    func queryByObject() async throws {
        let store = try await Self.createStore()

        let bob = Value.uri("http://example.org/Bob")
        let knows = Value.uri("http://xmlns.com/foaf/0.1/knows")

        // Insert triples pointing to the same object
        try await store.insert(Triple(subject: .uri("http://example.org/Alice"), predicate: knows, object: bob))
        try await store.insert(Triple(subject: .uri("http://example.org/Charlie"), predicate: knows, object: bob))

        // Query by object
        let results = try await store.query(object: bob)

        #expect(results.count == 2)
        #expect(results.allSatisfy { $0.object == bob })
    }

    @Test("Query with multiple bounds")
    func queryMultipleBounds() async throws {
        let store = try await Self.createStore()

        let alice = Value.uri("http://example.org/Alice")
        let knows = Value.uri("http://xmlns.com/foaf/0.1/knows")

        // Insert triples
        try await store.insert(Triple(subject: alice, predicate: knows, object: .uri("http://example.org/Bob")))
        try await store.insert(Triple(subject: alice, predicate: knows, object: .uri("http://example.org/Charlie")))
        try await store.insert(Triple(subject: alice, predicate: .uri("http://xmlns.com/foaf/0.1/name"), object: .text("Alice")))

        // Query with subject and predicate bound
        let results = try await store.query(subject: alice, predicate: knows)

        #expect(results.count == 2)
        #expect(results.allSatisfy { $0.subject == alice && $0.predicate == knows })
    }

    // MARK: - Value Types

    @Test("Store different value types")
    func storeDifferentValueTypes() async throws {
        let store = try await Self.createStore()

        let entity = Value.uri("http://example.org/Entity1")

        // URI
        try await store.insert(Triple(subject: entity, predicate: .uri("p1"), object: .uri("http://example.org/value")))

        // Text
        try await store.insert(Triple(subject: entity, predicate: .uri("p2"), object: .text("Hello World")))

        // Integer
        try await store.insert(Triple(subject: entity, predicate: .uri("p3"), object: .integer(42)))

        // Float
        try await store.insert(Triple(subject: entity, predicate: .uri("p4"), object: .float(3.14)))

        // Boolean
        try await store.insert(Triple(subject: entity, predicate: .uri("p5"), object: .boolean(true)))

        // Verify all inserted
        let results = try await store.query(subject: entity)
        #expect(results.count == 5)
    }

    @Test("Store language-tagged text")
    func storeLanguageTaggedText() async throws {
        let store = try await Self.createStore()

        let tokyo = Value.uri("http://example.org/Tokyo")
        let label = Value.uri("http://www.w3.org/2000/01/rdf-schema#label")

        // Insert multi-language labels
        try await store.insert(Triple(subject: tokyo, predicate: label, object: .text("Tokyo", language: "en")))
        try await store.insert(Triple(subject: tokyo, predicate: label, object: .text("東京", language: "ja")))

        // Query all labels
        let results = try await store.query(subject: tokyo, predicate: label)

        #expect(results.count == 2)
    }

    // MARK: - Batch Operations

    @Test("Batch insert")
    func batchInsert() async throws {
        let store = try await Self.createStore()

        // Create 100 triples
        var triples: [Triple] = []
        for i in 0..<100 {
            triples.append(Triple(
                subject: .uri("http://example.org/person\(i)"),
                predicate: .uri("http://xmlns.com/foaf/0.1/knows"),
                object: .uri("http://example.org/person\(i + 1)")
            ))
        }

        // Batch insert
        try await store.insertBatch(triples)

        // Verify count
        let count = try await store.count()
        #expect(count == 100)
    }

    @Test("Batch insert with duplicates")
    func batchInsertWithDuplicates() async throws {
        let store = try await Self.createStore()

        let triple = Triple(
            subject: .uri("http://example.org/Alice"),
            predicate: .uri("http://xmlns.com/foaf/0.1/knows"),
            object: .uri("http://example.org/Bob")
        )

        // Insert batch with duplicates
        try await store.insertBatch([triple, triple, triple])

        // Should only have one triple
        let count = try await store.count()
        #expect(count == 1)
    }

    // MARK: - Utility Methods

    @Test("Contains check")
    func containsCheck() async throws {
        let store = try await Self.createStore()

        let triple = Triple(
            subject: .uri("http://example.org/Alice"),
            predicate: .uri("http://xmlns.com/foaf/0.1/knows"),
            object: .uri("http://example.org/Bob")
        )

        // Should not contain before insert
        #expect(try await store.contains(triple) == false)

        // Insert
        try await store.insert(triple)

        // Should contain after insert
        #expect(try await store.contains(triple) == true)

        // Delete
        try await store.delete(triple)

        // Should not contain after delete
        #expect(try await store.contains(triple) == false)
    }

    @Test("Query non-existent value")
    func queryNonExistent() async throws {
        let store = try await Self.createStore()

        // Insert one triple
        try await store.insert(Triple(
            subject: .uri("http://example.org/Alice"),
            predicate: .uri("http://xmlns.com/foaf/0.1/knows"),
            object: .uri("http://example.org/Bob")
        ))

        // Query for non-existent value
        let results = try await store.query(subject: .uri("http://example.org/Nonexistent"))

        #expect(results.isEmpty)
    }

    // MARK: - Binary Data

    @Test("Store small binary data")
    func storeSmallBinaryData() async throws {
        let store = try await Self.createStore()

        // Create small binary data (1KB)
        let smallData = Data(repeating: 0x42, count: 1024)
        let entity = Value.uri("http://example.org/Entity1")

        try await store.insert(Triple(
            subject: entity,
            predicate: .uri("p1"),
            object: .binary(smallData)
        ))

        let results = try await store.query(subject: entity)
        #expect(results.count == 1)

        if case .binary(let retrievedData) = results[0].object {
            #expect(retrievedData == smallData)
        } else {
            #expect(Bool(false), "Expected binary value")
        }
    }

    @Test("Large binary data throws error")
    func largeBinaryDataThrowsError() async throws {
        let store = try await Self.createStore()

        // Create large binary data (10KB - exceeds 8KB limit)
        let largeData = Data(repeating: 0xFF, count: 10240)
        let entity = Value.uri("http://example.org/Entity2")

        // Should throw invalidValue error
        await #expect(throws: TripleError.self) {
            try await store.insert(Triple(
                subject: entity,
                predicate: .uri("p1"),
                object: .binary(largeData)
            ))
        }
    }

    // MARK: - Edge Cases

    @Test("Delete non-existent triple is idempotent")
    func deleteNonExistent() async throws {
        let store = try await Self.createStore()

        let triple = Triple(
            subject: .uri("http://example.org/NonExistent"),
            predicate: .uri("http://example.org/pred"),
            object: .uri("http://example.org/obj")
        )

        // Should not throw error
        try await store.delete(triple)

        // Count should be 0
        let count = try await store.count()
        #expect(count == 0)
    }

    @Test("Full scan query (all triples)")
    func fullScanQuery() async throws {
        let store = try await Self.createStore()

        // Insert 5 triples
        try await store.insert(Triple(subject: .uri("s1"), predicate: .uri("p1"), object: .uri("o1")))
        try await store.insert(Triple(subject: .uri("s2"), predicate: .uri("p2"), object: .uri("o2")))
        try await store.insert(Triple(subject: .uri("s3"), predicate: .uri("p3"), object: .uri("o3")))
        try await store.insert(Triple(subject: .uri("s4"), predicate: .uri("p4"), object: .uri("o4")))
        try await store.insert(Triple(subject: .uri("s5"), predicate: .uri("p5"), object: .uri("o5")))

        // Query all (?, ?, ?)
        let allResults = try await store.all()
        #expect(allResults.count == 5)

        // Verify count matches
        let count = try await store.count()
        #expect(count == 5)
    }

    @Test("Large text values")
    func largeTextValues() async throws {
        let store = try await Self.createStore()

        // Create large text (2KB - within limits)
        let largeText = String(repeating: "あ", count: 500)
        let entity = Value.uri("http://example.org/Entity")

        try await store.insert(Triple(
            subject: entity,
            predicate: .uri("hasDescription"),
            object: .text(largeText)
        ))

        let results = try await store.query(subject: entity)
        #expect(results.count == 1)

        if case .text(let retrievedText, _) = results[0].object {
            #expect(retrievedText == largeText)
        } else {
            #expect(Bool(false), "Expected text value")
        }
    }

    @Test("Mixed query patterns")
    func mixedQueryPatterns() async throws {
        let store = try await Self.createStore()

        let alice = Value.uri("http://example.org/Alice")
        let bob = Value.uri("http://example.org/Bob")
        let charlie = Value.uri("http://example.org/Charlie")
        let knows = Value.uri("http://xmlns.com/foaf/0.1/knows")
        let name = Value.uri("http://xmlns.com/foaf/0.1/name")

        // Insert test data
        try await store.insert(Triple(subject: alice, predicate: knows, object: bob))
        try await store.insert(Triple(subject: alice, predicate: name, object: .text("Alice")))
        try await store.insert(Triple(subject: bob, predicate: name, object: .text("Bob")))
        try await store.insert(Triple(subject: charlie, predicate: knows, object: bob))

        // Query: (?, knows, Bob) - should use POS index
        let results1 = try await store.query(predicate: knows, object: bob)
        #expect(results1.count == 2)  // Alice and Charlie both know Bob
        #expect(results1.contains(where: { $0.subject == alice }))
        #expect(results1.contains(where: { $0.subject == charlie }))

        // Query: (Alice, ?, Bob) - should use SPO index with object filter
        // Note: This query pattern (S, ?, O) is less efficient but should work
        let results2 = try await store.query(subject: alice, object: bob)
        #expect(results2.count == 1)
        #expect(results2[0].predicate == knows)

        // Query: (?, name, ?) - should use PSO index
        let results3 = try await store.query(predicate: name)
        #expect(results3.count == 2)
    }

    @Test("Special characters in URIs and text")
    func specialCharacters() async throws {
        let store = try await Self.createStore()

        let specialURI = Value.uri("http://example.org/entity#with-special-chars!@$%^&*()")
        let specialText = Value.text("Special 特殊文字 🎉 \n\t\r quotes: \"'`")

        try await store.insert(Triple(
            subject: specialURI,
            predicate: .uri("hasText"),
            object: specialText
        ))

        let results = try await store.query(subject: specialURI)
        #expect(results.count == 1)
        #expect(results[0].object == specialText)
    }

    @Test("Counter accuracy after mixed operations")
    func counterAccuracy() async throws {
        let store = try await Self.createStore()

        // Insert 10 triples
        for i in 0..<10 {
            try await store.insert(Triple(
                subject: .uri("s\(i)"),
                predicate: .uri("p"),
                object: .uri("o\(i)")
            ))
        }
        #expect(try await store.count() == 10)

        // Delete 5 triples
        for i in 0..<5 {
            try await store.delete(Triple(
                subject: .uri("s\(i)"),
                predicate: .uri("p"),
                object: .uri("o\(i)")
            ))
        }
        #expect(try await store.count() == 5)

        // Insert duplicate (should not increase count)
        try await store.insert(Triple(
            subject: .uri("s5"),
            predicate: .uri("p"),
            object: .uri("o5")
        ))
        #expect(try await store.count() == 5)

        // Delete non-existent (should not decrease count)
        try await store.delete(Triple(
            subject: .uri("nonexistent"),
            predicate: .uri("p"),
            object: .uri("o")
        ))
        #expect(try await store.count() == 5)
    }

    @Test("Multiple language tags on same text")
    func multipleLanguageTags() async throws {
        let store = try await Self.createStore()

        let entity = Value.uri("http://example.org/City")
        let label = Value.uri("rdfs:label")

        // Insert same text in multiple languages
        try await store.insert(Triple(subject: entity, predicate: label, object: .text("City", language: "en")))
        try await store.insert(Triple(subject: entity, predicate: label, object: .text("Stadt", language: "de")))
        try await store.insert(Triple(subject: entity, predicate: label, object: .text("Ville", language: "fr")))
        try await store.insert(Triple(subject: entity, predicate: label, object: .text("都市", language: "ja")))

        let results = try await store.query(subject: entity, predicate: label)
        #expect(results.count == 4)

        // Verify all language tags are different
        let languages = results.compactMap { $0.object.languageTag }
        #expect(Set(languages).count == 4)
    }

    @Test("Negative and zero numeric values")
    func negativeAndZeroValues() async throws {
        let store = try await Self.createStore()

        let entity = Value.uri("http://example.org/Measurement")

        try await store.insert(Triple(subject: entity, predicate: .uri("hasInt"), object: .integer(-42)))
        try await store.insert(Triple(subject: entity, predicate: .uri("hasZero"), object: .integer(0)))
        try await store.insert(Triple(subject: entity, predicate: .uri("hasFloat"), object: .float(-3.14)))
        try await store.insert(Triple(subject: entity, predicate: .uri("hasLargeFloat"), object: .float(-999999.999)))

        let results = try await store.query(subject: entity)
        #expect(results.count == 4)

        // Verify negative integer
        let negInt = results.first { triple in
            if case .integer(let i) = triple.object, i == -42 {
                return true
            }
            return false
        }
        #expect(negInt != nil)

        // Verify zero
        let zero = results.first { triple in
            if case .integer(let i) = triple.object, i == 0 {
                return true
            }
            return false
        }
        #expect(zero != nil)

        // Verify negative float
        let negFloat = results.first { triple in
            if case .float(let f) = triple.object, f == -3.14 {
                return true
            }
            return false
        }
        #expect(negFloat != nil)
    }

    @Test("Batch operations maintain consistency")
    func batchConsistency() async throws {
        let store = try await Self.createStore()

        // Create 1500 triples (will be split into 2 batches of 1000 and 500)
        var triples: [Triple] = []
        for i in 0..<1500 {
            triples.append(Triple(
                subject: .uri("s\(i)"),
                predicate: .uri("p"),
                object: .integer(Int64(i))
            ))
        }

        try await store.insertBatch(triples)

        // Verify all inserted
        let count = try await store.count()
        #expect(count == 1500)

        // Query a specific one
        let results = try await store.query(subject: .uri("s999"))
        #expect(results.count == 1)
        #expect(results[0].object == .integer(999))
    }

    // MARK: - Metadata

    @Test("Store triple with metadata")
    func storeTripleWithMetadata() async throws {
        let store = try await Self.createStore()

        var triple = Triple(
            subject: .uri("http://example.org/Alice"),
            predicate: .uri("http://example.org/worksAt"),
            object: .uri("http://example.org/TechCorp")
        )
        triple.metadata = Metadata(
            confidence: 0.87,
            source: "document_456",
            timestamp: Date()
        )

        // Insert
        try await store.insert(triple)

        // Query
        let results = try await store.query(subject: .uri("http://example.org/Alice"))

        #expect(results.count == 1)
        // Note: Metadata is not stored in current implementation
        // This test verifies that metadata doesn't break insertion
    }
}
