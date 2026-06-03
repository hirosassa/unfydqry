import UnifiedQuery

/// One normalization step toggle, bound to a field of `NormalizeOptions`.
struct OptionToggle: Identifiable {
    let id: String
    let label: String
    let keyPath: WritableKeyPath<NormalizeOptions, Bool>

    /// All normalization step toggles, in display order.
    static let all: [OptionToggle] = [
        OptionToggle(id: "lowercase", label: "小文字化", keyPath: \.lowercase),
        OptionToggle(id: "kana_fold", label: "カナ→かな", keyPath: \.kanaFold),
        OptionToggle(id: "fold_diacritics", label: "アクセント除去 (café→cafe)", keyPath: \.foldDiacritics),
        OptionToggle(id: "fold_choonpu", label: "長音畳み込み (サーバー→サーバ)", keyPath: \.foldChoonpu),
        OptionToggle(id: "expand_iteration_marks", label: "繰り返し記号展開 (時々→時時)", keyPath: \.expandIterationMarks),
        OptionToggle(id: "normalize_hyphens", label: "ハイフン統一", keyPath: \.normalizeHyphens),
        OptionToggle(id: "strip_digit_grouping", label: "桁区切り除去 (1,000→1000)", keyPath: \.stripDigitGrouping),
        OptionToggle(id: "collapse_whitespace", label: "空白圧縮", keyPath: \.collapseWhitespace),
    ]
}
