use std::sync::{Arc, Mutex};

use rusqlite::{params, Connection, OptionalExtension};

use crate::config::{EngineConfig, NormalizeProfile};
use crate::normalize::{build_normalizer, Normalizer};
use crate::search::{build_strategy, SearchAlgorithm};

/// A single search result: the stable `id` the host indexed under, plus a
/// relevance `score`.
///
/// The engine returns only ids and scores — never the document text — so the
/// host re-fetches the full record from its own source-of-truth store.
#[derive(Debug, Clone, uniffi::Record)]
pub struct Hit {
    /// The id the document was indexed under (see `index`).
    pub id: i64,
    /// Relevance score. For ranked strategies a smaller value is a better
    /// match (bm25 for `trigramBm25`, `1 − similarity` for `fuzzyTrigram`,
    /// edit distance for the Levenshtein strategies). Unranked strategies
    /// (`substring`, `prefix`, `suffix`, `allTerms`) always report `0.0`.
    pub score: f64,
}

/// An error surfaced across the FFI boundary by `SearchEngine`.
#[derive(Debug, thiserror::Error, uniffi::Error)]
pub enum SearchError {
    /// An underlying SQLite / storage failure; the associated string is its
    /// message.
    #[error("{0}")]
    Db(String),
    /// The on-disk index was built with a different normalization profile
    /// than the one requested. Indexed text is profile-specific, so the index
    /// must be rebuilt to change profiles. `stored` is the profile recorded in
    /// the index; `requested` is the one just asked for.
    #[error(
        "index built with normalize profile {stored}, requested {requested}; rebuild required"
    )]
    ConfigMismatch { stored: String, requested: String },
}

impl From<rusqlite::Error> for SearchError {
    fn from(e: rusqlite::Error) -> Self {
        SearchError::Db(e.to_string())
    }
}

/// A persistent full-text search index backed by SQLite.
///
/// Create one with `SearchEngine(dbPath:)` for the default behaviour, or
/// `SearchEngine.withConfig(dbPath:config:)` to choose a normalization profile
/// and a search strategy. Add or update documents with `index`, drop them with
/// `remove`, and query with `search`. The instance is safe to share across
/// threads.
///
/// The engine stores both the raw host text and its normalized form, so the
/// index can be regenerated in place after a normalization change — explicitly
/// via `reindex`, or automatically by opening with
/// `SearchEngine.withConfigRebuilding(dbPath:config:)`.
#[derive(uniffi::Object)]
pub struct SearchEngine {
    conn: Mutex<Connection>,
    normalizer: Box<dyn Normalizer>,
    strategy: Box<dyn SearchAlgorithm>,
    profile: NormalizeProfile,
}

impl SearchEngine {
    /// Opens the connection and ensures the schema and migrations are in place.
    fn open_schema(db_path: &str) -> Result<Connection, SearchError> {
        let conn = Connection::open(db_path)?;
        conn.pragma_update(None, "journal_mode", "WAL")?;
        conn.execute_batch(
            "CREATE VIRTUAL TABLE IF NOT EXISTS docs
                 USING fts5(norm, tokenize='trigram');
             CREATE TABLE IF NOT EXISTS entries(
                 id INTEGER PRIMARY KEY, norm TEXT NOT NULL, raw TEXT);
             CREATE TABLE IF NOT EXISTS meta(
                 key TEXT PRIMARY KEY, value TEXT NOT NULL);",
        )?;
        // Used to detect when the index needs to be rebuilt after a future change to a profile.
        conn.execute(
            "INSERT OR IGNORE INTO meta(key, value) VALUES ('index_version', '1')",
            [],
        )?;
        // Migrate indexes created before raw text was retained.
        if !Self::entries_has_raw(&conn)? {
            conn.execute("ALTER TABLE entries ADD COLUMN raw TEXT", [])?;
        }
        Ok(conn)
    }

    /// Whether the `entries` table already has the `raw` column.
    fn entries_has_raw(conn: &Connection) -> Result<bool, SearchError> {
        let mut stmt = conn.prepare("PRAGMA table_info(entries)")?;
        let mut rows = stmt.query([])?;
        while let Some(row) = rows.next()? {
            let name: String = row.get(1)?;
            if name == "raw" {
                return Ok(true);
            }
        }
        Ok(false)
    }

