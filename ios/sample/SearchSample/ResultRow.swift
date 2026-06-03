/// A search result row: the matched record plus which of its fields matched.
struct ResultRow: Identifiable, Hashable {
    let record: Record
    let matchedSlots: [UInt8]
    var id: Int64 { record.id }
}
