/// Which query algorithm [SearchEngine.search] / [SearchEngine.searchRecords]
/// use. Mirrors the native `SearchStrategy` enum of the Rust/UniFFI core.
///
/// The strategy is not part of the index fingerprint, so switching it does not
/// require a reindex (see [SearchEngine.reindexStatus]).
enum SearchStrategy {
  /// Trigram FTS5 + bm25, with a LIKE fallback for queries shorter than 3 chars.
  trigramBm25('TRIGRAM_BM25', 'trigram + bm25'),

  /// Substring match (`LIKE '%q%'`) for every query.
  substring('SUBSTRING', 'substring'),

  /// Prefix match (`LIKE 'q%'`) for every query.
  prefix('PREFIX', 'prefix'),

  /// Suffix match (`LIKE '%q'`) for every query.
  suffix('SUFFIX', 'suffix'),

  /// Every whitespace-separated term must appear (substring), order-independent.
  allTerms('ALL_TERMS', 'all terms'),

  /// Fuzzy trigram overlap ranking.
  fuzzyTrigram('FUZZY_TRIGRAM', 'fuzzy trigram'),

  /// Levenshtein edit distance.
  levenshtein('LEVENSHTEIN', 'levenshtein'),

  /// Damerau-Levenshtein edit distance (also counts transpositions).
  damerauLevenshtein('DAMERAU_LEVENSHTEIN', 'damerau-levenshtein');

  const SearchStrategy(this.wireName, this.label);

  /// Stable identifier sent over the method channel; the native side maps it
  /// to its own `SearchStrategy` enum case. Never renumber/rename.
  final String wireName;

  /// Human-readable label for the UI.
  final String label;

  /// Resolves a [wireName] coming back from the platform, defaulting to
  /// [trigramBm25] for unknown values.
  static SearchStrategy fromWire(String? wire) {
    for (final s in SearchStrategy.values) {
      if (s.wireName == wire) return s;
    }
    return SearchStrategy.trigramBm25;
  }
}