    /// The normalize profile recorded in the index, if any documents exist.
    ///
    /// Returns `None` for an empty index (any profile is safe to adopt). A
    /// non-empty index missing the key was built with the `loose` profile.
    fn stored_profile(conn: &Connection) -> Result<Option<String>, SearchError> {
        let indexed: i64 = conn.query_row("SELECT COUNT(*) FROM entries", [], |r| r.get(0))?;
        if indexed == 0 {
            return Ok(None);
        }
        let stored: Option<String> = conn
            .query_row(
                "SELECT value FROM meta WHERE key = 'normalize_profile'",
                [],
                |r| r.get(0),
            )
            .optional()?;
        Ok(Some(stored.unwrap_or_else(|| "loose".to_string())))
    }

    /// Records `profile` as the index's normalize profile.
    fn stamp_profile(conn: &Connection, profile: &str) -> Result<(), SearchError> {
        conn.execute(
            "INSERT OR REPLACE INTO meta(key, value) VALUES ('normalize_profile', ?1)",
            params![profile],
        )?;
        Ok(())
    }

    fn assemble(conn: Connection, config: EngineConfig) -> Arc<Self> {
        Arc::new(Self {
            conn: Mutex::new(conn),
            normalizer: build_normalizer(config.normalize),
            strategy: build_strategy(config.strategy),
            profile: config.normalize,
        })
    }
}

#[uniffi::export]
impl SearchEngine {
    /// Opens the index with the default behaviour (loose normalization +
    /// trigram/bm25). Kept for backward compatibility.
    #[uniffi::constructor]
    pub fn new(db_path: String) -> Result<Arc<Self>, SearchError> {
        Self::with_config(db_path, EngineConfig::default())
    }

    /// Opens the index with a host-selected combination of normalization
    /// profile and search strategy.
    ///
    /// If the index already holds documents normalized under a *different*
    /// profile, this returns `ConfigMismatch` rather than silently mixing
    /// profiles. To regenerate the index under the new profile instead of
    /// failing, open with `withConfigRebuilding`, or call `reindex` on an
    /// engine opened with the matching profile.
    #[uniffi::constructor(name = "withConfig")]
    pub fn with_config(db_path: String, config: EngineConfig) -> Result<Arc<Self>, SearchError> {
        let conn = Self::open_schema(&db_path)?;
        let requested = config.normalize.as_key();
        if let Some(stored) = Self::stored_profile(&conn)? {
            // The normalized text stored in the index depends on the normalize
            // profile, so an index built with one profile cannot be queried
            // with another. Reject a mismatch.
            if stored != requested {
                return Err(SearchError::ConfigMismatch {
                    stored,
                    requested: requested.to_string(),
                });
            }
        }
        Self::stamp_profile(&conn, requested)?;
        Ok(Self::assemble(conn, config))
    }

    /// Opens the index under `config`, regenerating it in place when the stored
    /// documents were normalized under a different profile.
    ///
    /// Unlike `withConfig`, a profile change is not an error here: the engine
    /// re-normalizes every stored document from its retained raw text under the
    /// new profile before returning. Documents indexed before raw text was
    /// retained cannot be regenerated and are left untouched.
    #[uniffi::constructor(name = "withConfigRebuilding")]
    pub fn with_config_rebuilding(
        db_path: String,
        config: EngineConfig,
    ) -> Result<Arc<Self>, SearchError> {
        let conn = Self::open_schema(&db_path)?;
        let requested = config.normalize.as_key();
        let needs_rebuild = Self::stored_profile(&conn)?
            .map(|stored| stored != requested)
            .unwrap_or(false);
        let engine = Self::assemble(conn, config);
        if needs_rebuild {
            // `reindex` re-normalizes from raw and stamps the new profile.
            engine.reindex()?;
        } else {
            let conn = engine.conn.lock().unwrap();
            Self::stamp_profile(&conn, requested)?;
        }
        Ok(engine)
    }

