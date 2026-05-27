import Foundation
import Testing
@testable import UnifiedQuery

/// Checks the **language-specific, non-data-driven** properties of `SearchEngine`.
///
/// Plain (input → hit ID) pairs live in `spec/search.json` and `SpecDrivenTests`.
/// What remains here:
///   - score sanity (LIKE path returns 0; FTS5 path returns a finite non-zero score)
///   - ordering (bm25 ascending)
///   - limit count (which IDs come back is non-deterministic; the count isn't)
///   - non-throwing safety (FTS5 reserved characters, whitespace-only queries)
///   - concurrent search (serialization via Mutex<Connection> does not crash)
@Suite("SearchEngine query (native-only)")
struct SearchEngineQueryTests {
    private func fresh() throws -> SearchEngine {
        try SearchEngine(dbPath: ":memory:")
    }

    // MARK: - Score sanity

    @Test func likeFallbackReturnsZeroScore() throws {
        // The LIKE path returns score=0 (as specified in the design doc).
        let e = try fresh()
        try e.index(id: 1, text: "がっこう")
        let hits = try e.search(query: "が", limit: 10)
        #expect(hits.first?.score == 0.0)
    }

    @Test func fts5HitHasFiniteNonZeroScore() throws {
        let e = try fresh()
        try e.index(id: 1, text: "がっこう")
        let hits = try e.search(query: "がっこ", limit: 10)
        #expect(!hits.isEmpty)
        if let first = hits.first {
            #expect(first.score != 0.0)
            #expect(first.score.isFinite)
        }
    }

    // MARK: - Ordering / limit

    @Test func resultsAreOrderedByBM25Ascending() throws {
        let e = try fresh()
        // ≥3 chars → FTS5 path. Different doc lengths move bm25 around.
        try e.index(id: 1, text: "coffee")
        try e.index(id: 2, text: "coffee coffee coffee coffee coffee")
        try e.index(id: 3, text: String(repeating: "lorem ipsum dolor sit amet ", count: 20) + "coffee")
        let hits = try e.search(query: "coffee", limit: 10)
        #expect(hits.count == 3)
        // Smaller (= more negative) bm25 ranks higher. The series is monotonically non-decreasing.
        let scores = hits.map(\.score)
        #expect(scores == scores.sorted())
    }

    @Test func limitIsHonored() throws {
        let e = try fresh()
        for i in Int64(1)...20 {
            try e.index(id: i, text: "doc \(i) about coffee bean")
        }
        let limit5 = try e.search(query: "coffee", limit: 5)
        #expect(limit5.count == 5)

        let limit0 = try e.search(query: "coffee", limit: 0)
        #expect(limit0.isEmpty)
    }

    // MARK: - Non-throwing safety

    @Test func whitespaceOnlyQueryDoesNotCrash() throws {
        let e = try fresh()
        try e.index(id: 1, text: "anything")
        // " " is one char after normalization → takes the LIKE path; matching whitespace is
        // meaningless. We only assert that the call returns without throwing.
        let hits = try e.search(query: " ", limit: 10)
        #expect(hits.count >= 0)
    }

    @Test func fts5SpecialCharactersDoNotCrash() throws {
        let e = try fresh()
        try e.index(id: 1, text: "alpha beta gamma")
        // Reserved FTS5 syntax characters are safe because we wrap the query as a phrase.
        for q in ["alpha AND beta", "alpha OR beta", "alpha NEAR beta",
                  "alpha*", "(alpha)", "alpha:beta"] {
            _ = try e.search(query: q, limit: 10)
        }
    }

    // MARK: - Concurrency smoke

    @Test func concurrentSearchOnSameEngineWorks() async throws {
        let e = try fresh()
        for i in Int64(1)...50 {
            try e.index(id: i, text: "coffee bean number \(i)")
        }
        // Calls are expected to be serialized internally via Mutex<Connection>. We only
        // assert that concurrent invocations do not crash.
        await withTaskGroup(of: Int.self) { group in
            for _ in 0..<20 {
                group.addTask {
                    (try? e.search(query: "coffee", limit: 100))?.count ?? -1
                }
            }
            for await count in group {
                #expect(count == 50)
            }
        }
    }
}
