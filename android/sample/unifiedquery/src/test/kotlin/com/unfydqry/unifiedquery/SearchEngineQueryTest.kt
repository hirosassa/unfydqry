package com.unfydqry.unifiedquery

import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertFalse
import org.junit.jupiter.api.Assertions.assertNotEquals
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.DisplayName
import org.junit.jupiter.api.Test
import uniffi.unfydqry.SearchEngine

/**
 * Checks the **language-specific, non-data-driven** properties of `SearchEngine`.
 *
 * Plain (input → hit ID) pairs live in `spec/search.json` and `SpecDrivenTest`.
 * What remains here:
 *   - score sanity (LIKE path returns 0; FTS5 path returns a finite non-zero score)
 *   - ordering (bm25 ascending)
 *   - limit count (which IDs come back is non-deterministic; the count isn't)
 *   - non-throwing safety (FTS5 reserved characters, whitespace-only queries)
 *   - concurrent search (serialization via Mutex<Connection> does not crash)
 */
@DisplayName("SearchEngine query (native-only)")
class SearchEngineQueryTest {
    private fun fresh() = SearchEngine(":memory:")

    @Test fun `LIKE fallback returns zero score`() {
        val e = fresh()
        e.index(1, "がっこう")
        assertEquals(0.0, e.search("が", 10u).first().score)
    }

    @Test fun `FTS5 hit has finite nonzero score`() {
        val e = fresh()
        e.index(1, "がっこう")
        val hits = e.search("がっこ", 10u)
        assertFalse(hits.isEmpty())
        val first = hits.first()
        assertNotEquals(0.0, first.score)
        assertTrue(first.score.isFinite())
    }

    @Test fun `results are ordered by bm25 ascending`() {
        val e = fresh()
        e.index(1, "coffee")
        e.index(2, "coffee coffee coffee coffee coffee")
        e.index(3, "lorem ipsum dolor sit amet ".repeat(20) + "coffee")
        val hits = e.search("coffee", 10u)
        assertEquals(3, hits.size)
        val scores = hits.map { it.score }
        assertEquals(scores, scores.sorted())
    }

    @Test fun `limit is honored`() {
        val e = fresh()
        for (i in 1L..20L) {
            e.index(i, "doc $i about coffee bean")
        }
        assertEquals(5, e.search("coffee", 5u).size)
        assertTrue(e.search("coffee", 0u).isEmpty())
    }

    @Test fun `whitespace-only query does not crash`() {
        val e = fresh()
        e.index(1, "anything")
        // " " is one normalized char → LIKE path; result may or may not be empty,
        // but must not throw.
        val hits = e.search(" ", 10u)
        assertTrue(hits.size >= 0)
    }

    @Test fun `fts5 special characters do not crash`() {
        val e = fresh()
        e.index(1, "alpha beta gamma")
        for (q in listOf("alpha AND beta", "alpha OR beta", "alpha NEAR beta",
                          "alpha*", "(alpha)", "alpha:beta")) {
            e.search(q, 10u) // Only assert the call completes without throwing.
        }
    }

    @Test fun `concurrent search on same engine works`() {
        val e = fresh()
        for (i in 1L..50L) {
            e.index(i, "coffee bean number $i")
        }
        val pool = Executors.newFixedThreadPool(8)
        try {
            val tasks = (1..20).map {
                pool.submit<Int> { e.search("coffee", 100u).size }
            }
            for (t in tasks) {
                assertEquals(50, t.get(10, TimeUnit.SECONDS))
            }
        } finally {
            pool.shutdown()
        }
    }
}
