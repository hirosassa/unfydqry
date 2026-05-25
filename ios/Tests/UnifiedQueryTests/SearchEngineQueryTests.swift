import Foundation
import Testing
@testable import UnifiedQuery

/// `SearchEngine` の **言語固有・非データ駋動** な性質をチェックする。
///
/// 入力→ヒット ID の素朴な対は `spec/search.json` と `SpecDrivenTests` 側に寄せて
/// あるので、ここに残るのは:
///   - score の sanity(LIKE 経路は 0、FTS5 経路は有限の非ゼロ)
///   - 順序(bm25 昇順)
///   - limit のカウント(どの ID が来るかは非決定)
///   - 例外を出さないことの確認(FTS5 予約文字、空白だけのクエリ)
///   - 並行検索(Mutex<Connection> 経由の直列化が落ちないこと)
@Suite("SearchEngine query (native-only)")
struct SearchEngineQueryTests {
    private func fresh() throws -> SearchEngine {
        try SearchEngine(dbPath: ":memory:")
    }

    // MARK: - Score sanity

    @Test func likeFallbackReturnsZeroScore() throws {
        // LIKE 経路は score=0 を返す(設計書通り)。
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
        // 3文字以上 → FTS5 経路。doc 長が異なると bm25 が動く。
        try e.index(id: 1, text: "coffee")
        try e.index(id: 2, text: "coffee coffee coffee coffee coffee")
        try e.index(id: 3, text: String(repeating: "lorem ipsum dolor sit amet ", count: 20) + "coffee")
        let hits = try e.search(query: "coffee", limit: 10)
        #expect(hits.count == 3)
        // bm25 は小さい(=負の絶対値が大きい)ほど上位。順序は単調増加。
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
        // " " は正規化後も1文字 → LIKE 経路だが空白マッチは無意味。例外なく返ることを担保。
        let hits = try e.search(query: " ", limit: 10)
        #expect(hits.count >= 0)
    }

    @Test func fts5SpecialCharactersDoNotCrash() throws {
        let e = try fresh()
        try e.index(id: 1, text: "alpha beta gamma")
        // FTS5 構文の予約文字を含んでも、フレーズで包んでいるので落ちない。
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
        // Mutex<Connection> 経由で内部直列化される想定。並行呼び出しが落ちないことを担保。
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
