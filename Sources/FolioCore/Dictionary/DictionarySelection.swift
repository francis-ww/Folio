import Foundation

public struct DictionarySelection: Codable, Sendable, Equatable {
    public private(set) var priority: [String]
    public private(set) var disabledIDs: Set<String>
    public init(priority: [String] = [], disabledIDs: Set<String> = []) {
        var seen: Set<String> = []
        self.priority = priority.filter { seen.insert($0).inserted }
        self.disabledIDs = disabledIDs
    }
    public func isEnabled(_ id: String) -> Bool { !disabledIDs.contains(id) }
    public mutating func setEnabled(_ enabled: Bool, id: String) {
        if enabled { disabledIDs.remove(id) } else { disabledIDs.insert(id) }
    }
    public mutating func reorder(_ ids: [String]) {
        self = Self(priority: ids + priority.filter { !ids.contains($0) }, disabledIDs: disabledIDs)
    }
    public func ordered(_ sources: [DictionarySource]) -> [DictionarySource] {
        let ranks = priority.enumerated().reduce(into: [String: Int]()) { ranks, item in
            if ranks[item.element] == nil { ranks[item.element] = item.offset }
        }
        return sources.enumerated().sorted {
            (ranks[$0.element.id] ?? priority.count + $0.offset) < (ranks[$1.element.id] ?? priority.count + $1.offset)
        }.map(\.element)
    }
}

public protocol DictionarySelectionStore: Sendable {
    func configuration() async throws -> DictionarySelection
    func setEnabled(_ enabled: Bool, id: String) async throws
    func reorder(_ ids: [String]) async throws
}

public actor MemoryDictionarySelectionStore: DictionarySelectionStore {
    private var value: DictionarySelection
    public init(_ value: DictionarySelection = .init()) { self.value = value }
    public func configuration() -> DictionarySelection { value }
    public func setEnabled(_ enabled: Bool, id: String) { value.setEnabled(enabled, id: id) }
    public func reorder(_ ids: [String]) { value.reorder(ids) }
}

/// Actor-owned read/modify/write prevents concurrent toggles losing each other.
public actor UserDefaultsDictionarySelectionStore: DictionarySelectionStore {
    public static let preferenceKey = "dictionary_selection"
    private let defaults: UserDefaults
    public init(suiteName: String? = nil) {
        defaults = suiteName.flatMap(UserDefaults.init(suiteName:)) ?? .standard
    }
    public func configuration() -> DictionarySelection {
        guard let data = defaults.data(forKey: Self.preferenceKey),
              let value = try? JSONDecoder().decode(DictionarySelection.self, from: data) else { return .init() }
        return DictionarySelection(priority: value.priority, disabledIDs: value.disabledIDs)
    }
    public func setEnabled(_ enabled: Bool, id: String) throws {
        var value = configuration()
        value.setEnabled(enabled, id: id)
        try save(value)
    }
    public func reorder(_ ids: [String]) throws {
        var value = configuration()
        value.reorder(ids)
        try save(value)
    }
    private func save(_ value: DictionarySelection) throws {
        defaults.set(try JSONEncoder().encode(value), forKey: Self.preferenceKey)
    }
}
