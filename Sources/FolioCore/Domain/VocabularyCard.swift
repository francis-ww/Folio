import Foundation

public enum ReviewRating: Int, CaseIterable, Codable, Sendable {
    case again = 1, hard, good, easy

    public var title: String {
        switch self {
        case .again: "Again"
        case .hard: "Hard"
        case .good: "Good"
        case .easy: "Easy"
        }
    }
}

public enum LearningState: String, Codable, Sendable {
    case new, learning, review, relearning
}

public struct MemoryState: Codable, Equatable, Sendable {
    public var stability: Double
    public var difficulty: Double
    public var state: LearningState
    public var step: Int
    public var due: Date
    public var lastReview: Date?
    public var repetitions: Int
    public var lapses: Int

    public init(stability: Double = 0, difficulty: Double = 0, state: LearningState = .new,
                step: Int = 0, due: Date = .now, lastReview: Date? = nil,
                repetitions: Int = 0, lapses: Int = 0) {
        self.stability = stability
        self.difficulty = difficulty
        self.state = state
        self.step = step
        self.due = due
        self.lastReview = lastReview
        self.repetitions = repetitions
        self.lapses = lapses
    }
}

public struct VocabularyCard: Identifiable, Codable, Hashable, Sendable {
    public let id: UUID
    public let entry: DictionaryEntry
    public var memory: MemoryState
    public let addedAt: Date

    public init(id: UUID = UUID(), entry: DictionaryEntry, memory: MemoryState = MemoryState(), addedAt: Date = .now) {
        self.id = id
        self.entry = entry
        self.memory = memory
        self.addedAt = addedAt
    }

    public static func == (lhs: Self, rhs: Self) -> Bool { lhs.id == rhs.id }
    public func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

public struct ReviewEvent: Identifiable, Codable, Sendable {
    public let id: UUID
    public let cardID: UUID
    public let rating: ReviewRating
    public let reviewedAt: Date
    public let previous: MemoryState
    public let next: MemoryState
    public let schedulerVersion: String
    public let desiredRetention: Double

    public init(cardID: UUID, rating: ReviewRating, reviewedAt: Date, previous: MemoryState,
                next: MemoryState, desiredRetention: Double) {
        id = UUID()
        self.cardID = cardID
        self.rating = rating
        self.reviewedAt = reviewedAt
        self.previous = previous
        self.next = next
        schedulerVersion = "FSRS-6/default-21/no-fuzz"
        self.desiredRetention = desiredRetention
    }
}

public protocol VocabularyRepository: Sendable {
    func cards() async throws -> [VocabularyCard]
    func save(_ entry: DictionaryEntry) async throws
    func remove(id: UUID) async throws
    func review(cardID: UUID, rating: ReviewRating, at date: Date) async throws -> VocabularyCard
}
