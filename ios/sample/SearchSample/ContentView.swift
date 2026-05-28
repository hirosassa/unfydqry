import Combine
import UnifiedQuery
import SwiftUI

/// Minimal record that stands in for the app's "source-of-truth DB".
/// In a real app this would be a SwiftData / Core Data entity.
struct Record: Identifiable, Hashable {
    let id: Int64
    let text: String
}

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

/// One normalization step toggle, bound to a field of `NormalizeOptions`.
struct OptionToggle: Identifiable {
    let id: String
    let label: String
    let keyPath: WritableKeyPath<NormalizeOptions, Bool>
}

let optionToggles: [OptionToggle] = [
    OptionToggle(id: "lowercase", label: "小文字化", keyPath: \.lowercase),
    OptionToggle(id: "kana_fold", label: "カナ→かな", keyPath: \.kanaFold),
    OptionToggle(id: "fold_diacritics", label: "アクセント除去 (café→cafe)", keyPath: \.foldDiacritics),
    OptionToggle(id: "fold_choonpu", label: "長音畳み込み (サーバー→サーバ)", keyPath: \.foldChoonpu),
    OptionToggle(id: "expand_iteration_marks", label: "繰り返し記号展開 (時々→時時)", keyPath: \.expandIterationMarks),
    OptionToggle(id: "normalize_hyphens", label: "ハイフン統一", keyPath: \.normalizeHyphens),
    OptionToggle(id: "strip_digit_grouping", label: "桁区切り除去 (1,000→1000)", keyPath: \.stripDigitGrouping),
    OptionToggle(id: "collapse_whitespace", label: "空白圧縮", keyPath: \.collapseWhitespace),
]

/// The `loose` preset as composable options (lowercase + kana fold).
private func looseOptions() -> NormalizeOptions {
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

@MainActor
final class SearchModel: ObservableObject {
    /// Bound to the standard search bar (`.searchable`); changes drive an
    /// incremental, debounced search.
    @Published var query: String = ""
    @Published var status: String = ""
    @Published var results: [Record] = []

    /// Toggling any normalization step or strategy rebuilds the engine.
    @Published var options: NormalizeOptions = looseOptions() {
        didSet { if options != oldValue { reconfigure() } }
    }
    @Published var strategy: StrategyOption = .trigramBm25 {
        didSet { if strategy != oldValue { reconfigure() } }
    }

    private var engine: SearchEngine
    private let dbPath: String
    /// The engine returns only IDs and scores, so the host side maps id → Record.
    private var store: [Int64: Record] = [:]
    private var cancellables = Set<AnyCancellable>()

    init() {
        let url = FileManager.default
            .urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("search_index.sqlite")
        self.dbPath = url.path
        do {
            self.engine = try SearchModel.makeEngine(
                options: looseOptions(), strategy: .trigramBm25, dbPath: url.path
            )
        } catch {
            fatalError("open SearchEngine failed: \(error)")
        }
        seed()
        // Incremental search: debounce keystrokes so a search runs shortly after
        // typing settles rather than on every character.
        $query
            .debounce(for: .milliseconds(150), scheduler: RunLoop.main)
            .removeDuplicates()
            .sink { [weak self] _ in self?.search() }
            .store(in: &cancellables)
        search() // show all docs immediately for the initial empty query
        applyEnvHooks()
    }

    /// Opens the index for the given composable options. Changing the enabled
    /// steps regenerates the index in place from the retained raw text
    /// (`withOptionsRebuilding`), so the host never re-feeds documents.
    private static func makeEngine(
        options: NormalizeOptions, strategy: SearchStrategy, dbPath: String
    ) throws -> SearchEngine {
        try SearchEngine.withOptionsRebuilding(
            dbPath: dbPath,
            config: EngineOptionsConfig(normalize: options, strategy: strategy)
        )
    }

    /// Rebuilds the engine for the current options/strategy and refreshes results.
    private func reconfigure() {
        do {
            engine = try SearchModel.makeEngine(
                options: options, strategy: strategy.ffi, dbPath: dbPath
            )
            search()
        } catch {
            status = "reconfigure error: \(error)"
        }
    }

    private func seed() {
        let seed: [Record] = [
            Record(id: 1, text: "東京タワー"),
            Record(id: 2, text: "とうきょうスカイツリー"),
            Record(id: 3, text: "ﾄｳｷｮｳ ﾄﾞｰﾑ"),
            Record(id: 4, text: "Osaka 城"),
            Record(id: 5, text: "がっこう ぐらし"),
            Record(id: 6, text: "かっこう の歌"),
            Record(id: 7, text: "Ｐｙｔｈｏｎ 入門"),
            Record(id: 8, text: "ぱんだ と ﾊﾟﾝﾀﾞ"),
            Record(id: 9, text: "コーヒーサーバー"),
            Record(id: 10, text: "café オレ")
        ]
        for record in seed {
            try? engine.index(id: record.id, text: record.text)
            store[record.id] = record
        }
        status = "indexed \(seed.count) docs"
    }

    /// Explicitly regenerates the index from the retained raw text under the
    /// current settings (distinct from the automatic rebuild on a settings
    /// change). Useful after the normalization rules themselves change.
    func reindex() {
        do {
            let count = try engine.reindex()
            status = "reindexed \(count) docs"
            search()
        } catch {
            status = "reindex error: \(error)"
        }
    }

    func search() {
        guard !query.isEmpty else {
            // Empty query → show every indexed document (sorted by id for stability).
            results = store.values.sorted { $0.id < $1.id }
            status = "全件表示 (\(results.count))"
            return
        }
        do {
            let hits = try engine.search(query: query, limit: 50)
            results = hits.compactMap { store[$0.id] }
            let normalized = normalizeWithOptions(input: query, options: options)
            status = "hits: \(results.count)  normalized=\u{0022}\(normalized)\u{0022}"
        } catch {
            status = "error: \(error)"
            results = []
        }
    }

    /// UI-test hooks: preselect steps/strategy and/or a query on launch.
    /// SEARCH_OPTIONS is a comma-separated step id list (see `optionToggles`).
    private func applyEnvHooks() {
        let env = ProcessInfo.processInfo.environment
        guard env["SEARCH_AUTO_QUERY"] != nil || env["SEARCH_OPTIONS"] != nil
            || env["SEARCH_STRATEGY"] != nil else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            guard let self else { return }
            if let raw = env["SEARCH_OPTIONS"] {
                self.options = SearchModel.parseOptions(raw)
            }
            if let s = env["SEARCH_STRATEGY"].flatMap(StrategyOption.init(rawValue:)) {
                self.strategy = s
            }
            if let auto = env["SEARCH_AUTO_QUERY"] {
                self.query = auto
            }
        }
    }

    /// Builds options from a comma-separated list of step ids (see `optionToggles`).
    static func parseOptions(_ raw: String) -> NormalizeOptions {
        let enabled = Set(raw.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) })
        var options = NormalizeOptions(
            lowercase: false, kanaFold: false, foldDiacritics: false, foldChoonpu: false,
            expandIterationMarks: false, normalizeHyphens: false,
            stripDigitGrouping: false, collapseWhitespace: false
        )
        for toggle in optionToggles where enabled.contains(toggle.id) {
            options[keyPath: toggle.keyPath] = true
        }
        return options
    }
}

