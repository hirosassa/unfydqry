/// Composable text-normalization steps applied at index and query time.
///
/// Mirrors the native `NormalizeOptions` of the Rust/UniFFI core. Each flag is
/// an independent step; the same options must be used when indexing and when
/// querying, otherwise stored documents need regenerating (see
/// [SearchEngine.reindexStatus]).
///
/// All steps default to `false`. Use [NormalizeOptions.loose] for the common
/// case-insensitive, kana-folding preset.
class NormalizeOptions {
  /// Fold case via Unicode lowercasing.
  final bool lowercase;

  /// Map katakana to hiragana (カ → か); dakuten stays distinct.
  final bool kanaFold;

  /// Strip Latin/Western combining diacritics (café → cafe).
  final bool foldDiacritics;

  /// Fold the prolonged-sound mark after kana (サーバー → サーバ).
  final bool foldChoonpu;

  /// Expand iteration marks (時々 → 時時, こゞ → こご).
  final bool expandIterationMarks;

  /// Unify the dash/hyphen family to ASCII `-`.
  final bool normalizeHyphens;

  /// Remove digit-grouping commas (1,000 → 1000).
  final bool stripDigitGrouping;

  /// Collapse whitespace runs to a single space and trim.
  final bool collapseWhitespace;

  const NormalizeOptions({
    this.lowercase = false,
    this.kanaFold = false,
    this.foldDiacritics = false,
    this.foldChoonpu = false,
    this.expandIterationMarks = false,
    this.normalizeHyphens = false,
    this.stripDigitGrouping = false,
    this.collapseWhitespace = false,
  });

  /// The `loose` preset: case-insensitive + katakana-to-hiragana folding.
  ///
  /// Matches the native `NormalizeOptions::loose()` used by the iOS and Android
  /// samples as the default profile.
  const NormalizeOptions.loose()
      : lowercase = true,
        kanaFold = true,
        foldDiacritics = false,
        foldChoonpu = false,
        expandIterationMarks = false,
        normalizeHyphens = false,
        stripDigitGrouping = false,
        collapseWhitespace = false;

  /// Returns a copy with the given fields replaced.
  NormalizeOptions copyWith({
    bool? lowercase,
    bool? kanaFold,
    bool? foldDiacritics,
    bool? foldChoonpu,
    bool? expandIterationMarks,
    bool? normalizeHyphens,
    bool? stripDigitGrouping,
    bool? collapseWhitespace,
  }) {
    return NormalizeOptions(
      lowercase: lowercase ?? this.lowercase,
      kanaFold: kanaFold ?? this.kanaFold,
      foldDiacritics: foldDiacritics ?? this.foldDiacritics,
      foldChoonpu: foldChoonpu ?? this.foldChoonpu,
      expandIterationMarks: expandIterationMarks ?? this.expandIterationMarks,
      normalizeHyphens: normalizeHyphens ?? this.normalizeHyphens,
      stripDigitGrouping: stripDigitGrouping ?? this.stripDigitGrouping,
      collapseWhitespace: collapseWhitespace ?? this.collapseWhitespace,
    );
  }

  /// Wire representation sent over the method channel. Keys match the native
  /// `NormalizeOptions` field names so the platform side maps them 1:1.
  Map<String, dynamic> toMap() => {
        'lowercase': lowercase,
        'kanaFold': kanaFold,
        'foldDiacritics': foldDiacritics,
        'foldChoonpu': foldChoonpu,
        'expandIterationMarks': expandIterationMarks,
        'normalizeHyphens': normalizeHyphens,
        'stripDigitGrouping': stripDigitGrouping,
        'collapseWhitespace': collapseWhitespace,
      };

  @override
  bool operator ==(Object other) =>
      other is NormalizeOptions &&
      other.lowercase == lowercase &&
      other.kanaFold == kanaFold &&
      other.foldDiacritics == foldDiacritics &&
      other.foldChoonpu == foldChoonpu &&
      other.expandIterationMarks == expandIterationMarks &&
      other.normalizeHyphens == normalizeHyphens &&
      other.stripDigitGrouping == stripDigitGrouping &&
      other.collapseWhitespace == collapseWhitespace;

  @override
  int get hashCode => Object.hash(
        lowercase,
        kanaFold,
        foldDiacritics,
        foldChoonpu,
        expandIterationMarks,
        normalizeHyphens,
        stripDigitGrouping,
        collapseWhitespace,
      );

  @override
  String toString() => 'NormalizeOptions(${toMap()})';
}
