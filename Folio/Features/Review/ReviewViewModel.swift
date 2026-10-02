import Foundation
import Observation
import FolioCore

@MainActor @Observable
final class ReviewViewModel {
    private(set) var queue: [VocabularyCard] = []
    private(set) var completed = 0
    private(set) var total = 0
    private(set) var isSaving = false
    var isRevealed = false
    var error: String?
    private(set) var hasStarted = false
    private let vocabulary: any VocabularyRepository
    private var sessionDate = Date.now

    init(vocabulary: any VocabularyRepository) { self.vocabulary = vocabulary }
    var current: VocabularyCard? { queue.first }
    var progress: Double { total == 0 ? 0 : Double(completed) / Double(total) }

    func begin() async {
        guard !isSaving else { return }
        do {
            sessionDate = .now
            queue = try await vocabulary.cards().filter { $0.memory.due <= sessionDate }.sorted { $0.memory.due < $1.memory.due }
            completed = 0
            total = queue.count
            isRevealed = false
            hasStarted = true
            error = nil
        } catch { self.error = error.localizedDescription }
    }

    func interval(for rating: ReviewRating) -> String {
        guard let current else { return "" }
        let next = FSRSScheduler().review(current.memory, rating: rating, at: sessionDate)
        let seconds = next.due.timeIntervalSince(sessionDate)
        if seconds < 3_600 {
            let minutes = seconds / 60
            return minutes == minutes.rounded() ? "\(Int(minutes))m" : "\(minutes.formatted(.number.precision(.fractionLength(1))))m"
        }
        let days = Int((seconds / 86_400).rounded())
        return "\(days)d"
    }

    func reveal() { sessionDate = .now; isRevealed = true }

    func rate(_ rating: ReviewRating) async {
        guard let current, isRevealed, !isSaving else { return }
        isSaving = true
        defer { isSaving = false }
        do {
            // Persist first. A failed write leaves the same card visible for retry.
            _ = try await vocabulary.review(cardID: current.id, rating: rating, at: sessionDate)
            queue.removeFirst()
            completed += 1
            isRevealed = false
            error = nil
        } catch { self.error = error.localizedDescription }
    }
}