    /// Adds, or replaces, the document stored under `id`.
    ///
    /// The host passes raw `text`; normalization runs inside the engine, so the
    /// engine's profile is applied identically to indexed text and to queries.
    /// Calling `index` again with an existing `id` overwrites that document.
    pub fn index(&self, id: i64, text: String) -> Result<(), SearchError> {
        let norm = self.normalizer.normalize(&text);
        let conn = self.conn.lock().unwrap();
        conn.execute("DELETE FROM docs WHERE rowid=?1", params![id])?;
        conn.execute(
            "INSERT INTO docs(rowid, norm) VALUES (?1, ?2)",
            params![id, &norm],
        )?;
        // The raw text is retained alongside `norm` so the index can be
        // regenerated under a different profile without the host re-feeding it.
        conn.execute(
            "INSERT OR REPLACE INTO entries(id, norm, raw) VALUES (?1, ?2, ?3)",
            params![id, &norm, &text],
        )?;
        Ok(())
    }

    /// Regenerates the index by re-normalizing every stored document's raw text
    /// with this engine's current profile, then stamps that profile.
    ///
    /// Use this after changing the normalization profile (or its underlying
    /// rules) to bring already-indexed documents back in sync without the host
    /// re-feeding them. Documents indexed before raw text was retained have no
    /// raw to normalize and are skipped. Returns the number of documents
    /// regenerated.
    pub fn reindex(&self) -> Result<u64, SearchError> {
        let conn = self.conn.lock().unwrap();
        let rows: Vec<(i64, String)> = {
            let mut stmt = conn.prepare("SELECT id, raw FROM entries WHERE raw IS NOT NULL")?;
            let mapped =
                stmt.query_map([], |r| Ok((r.get::<_, i64>(0)?, r.get::<_, String>(1)?)))?;
            mapped.collect::<Result<Vec<_>, _>>()?
        };
        let tx = conn.unchecked_transaction()?;
        for (id, raw) in &rows {
            let norm = self.normalizer.normalize(raw);
            tx.execute("UPDATE entries SET norm=?2 WHERE id=?1", params![id, &norm])?;
            tx.execute("DELETE FROM docs WHERE rowid=?1", params![id])?;
            tx.execute(
                "INSERT INTO docs(rowid, norm) VALUES (?1, ?2)",
                params![id, &norm],
            )?;
        }
        Self::stamp_profile(&tx, self.profile.as_key())?;
        tx.commit()?;
        Ok(rows.len() as u64)
    }

    /// Removes the document stored under `id`. A no-op if no such document
    /// exists.
    pub fn remove(&self, id: i64) -> Result<(), SearchError> {
        let conn = self.conn.lock().unwrap();
        conn.execute("DELETE FROM docs WHERE rowid=?1", params![id])?;
        conn.execute("DELETE FROM entries WHERE id=?1", params![id])?;
        Ok(())
    }

