package com.unfydqry.searchsample

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material3.Button
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Surface
import androidx.compose.material3.Switch
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TopAppBar
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateListOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import kotlinx.coroutines.delay
import uniffi.unfydqry.EngineOptionsConfig
import uniffi.unfydqry.NormalizeOptions
import uniffi.unfydqry.SearchEngine
import uniffi.unfydqry.SearchStrategy
import uniffi.unfydqry.normalizeWithOptions

/// Minimal record standing in for the app's "source-of-truth DB" (equivalent to a
/// SwiftData / Room entity).
data class Record(val id: Long, val text: String)

/// The `loose` preset as composable options (lowercase + kana fold).
private fun looseOptions() = NormalizeOptions(lowercase = true, kanaFold = true)

/// One normalization step toggle, bound to a field of [NormalizeOptions].
private data class StepToggle(
    val label: String,
    val get: (NormalizeOptions) -> Boolean,
    val set: (NormalizeOptions, Boolean) -> NormalizeOptions,
)

private val stepToggles = listOf(
    StepToggle("小文字化", { it.lowercase }, { o, v -> o.copy(lowercase = v) }),
    StepToggle("カナ→かな", { it.kanaFold }, { o, v -> o.copy(kanaFold = v) }),
    StepToggle("アクセント除去 (café→cafe)", { it.foldDiacritics }, { o, v -> o.copy(foldDiacritics = v) }),
    StepToggle("長音畳み込み (サーバー→サーバ)", { it.foldChoonpu }, { o, v -> o.copy(foldChoonpu = v) }),
    StepToggle("繰り返し記号展開 (時々→時時)", { it.expandIterationMarks }, { o, v -> o.copy(expandIterationMarks = v) }),
    StepToggle("ハイフン統一", { it.normalizeHyphens }, { o, v -> o.copy(normalizeHyphens = v) }),
    StepToggle("桁区切り除去 (1,000→1000)", { it.stripDigitGrouping }, { o, v -> o.copy(stripDigitGrouping = v) }),
    StepToggle("空白圧縮", { it.collapseWhitespace }, { o, v -> o.copy(collapseWhitespace = v) }),
)

private fun strategyLabel(s: SearchStrategy): String = when (s) {
    SearchStrategy.TRIGRAM_BM25 -> "trigram + bm25"
    SearchStrategy.SUBSTRING -> "substring"
    SearchStrategy.PREFIX -> "prefix"
    SearchStrategy.SUFFIX -> "suffix"
    SearchStrategy.ALL_TERMS -> "all terms"
    SearchStrategy.FUZZY_TRIGRAM -> "fuzzy trigram"
    SearchStrategy.LEVENSHTEIN -> "levenshtein"
    SearchStrategy.DAMERAU_LEVENSHTEIN -> "damerau-levenshtein"
}

class MainActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        val dbPath = filesDir.resolve("search_index.sqlite").absolutePath
        val engine = SearchEngine.withOptionsRebuilding(
            dbPath,
            EngineOptionsConfig(looseOptions(), SearchStrategy.TRIGRAM_BM25),
        )
        val store = seed(engine)
        setContent {
            MaterialTheme {
                Surface(modifier = Modifier.fillMaxSize()) {
                    SearchScreen(engine, store, dbPath)
                }
            }
        }
    }

    // Same seed as the iOS sample, so the same hit IDs can be eyeballed across both OSes.
    // Returns the id → Record store used to re-fetch records.
    private fun seed(engine: SearchEngine): Map<Long, Record> {
        val docs = listOf(
            Record(1L, "東京タワー"),
            Record(2L, "とうきょうスカイツリー"),
            Record(3L, "ﾄｳｷｮｳ ﾄﾞｰﾑ"),
            Record(4L, "Osaka 城"),
            Record(5L, "がっこう ぐらし"),
            Record(6L, "かっこう の歌"),
            Record(7L, "Ｐｙｔｈｏｎ 入門"),
            Record(8L, "ぱんだ と ﾊﾟﾝﾀﾞ"),
            Record(9L, "コーヒーサーバー"),
            Record(10L, "café オレ"),
        )
        docs.forEach { engine.index(it.id, it.text) }
        return docs.associateBy { it.id }
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun SearchScreen(initialEngine: SearchEngine, store: Map<Long, Record>, dbPath: String) {
    var engine by remember { mutableStateOf(initialEngine) }
    var query by remember { mutableStateOf("") }
    var options by remember { mutableStateOf(looseOptions()) }
    var strategy by remember { mutableStateOf(SearchStrategy.TRIGRAM_BM25) }
    var status by remember { mutableStateOf("") }
    var showSettings by remember { mutableStateOf(false) }
    val allDocs = remember(store) { store.values.sortedBy { it.id } }
    // Prefilled so the initial empty query shows every doc without a flash.
    val results = remember { mutableStateListOf<Record>().apply { addAll(allDocs) } }

    fun runSearch() {
        if (query.isBlank()) {
            results.clear()
            results.addAll(allDocs)
            status = "全件表示 (${results.size})"
            return
        }
        val hits = engine.search(query, 50u)
        // Minimal implementation of design doc §1.3 ("return IDs only / re-fetch
        // from the source-of-truth DB").
        val records = hits.mapNotNull { store[it.id] }
        results.clear()
        results.addAll(records)
        status = "hits: ${records.size}  normalized=\"${normalizeWithOptions(query, options)}\""
    }

    // Changing the steps/strategy regenerates the index in place from the retained
    // raw text (withOptionsRebuilding), then refreshes results.
    fun reconfigure(newOptions: NormalizeOptions, newStrategy: SearchStrategy) {
        val old = engine
        engine = SearchEngine.withOptionsRebuilding(
            dbPath,
            EngineOptionsConfig(newOptions, newStrategy),
        )
        old.close()
        runSearch()
    }

    // Incremental search: debounce keystrokes so a search runs shortly after typing
    // settles rather than on every character.
    LaunchedEffect(query) {
        delay(150)
        runSearch()
    }

    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text("SearchSample") },
                actions = { TextButton(onClick = { showSettings = true }) { Text("設定") } },
            )
        },
    ) { padding ->
        Column(modifier = Modifier.fillMaxSize().padding(padding).padding(horizontal = 16.dp)) {
            OutlinedTextField(
                value = query,
                onValueChange = { query = it },
                label = { Text("検索 (全角/半角/カナ/ひら、なんでも)") },
                singleLine = true,
                trailingIcon = {
                    if (query.isNotEmpty()) {
                        TextButton(onClick = { query = "" }) { Text("✕") }
                    }
                },
                modifier = Modifier.fillMaxWidth(),
            )
            Spacer(Modifier.height(4.dp))
            Text(status, style = MaterialTheme.typography.bodySmall)
            Spacer(Modifier.height(8.dp))
            LazyColumn(modifier = Modifier.fillMaxSize()) {
                items(results, key = { it.id }) { record ->
                    Column(modifier = Modifier.fillMaxWidth().padding(vertical = 6.dp)) {
                        Text(record.text, style = MaterialTheme.typography.bodyLarge)
                        Text(
                            "id=${record.id}",
                            style = MaterialTheme.typography.bodySmall,
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                        )
                    }
                }
            }
        }
    }

    if (showSettings) {
        val sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true)
        ModalBottomSheet(onDismissRequest = { showSettings = false }, sheetState = sheetState) {
            SettingsSheet(
                options = options,
                strategy = strategy,
                onToggle = { newOptions -> options = newOptions; reconfigure(newOptions, strategy) },
                onStrategy = { newStrategy -> strategy = newStrategy; reconfigure(options, newStrategy) },
                onReindex = {
                    val count = engine.reindex()
                    status = "reindexed $count docs"
                    runSearch()
                },
            )
        }
    }
}

@Composable
private fun SettingsSheet(
    options: NormalizeOptions,
    strategy: SearchStrategy,
    onToggle: (NormalizeOptions) -> Unit,
    onStrategy: (SearchStrategy) -> Unit,
    onReindex: () -> Unit,
) {
    Column(modifier = Modifier.fillMaxWidth().padding(horizontal = 16.dp).padding(bottom = 24.dp)) {
        Text("正規化ステップ", style = MaterialTheme.typography.titleSmall)
        Spacer(Modifier.height(8.dp))
        stepToggles.forEach { step ->
            Row(
                modifier = Modifier.fillMaxWidth().padding(vertical = 4.dp),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Switch(
                    checked = step.get(options),
                    onCheckedChange = { v -> onToggle(step.set(options, v)) },
                )
                Spacer(Modifier.width(12.dp))
                Text(step.label, style = MaterialTheme.typography.bodyMedium)
            }
        }

        Spacer(Modifier.height(8.dp))
        HorizontalDivider()
        Spacer(Modifier.height(8.dp))

        Text("検索アルゴリズム", style = MaterialTheme.typography.titleSmall)
        Spacer(Modifier.height(4.dp))
        var expanded by remember { mutableStateOf(false) }
        Button(onClick = { expanded = true }) { Text(strategyLabel(strategy)) }
        DropdownMenu(expanded = expanded, onDismissRequest = { expanded = false }) {
            SearchStrategy.values().forEach { s ->
                DropdownMenuItem(
                    text = { Text(strategyLabel(s)) },
                    onClick = { expanded = false; onStrategy(s) },
                )
            }
        }

        Spacer(Modifier.height(16.dp))
        Button(
            onClick = onReindex,
            modifier = Modifier.fillMaxWidth(),
        ) { Text("インデックス再生成") }
        Text(
            "保存済みの生テキストから現在の設定で再生成します。",
            style = MaterialTheme.typography.bodySmall,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
            modifier = Modifier.padding(top = 4.dp),
        )
    }
}
