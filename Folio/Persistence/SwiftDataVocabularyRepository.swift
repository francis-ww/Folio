import Foundation
import SwiftData
import FolioCore

@ModelActor
actor SwiftDataVocabularyRepository: VocabularyRepository {
    func cards() throws -> [VocabularyCard] {
        try modelContext.fetch(FetchDescriptor<StoredWord>(sortBy: [SortDescriptor(\StoredWord.addedAt, order: .reverse)]))
            .map { try $0.snapshot() }
    }

    func save(_ entry: DictionaryEntry) throws {
        let entryID = entry.id
        var request = FetchDescriptor<StoredWord>(predicate: #Predicate { $0.entryID == entryID })
        request.fetchLimit = 1
        guard try modelContext.fetch(request).isEmpty else { return }
        do {
            modelContext.insert(try StoredWord(entry: entry, at: .now))
            try modelContext.save()
        } catch { modelContext.rollback(); throw error }
    }

    func remove(id: UUID) throws {
        do {
            try modelContext.delete(model: StoredWord.self, where: #Predicate { $0.id == id })
            try modelContext.delete(model: StoredReview.self, where: #Predicate { $0.cardID == id })
            try modelContext.save()
        } catch { modelContext.rollback(); throw error }
    }

    func review(cardID: UUID, rating: ReviewRating, at date: Date) throws -> VocabularyCard {
        var request = FetchDescriptor<StoredWord>(predicate: #Predicate { $0.id == cardID })
        request.fetchLimit = 1
        guard let stored = try modelContext.fetch(request).first else { throw CocoaError(.fileNoSuchFile) }
        let previous = try stored.snapshot()
        let scheduler = FSRSScheduler()
        let next = scheduler.review(previous.memory, rating: rating, at: date)
        let log = ReviewEvent(cardID: cardID, rating: rating, reviewedAt: date, previous: previous.memory,
                              next: next, desiredRetention: scheduler.desiredRetention)
        do {
            stored.memoryData = try JSONEncoder().encode(next)
            stored.due = next.due
            modelContext.insert(try StoredReview(log))
            try modelContext.save()
        } catch { modelContext.rollback(); throw error }
        return try stored.snapshot()
    }
}
