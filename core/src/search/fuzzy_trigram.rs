//! Character-trigram set similarity (Jaccard) with FTS5 pre-filtering.
//!
//! The query and each candidate document are reduced to their sets of character
//! trigrams, and documents whose Jaccard similarity to the query clears a
//! threshold are returned, ranked by `1 − similarity` (exact match = `0.0`).
//!
//! For queries of 3+ characters, the FTS5 trigram index is used to narrow
//! candidates before computing Jaccard in Rust.  Queries shorter than 3 chars
//! fall back to a full table scan (FTS5 trigram cannot match them).
//!
//! Trigrams are stored as `[char; 3]` (12 bytes on the stack) rather than
//! heap-allocated `String`s to avoid per-trigram allocation.

use std::collections::HashSet;

use rusqlite::{Connection, params};

use super::SearchAlgorithm;
use crate::engine::{Hit, SearchError};

/// Minimum Jaccard similarity for a document to be considered a match.
const THRESHOLD: f64 = 0.3;

fn trigrams(s: &str) -> HashSet<[char; 3]> {
    let chars: Vec<char> = s.chars().collect();
    let mut set = HashSet::new();
    if chars.len() < 3 {
        return set;
    }
    for w in chars.windows(3) {
        set.insert([w[0], w[1], w[2]]);
    }
    set
}

/// For short strings (< 3 chars), Jaccard uses the whole string as a single
/// element.  This avoids mixing `[char; 3]` trigrams with variable-length
/// tokens in the same set.
fn short_jaccard(query: &str, doc: &str) -> f64 {
    if query == doc { 1.0 } else { 0.0 }
}

fn jaccard(a: &HashSet<[char; 3]>, b: &HashSet<[char; 3]>) -> f64 {
    let inter = a.intersection(b).count();
    let union = a.len() + b.len() - inter;
    if union == 0 {
        0.0
    } else {
        inter as f64 / union as f64
    }
}

/// Builds an FTS5 MATCH expression that ORs all trigrams as phrase queries.
fn build_fts5_or(tset: &HashSet<[char; 3]>) -> Option<String> {
    if tset.is_empty() {
        return None;
    }
    let parts: Vec<String> = tset
        .iter()
        .map(|t| {
            let s: String = t.iter().collect();
            format!("\"{}\"", s.replace('"', "\"\""))
        })
        .collect();
    Some(parts.join(" OR "))
}

pub struct FuzzyTrigram;

impl SearchAlgorithm for FuzzyTrigram {
    fn search(&self, conn: &Connection, q: &str, limit: u32) -> Result<Vec<Hit>, SearchError> {
        let q_chars: Vec<char> = q.chars().collect();
        let is_short = q_chars.len() < 3;

        if q_chars.is_empty() {
            return Ok(Vec::new());
        }

        if is_short {
            // Short queries: full scan with exact-string comparison.
            let mut stmt = conn.prepare("SELECT id, norm FROM entries")?;
            let rows = stmt.query_map([], |r| Ok((r.get::<_, i64>(0)?, r.get::<_, String>(1)?)))?;

            let mut hits: Vec<Hit> = Vec::new();
            for row in rows {
                let (id, norm) = row?;
                let sim = short_jaccard(q, &norm);
                if sim >= THRESHOLD {
                    hits.push(Hit {
                        id,
                        score: 1.0 - sim,
                    });
                }
            }
            hits.sort_by(|a, b| {
                a.score
                    .partial_cmp(&b.score)
                    .unwrap_or(std::cmp::Ordering::Equal)
                    .then(a.id.cmp(&b.id))
            });
            hits.truncate(limit as usize);
            return Ok(hits);
        }

        // 3+ char queries: use trigram sets.
        let qset = trigrams(q);
        let match_expr = build_fts5_or(&qset).expect("3+ char query always produces trigrams");
        let mut stmt = conn.prepare("SELECT rowid, norm FROM docs WHERE docs MATCH ?1")?;
        let rows = stmt.query_map(params![match_expr], |r| {
            Ok((r.get::<_, i64>(0)?, r.get::<_, String>(1)?))
        })?;

        let mut hits: Vec<Hit> = Vec::new();
        for row in rows {
            let (id, norm) = row?;
            let sim = jaccard(&qset, &trigrams(&norm));
            if sim >= THRESHOLD {
                hits.push(Hit {
                    id,
                    score: 1.0 - sim,
                });
            }
        }
        hits.sort_by(|a, b| {
            a.score
                .partial_cmp(&b.score)
                .unwrap_or(std::cmp::Ordering::Equal)
                .then(a.id.cmp(&b.id))
        });
        hits.truncate(limit as usize);
        Ok(hits)
    }
}
