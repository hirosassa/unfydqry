import Foundation
import UnifiedQuery

extension NormalizeOptions {
    /// The `loose` preset as composable options (lowercase + kana fold).
    static var loose: NormalizeOptions {
        NormalizeOptions(
            lowercase: true,
            kanaFold: true,
            foldDiacritics: false,
            foldChoonpu: false,
            expandIterationMarks: false,
            normalizeHyphens: false,
            stripDigitGrouping: false,
            collapseWhitespace: false
        )
    }

    /// Builds options from a comma-separated list of step ids (see `OptionToggle.all`).
    init(stepIds raw: String) {
        let enabled = Set(raw.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) })
        self.init(
            lowercase: false, kanaFold: false, foldDiacritics: false, foldChoonpu: false,
            expandIterationMarks: false, normalizeHyphens: false,
            stripDigitGrouping: false, collapseWhitespace: false
        )
        for toggle in OptionToggle.all where enabled.contains(toggle.id) {
            self[keyPath: toggle.keyPath] = true
        }
    }
}
