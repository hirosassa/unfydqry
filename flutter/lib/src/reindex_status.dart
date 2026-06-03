/// Whether the stored index matches a requested normalization profile.
///
/// Mirrors the native `ReindexStatus` enum, returned by
/// [SearchEngine.reindexStatus].
enum ReindexStatus {
  /// The index holds no documents; any normalization can be adopted freely
  /// (the next index call stamps the profile).
  empty('EMPTY'),

  /// The stored documents were already normalized with the requested options.
  /// The index is ready to query as-is.
  upToDate('UP_TO_DATE'),

  /// The stored documents were normalized under different options. Querying
  /// as-is would return wrong results — regenerate via
  /// [SearchEngine.openWithOptionsRebuilding] before use.
  configChanged('CONFIG_CHANGED');

  const ReindexStatus(this.wireName);

  /// Stable identifier exchanged over the method channel.
  final String wireName;

  /// Resolves a [wireName] coming back from the platform, defaulting to
  /// [upToDate] for unknown values.
  static ReindexStatus fromWire(String? wire) {
    for (final s in ReindexStatus.values) {
      if (s.wireName == wire) return s;
    }
    return ReindexStatus.upToDate;
  }
}