    /// Searches the index and returns at most `limit` hits.
    ///
    /// The `query` is normalized with the engine's profile and then matched
    /// using the engine's strategy. A query that is empty — or only whitespace
    /// once normalized — returns no hits. Ordering and scoring depend on the
    /// strategy (see `Hit.score`).
    pub fn search(&self, query: String, limit: u32) -> Result<Vec<Hit>, SearchError> {
        let q = self.normalizer.normalize(&query);
        if q.is_empty() {
            return Ok(Vec::new());
        }
        let conn = self.conn.lock().unwrap();
        self.strategy.search(&conn, &q, limit)
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::config::{NormalizeProfile, SearchStrategy};

    fn fresh() -> Arc<SearchEngine> {
        // In-memory DB (independent per test).
        SearchEngine::new(":memory:".to_string()).expect("open")
    }

    #[test]
    fn katakana_query_hits_hiragana_doc() {
        let e = fresh();
        e.index(1, "とうきょうタワー".into()).unwrap();
        let hits = e.search("トウキョウ".into(), 10).unwrap();
        assert_eq!(hits.len(), 1);
        assert_eq!(hits[0].id, 1);
    }

    #[test]
    fn hiragana_query_hits_kanji_mixed_doc() {
        let e = fresh();
        e.index(42, "東京 ﾄｳｷｮｳ タワー".into()).unwrap();
        let hits = e.search("とうきょう".into(), 10).unwrap();
        assert_eq!(hits.len(), 1);
        assert_eq!(hits[0].id, 42);
    }

    #[test]
    fn dakuten_is_distinguished() {
        let e = fresh();
        e.index(1, "がっこう".into()).unwrap();
        e.index(2, "かっこう".into()).unwrap();
        let hits = e.search("がっこう".into(), 10).unwrap();
        let ids: Vec<i64> = hits.iter().map(|h| h.id).collect();
        assert_eq!(ids, vec![1]);
    }

    #[test]
    fn short_query_uses_like_fallback() {
        // A 2-char query cannot be served by trigram, so it must take the LIKE path.
        let e = fresh();
        e.index(1, "がっこう".into()).unwrap();
        e.index(2, "かばん".into()).unwrap();
        let hits = e.search("がっ".into(), 10).unwrap();
        let ids: Vec<i64> = hits.iter().map(|h| h.id).collect();
        assert_eq!(ids, vec![1]);
    }

    #[test]
    fn fullwidth_alpha_folded() {
        let e = fresh();
        e.index(1, "Ｐｙｔｈｏｎ 入門".into()).unwrap();
        let hits = e.search("python".into(), 10).unwrap();
        assert_eq!(hits.len(), 1);
        assert_eq!(hits[0].id, 1);
    }

    #[test]
    fn remove_then_search_returns_none() {
        let e = fresh();
        e.index(1, "とうきょう".into()).unwrap();
        e.remove(1).unwrap();
        let hits = e.search("とうきょう".into(), 10).unwrap();
        assert!(hits.is_empty());
    }

    #[test]
    fn reindex_updates_text() {
        let e = fresh();
        e.index(1, "おおさか".into()).unwrap();
        e.index(1, "なごや".into()).unwrap();
        assert!(e.search("おおさか".into(), 10).unwrap().is_empty());
        let hits = e.search("なごや".into(), 10).unwrap();
        assert_eq!(hits.len(), 1);
        assert_eq!(hits[0].id, 1);
    }

    #[test]
    fn quote_in_query_is_escaped() {
        let e = fresh();
        e.index(1, r#"say "hello" world"#.into()).unwrap();
        let hits = e.search(r#""hello""#.into(), 10).unwrap();
        assert_eq!(hits.len(), 1);
        assert_eq!(hits[0].id, 1);
    }

    #[test]
    fn empty_query_returns_empty() {
        let e = fresh();
        e.index(1, "anything".into()).unwrap();
        assert!(e.search("".into(), 10).unwrap().is_empty());
    }

    // --- new behaviour: configurable strategy / profile ---

    fn fresh_with(config: EngineConfig) -> Arc<SearchEngine> {
        SearchEngine::with_config(":memory:".to_string(), config).expect("open")
    }

    #[test]
    fn prefix_strategy_matches_only_prefix() {
        let e = fresh_with(EngineConfig {
            normalize: NormalizeProfile::Loose,
            strategy: SearchStrategy::Prefix,
        });
        e.index(1, "tokyo tower".into()).unwrap();
        e.index(2, "old tokyo".into()).unwrap();
        let ids: Vec<i64> = e
            .search("tokyo".into(), 10)
            .unwrap()
            .iter()
            .map(|h| h.id)
            .collect();
        assert_eq!(ids, vec![1]);
    }

    #[test]
    fn substring_strategy_matches_anywhere_even_short() {
        let e = fresh_with(EngineConfig {
            normalize: NormalizeProfile::Loose,
            strategy: SearchStrategy::Substring,
        });
        e.index(1, "abcdef".into()).unwrap();
        // 2-char query in the middle: substring strategy must still find it.
        let ids: Vec<i64> = e
            .search("cd".into(), 10)
            .unwrap()
            .iter()
            .map(|h| h.id)
            .collect();
        assert_eq!(ids, vec![1]);
    }

    #[test]
    fn suffix_strategy_matches_only_trailing() {
        let e = fresh_with(EngineConfig {
            normalize: NormalizeProfile::Loose,
            strategy: SearchStrategy::Suffix,
        });
        e.index(1, "tokyo tower".into()).unwrap();
        e.index(2, "tower crane".into()).unwrap();
        // Only the doc that ENDS with "tower" matches; mid-string "tower" must not.
        let ids: Vec<i64> = e
            .search("tower".into(), 10)
            .unwrap()
            .iter()
            .map(|h| h.id)
            .collect();
        assert_eq!(ids, vec![1]);
    }

    #[test]
    fn all_terms_strategy_requires_every_term_any_order() {
        let e = fresh_with(EngineConfig {
            normalize: NormalizeProfile::Loose,
            strategy: SearchStrategy::AllTerms,
        });
        e.index(1, "tokyo sky tree".into()).unwrap();
        e.index(2, "tokyo tower".into()).unwrap();
        e.index(3, "sky high".into()).unwrap();
        // "sky tokyo": both terms present in doc 1 (order-independent); doc 2 lacks
        // "sky", doc 3 lacks "tokyo".
        let ids: Vec<i64> = e
            .search("sky tokyo".into(), 10)
            .unwrap()
            .iter()
            .map(|h| h.id)
            .collect();
        assert_eq!(ids, vec![1]);
        // Contrast with Substring, which would need the literal run "sky tokyo".
        let sub = fresh_with(EngineConfig {
            normalize: NormalizeProfile::Loose,
            strategy: SearchStrategy::Substring,
        });
        sub.index(1, "tokyo sky tree".into()).unwrap();
        assert!(sub.search("sky tokyo".into(), 10).unwrap().is_empty());
    }

    #[test]
    fn fuzzy_trigram_tolerates_a_typo_and_ranks_exact_first() {
        let e = fresh_with(EngineConfig {
            normalize: NormalizeProfile::Loose,
            strategy: SearchStrategy::FuzzyTrigram,
        });
        e.index(1, "international".into()).unwrap();
        e.index(2, "supercalifragilistic".into()).unwrap();
        // One-character typo ("...nai" instead of "...nal") still finds doc 1,
        // and the unrelated doc shares no trigrams so it is filtered out.
        let ids: Vec<i64> = e
            .search("internationai".into(), 10)
            .unwrap()
            .iter()
            .map(|h| h.id)
            .collect();
        assert_eq!(ids, vec![1]);
        // An exact query scores 0.0 (similarity 1.0).
        let exact = e.search("international".into(), 10).unwrap();
        assert_eq!(exact[0].id, 1);
        assert!(exact[0].score.abs() < 1e-9);
    }

    #[test]
    fn levenshtein_matches_one_char_typo() {
        let e = fresh_with(EngineConfig {
            normalize: NormalizeProfile::Loose,
            strategy: SearchStrategy::Levenshtein,
        });
        e.index(1, "tokyo tower".into()).unwrap();
        e.index(2, "osaka castle".into()).unwrap();
        // "tokio" is 1 substitution from the word "tokyo"; threshold for a
        // 5-char query is 1, so it matches doc 1 only.
        let ids: Vec<i64> = e
            .search("tokio".into(), 10)
            .unwrap()
            .iter()
            .map(|h| h.id)
            .collect();
        assert_eq!(ids, vec![1]);
    }

    #[test]
    fn damerau_matches_transposition_that_levenshtein_misses() {
        // "tokoy" is a single adjacent transposition of "tokyo": OSA distance 1,
        // plain Levenshtein distance 2. With the 5-char threshold (=1), only the
        // Damerau strategy matches.
        let lev = fresh_with(EngineConfig {
            normalize: NormalizeProfile::Loose,
            strategy: SearchStrategy::Levenshtein,
        });
        lev.index(1, "tokyo tower".into()).unwrap();
        assert!(lev.search("tokoy".into(), 10).unwrap().is_empty());

        let dl = fresh_with(EngineConfig {
            normalize: NormalizeProfile::Loose,
            strategy: SearchStrategy::DamerauLevenshtein,
        });
        dl.index(1, "tokyo tower".into()).unwrap();
        let ids: Vec<i64> = dl
            .search("tokoy".into(), 10)
            .unwrap()
            .iter()
            .map(|h| h.id)
            .collect();
        assert_eq!(ids, vec![1]);
    }

    #[test]
    fn nfkc_case_fold_keeps_katakana_distinct() {
        let e = fresh_with(EngineConfig {
            normalize: NormalizeProfile::NfkcCaseFold,
            strategy: SearchStrategy::Substring,
        });
        e.index(1, "カタカナ".into()).unwrap();
        // Hiragana query must NOT hit the katakana doc under this profile.
        assert!(e.search("かたかな".into(), 10).unwrap().is_empty());
        assert_eq!(e.search("カタカナ".into(), 10).unwrap().len(), 1);
    }

    #[test]
    fn reindex_returns_count_of_stored_documents() {
        let e = fresh();
        e.index(1, "とうきょう".into()).unwrap();
        e.index(2, "おおさか".into()).unwrap();
        e.index(3, "なごや".into()).unwrap();
        // Re-normalizing under the same profile is a no-op for results but still
        // reports every retained document.
        assert_eq!(e.reindex().unwrap(), 3);
        let hits = e.search("とうきょう".into(), 10).unwrap();
        assert_eq!(hits.len(), 1);
        assert_eq!(hits[0].id, 1);
    }

    fn temp_db_path(tag: &str) -> String {
        let path = std::env::temp_dir().join(format!(
            "unfydqry_test_{}_{}.sqlite",
            tag,
            std::process::id()
        ));
        let _ = std::fs::remove_file(&path);
        path.to_string_lossy().to_string()
    }

    #[test]
    fn with_config_rebuilding_reindexes_on_profile_change() {
        let p = temp_db_path("rebuild");
        {
            // Index under the loose profile: katakana folds to hiragana, so a
            // hiragana query hits the katakana document.
            let e = SearchEngine::new(p.clone()).expect("open loose");
            e.index(1, "カタカナ".into()).unwrap();
            assert_eq!(e.search("かたかな".into(), 10).unwrap().len(), 1);
        }
        // Reopen under a profile that keeps kana variants distinct. Rather than
        // erroring, the engine regenerates the index from the retained raw text.
        let rebuilt = SearchEngine::with_config_rebuilding(
            p.clone(),
            EngineConfig {
                normalize: NormalizeProfile::NfkcCaseFold,
                strategy: SearchStrategy::Substring,
            },
        )
        .expect("rebuild");
        // Under the new profile the hiragana query no longer matches the
        // katakana document, but the exact katakana query does — proving the
        // stored norm was regenerated from raw under NfkcCaseFold.
        assert!(rebuilt.search("かたかな".into(), 10).unwrap().is_empty());
        assert_eq!(rebuilt.search("カタカナ".into(), 10).unwrap().len(), 1);

        // The new profile is now stamped, so a plain `withConfig` open with the
        // same profile succeeds (no mismatch).
        drop(rebuilt);
        SearchEngine::with_config(
            p.clone(),
            EngineConfig {
                normalize: NormalizeProfile::NfkcCaseFold,
                strategy: SearchStrategy::Substring,
            },
        )
        .expect("reopen with rebuilt profile");

        let _ = std::fs::remove_file(&p);
    }

    #[test]
    fn profile_mismatch_on_reopen_errors() {
        let dir = std::env::temp_dir();
        let path = dir.join(format!("unfydqry_test_{}.sqlite", std::process::id()));
        let _ = std::fs::remove_file(&path);
        let p = path.to_string_lossy().to_string();

        {
            let e = SearchEngine::new(p.clone()).expect("open loose");
            e.index(1, "とうきょう".into()).unwrap();
        }
        // Reopen the same indexed DB with a different normalize profile.
        let reopened = SearchEngine::with_config(
            p.clone(),
            EngineConfig {
                normalize: NormalizeProfile::NfkcCaseFold,
                strategy: SearchStrategy::TrigramBm25,
            },
        );
        assert!(
            matches!(reopened, Err(SearchError::ConfigMismatch { .. })),
            "must reject profile mismatch"
        );
        drop(reopened);

        // Reopening with the original (loose) profile still works.
        SearchEngine::new(p.clone()).expect("reopen loose");

        let _ = std::fs::remove_file(&path);
    }
}