struct ContentView: View {
    @StateObject private var model = SearchModel()
    // UI-test hook: open the settings sheet on launch when SEARCH_SHOW_SETTINGS is set.
    @State private var showSettings =
        ProcessInfo.processInfo.environment["SEARCH_SHOW_SETTINGS"] != nil

    var body: some View {
        NavigationStack {
            List(model.results) { record in
                VStack(alignment: .leading, spacing: 4) {
                    Text(record.text).font(.body)
                    Text("id=\(record.id)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }
            .navigationTitle("SearchSample")
            .searchable(text: $model.query, prompt: "全角/半角/カナ/ひら、なんでも")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showSettings = true } label: {
                        Image(systemName: "gearshape")
                    }
                    .accessibilityLabel("設定")
                }
            }
            .safeAreaInset(edge: .bottom) {
                Text(model.status)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal)
                    .padding(.vertical, 6)
                    .background(.bar)
            }
            .sheet(isPresented: $showSettings) {
                SettingsView(model: model)
            }
        }
    }
}

/// Modal settings: normalization step toggles, the search algorithm, and an
/// explicit index-regeneration button.
struct SettingsView: View {
    @ObservedObject var model: SearchModel
    @Environment(\.dismiss) private var dismiss

    private func binding(_ keyPath: WritableKeyPath<NormalizeOptions, Bool>) -> Binding<Bool> {
        Binding(
            get: { model.options[keyPath: keyPath] },
            set: { model.options[keyPath: keyPath] = $0 }
        )
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("正規化ステップ") {
                    ForEach(optionToggles) { toggle in
                        Toggle(toggle.label, isOn: binding(toggle.keyPath))
                            .font(.callout)
                    }
                }
                Section("検索アルゴリズム") {
                    Picker("アルゴリズム", selection: $model.strategy) {
                        ForEach(StrategyOption.allCases) { Text($0.label).tag($0) }
                    }
                }
                Section {
                    Button("インデックス再生成") { model.reindex() }
                } footer: {
                    Text("保存済みの生テキストから現在の設定で再生成します。")
                }
            }
            .navigationTitle("設定")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("完了") { dismiss() }
                }
            }
        }
    }
}
