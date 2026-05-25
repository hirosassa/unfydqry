import Foundation
import Testing
@testable import UnifiedQuery

/// 設計書 §E.4「ゴールデンテスト」を `spec/*.json` の形で具現化したテスト。
/// Kotlin / Rust 側と同じ JSON を読むので、Rust コアの正規化や検索ロジックが変わると
/// 3 つのランナー(Swift / Kotlin / Rust)が同時に同じ id で失敗する。
@Suite("Spec-driven cross-platform")
struct SpecDrivenTests {
    // MARK: - normalize.json

    @Test func normalizeSpecVersionIsExpected() {
        #expect(Spec.normalize.version == Spec.expectedVersion)
    }

    @Test(arguments: Spec.normalize.cases)
    func normalizeMatchesSpec(_ c: NormalizeCase) {
        #expect(normalizeLoose(input: c.input) == c.expected,
                "id=\(c.id): \(c.description)")
    }

    // MARK: - search.json: scenarios

    @Test func searchSpecVersionIsExpected() {
        #expect(Spec.search.version == Spec.expectedVersion)
    }

    @Test(arguments: Spec.search.scenarios)
    func scenarioMatchesSpec(_ s: Scenario) throws {
        let engine = try SearchEngine(dbPath: ":memory:")
        try apply(ops: s.ops, to: engine)
        for assertion in s.assertions {
            let hits = try engine.search(query: assertion.search.query,
                                         limit: assertion.search.limit)
            let got = Set(hits.map(\.id))
            let want = Set(assertion.expectedIds)
            #expect(got == want,
                    "scenario id=\(s.id): \(s.description); query=\"\(assertion.search.query)\" got=\(got.sorted()) want=\(want.sorted())")
        }
    }

    // MARK: - search.json: seeded_matrices

    /// 共有シードに対する全 matrix × 全 query を 1 つの `@Test` に展開する。
    /// matrix が 1 つしかない現状でも、将来複数 matrix を足せばそのまま倍々で増える。
    static let matrixCases: [(matrix: SeededMatrix, query: QueryExpectation)] = {
        Spec.search.seededMatrices.flatMap { m in m.queries.map { (m, $0) } }
    }()

    @Test(arguments: matrixCases)
    func seededMatrixQueryMatchesSpec(_ pair: (matrix: SeededMatrix, query: QueryExpectation)) throws {
        let engine = try SearchEngine(dbPath: ":memory:")
        try apply(ops: pair.matrix.seed, to: engine)
        let hits = try engine.search(query: pair.query.query, limit: pair.matrix.limit)
        let got = Set(hits.map(\.id))
        let want = Set(pair.query.expectedIds)
        #expect(got == want,
                "matrix=\(pair.matrix.id) query=\"\(pair.query.query)\": \(pair.query.description); got=\(got.sorted()) want=\(want.sorted())")
    }

    // MARK: - helpers

    private func apply(ops: [IndexOp], to engine: SearchEngine) throws {
        for op in ops {
            switch op.op {
            case "index":
                try engine.index(id: op.id, text: op.text ?? "")
            case "remove":
                try engine.remove(id: op.id)
            default:
                Issue.record("Unknown op \"\(op.op)\" — spec/search.json schema mismatch")
            }
        }
    }
}
