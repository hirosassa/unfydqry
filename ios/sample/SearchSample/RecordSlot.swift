/// Field slots for the record-layer API. Raw values are the slot numbers baked
/// into the FFI record layer and the on-disk index, so they are stable and must
/// never be renumbered — only appended.
enum RecordSlot: UInt8, CaseIterable {
    case name = 0
    case yomi = 1

    /// Human-readable label for this slot.
    var label: String {
        switch self {
        case .name: return "名前"
        case .yomi: return "よみ"
        }
    }

    /// Number of fields per record, derived from the defined slots.
    static var fieldCount: UInt32 { UInt32(allCases.count) }

    /// Label for a raw slot value as returned by the engine (e.g. `matchedSlots`).
    static func label(for slot: UInt8) -> String {
        RecordSlot(rawValue: slot)?.label ?? "slot \(slot)"
    }
}
