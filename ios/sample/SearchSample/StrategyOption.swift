import UnifiedQuery

/// UI-facing list of search algorithms, mapped to the FFI enum.
enum StrategyOption: String, CaseIterable, Identifiable {
    case trigramBm25
    case substring
    case prefix
    case suffix
    case allTerms
    case fuzzyTrigram
    case levenshtein
    case damerauLevenshtein

    var id: String { rawValue }

    var label: String {
        switch self {
        case .trigramBm25: return "trigram + bm25"
        case .substring: return "substring"
        case .prefix: return "prefix"
        case .suffix: return "suffix"
        case .allTerms: return "all terms"
        case .fuzzyTrigram: return "fuzzy trigram"
        case .levenshtein: return "levenshtein"
        case .damerauLevenshtein: return "damerau-levenshtein"
        }
    }

    var ffi: SearchStrategy {
        switch self {
        case .trigramBm25: return .trigramBm25
        case .substring: return .substring
        case .prefix: return .prefix
        case .suffix: return .suffix
        case .allTerms: return .allTerms
        case .fuzzyTrigram: return .fuzzyTrigram
        case .levenshtein: return .levenshtein
        case .damerauLevenshtein: return .damerauLevenshtein
        }
    }
}
