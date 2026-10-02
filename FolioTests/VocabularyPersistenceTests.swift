import Foundation
import SwiftData
import Testing
import FolioCore
@testable import Folio

struct VocabularyPersistenceTests {
    @Test @MainActor func savesIdempotentlyAndPersistsReviewHistory() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let location = directory.appendingPathComponent("vocabulary.store")
        let bundle = try await Task.detached {
            let config = ModelConfiguration(url: location)
            let container = try ModelContainer(for: StoredWord.self, StoredReview.self, configurations: config)
            return (container, SwiftDataVocabularyRepository(modelContainer: container))
        }.value
        let repository = bundle.1
        let entry = SampleData.entries[0]
        try await repository.save(entry)
        try await repository.save(entry)
        let cards = try await repository.cards()
        #expect(cards.count == 1)
        let card = try #require(cards.first)
        let date = Date.now
        let reviewed = try await repository.review(cardID: card.id, rating: .easy, at: date)
        #expect(reviewed.memory.state == .review)
        #expect(reviewed.memory.repetitions == 1)
        let reopened = try await Task.detached {
            let config = ModelConfiguration(url: location)
            let container = try ModelContainer(for: StoredWord.self, StoredReview.self, configurations: config)
            return SwiftDataVocabularyRepository(modelContainer: container)
        }.value
        let persisted = try #require(try await reopened.cards().first)
        #expect(persisted.memory == reviewed.memory)
        let context = ModelContext(bundle.0)
        let history = try context.fetch(FetchDescriptor<StoredReview>())
        #expect(history.count == 1)
        let event = try JSONDecoder().decode(ReviewEvent.self, from: #require(history.first).eventData)
        #expect(event.rating == .easy)
        #expect(event.schedulerVersion.hasPrefix("FSRS-6"))
        try await repository.remove(id: card.id)
        #expect(try await repository.cards().isEmpty)
        let verification = ModelContext(bundle.0)
        #expect(try verification.fetchCount(FetchDescriptor<StoredReview>()) == 0)
    }

    @Test @MainActor func failedReviewDoesNotAdvanceSession() async throws {
        let repository = MockVocabularyRepository()
        let model = ReviewViewModel(vocabulary: repository)
        await model.begin()
        let current = try #require(model.current)
        model.reveal()
        try await repository.remove(id: current.id)
        await model.rate(.good)
        #expect(model.current?.id == current.id)
        #expect(model.completed == 0)
        #expect(model.isRevealed)
        #expect(model.error != nil)
    }
}
