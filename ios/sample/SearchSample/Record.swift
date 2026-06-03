/// Minimal multi-field record that stands in for the app's "source-of-truth DB".
/// In a real app this would be a SwiftData / Core Data entity with several
/// searchable columns.
struct Record: Identifiable, Hashable {
    let id: Int64
    let name: String
    let yomi: String
}
