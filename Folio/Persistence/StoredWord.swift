import Foundation
import SwiftData
import FolioCore

@Model
final class StoredWord {
    @Attribute(.unique) var id: UUID
    @Attribute(.unique) var entryID: String
    var entryData: Data
    var memoryData: Data
    var addedAt: Date
    var due: Date

    init(entry: DictionaryEntry, at date: Date) throws {
        id = UUID()
        entryID = entry.id
        entryData = try JSONEncoder().encode(entry)
        memoryData = try JSONEncoder().encode(MemoryState(due: date))
        addedAt = date
        due = date
    }

    func snapshot() throws -> VocabularyCard {
        VocabularyCard(id: id, entry: try JSONDecoder().decode(DictionaryEntry.self, from: entryData),
                       memory: try JSONDecoder().decode(MemoryState.self, from: memoryData), addedAt: addedAt)
    }
}

@Model
final class StoredReview {
    @Attribute(.unique) var id: UUID
    var cardID: UUID
    var reviewedAt: Date
    var eventData: Data

    init(_ event: ReviewEvent) throws {
        id = event.id
        cardID = event.cardID
        reviewedAt = event.reviewedAt
        eventData = try JSONEncoder().encode(event)
    }
}
