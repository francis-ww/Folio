import Foundation
import Testing
@testable import FolioCore

struct FSRSSchedulerTests {
    private struct Reference: Decodable {
        let reference: String
        let origin: Double
        let cases: [[Event]]
    }
    private struct Event: Decodable {
        let rating: Int
        let elapsed: Double
        let stability: Double
        let difficulty: Double
        let state: LearningState
        let step: Int
        let due: Double
        let retrievability: Double
    }

    @Test func matchesOfficialPythonReference() throws {
        let url = try #require(Bundle.module.url(forResource: "fsrs-reference", withExtension: "json", subdirectory: "Fixtures"))
        let reference = try JSONDecoder().decode(Reference.self, from: Data(contentsOf: url))
        #expect(reference.reference == "py-fsrs 6.3.2")
        let scheduler = FSRSScheduler()
        let origin = Date(timeIntervalSince1970: reference.origin)
        for sequence in reference.cases {
            var memory = MemoryState(due: origin)
            for expected in sequence {
                let rating = try #require(ReviewRating(rawValue: expected.rating))
                let date = origin.addingTimeInterval(expected.elapsed)
                memory = scheduler.review(memory, rating: rating, at: date)
                #expect(abs(memory.stability - expected.stability) < 1e-9)
                #expect(abs(memory.difficulty - expected.difficulty) < 1e-9)
                #expect(memory.state == expected.state)
                #expect(memory.step == expected.step)
                #expect(abs(memory.due.timeIntervalSince1970 - expected.due) < 0.001)
                #expect(abs(scheduler.retrievability(memory, at: date.addingTimeInterval(10 * 86_400)) - expected.retrievability) < 1e-9)
            }
        }
    }

    @Test func forgettingCurveAndRetention() {
        let date = Date(timeIntervalSince1970: 0)
        let memory = MemoryState(stability: 10, difficulty: 5, state: .review, lastReview: date)
        #expect(abs(FSRSScheduler().retrievability(memory, at: date.addingTimeInterval(10 * 86_400)) - 0.9) < 1e-12)
        #expect(FSRSScheduler(desiredRetention: 0.95).intervalDays(stability: 20) < FSRSScheduler(desiredRetention: 0.8).intervalDays(stability: 20))
        #expect(FSRSScheduler(maximumInterval: 7).intervalDays(stability: 1000) == 7)
        #expect(FSRSScheduler(desiredRetention: .nan).desiredRetention == 0.9)
    }

    @Test func lapseIsCountedOnlyOnLeavingReview() {
        let date = Date(timeIntervalSince1970: 0)
        let scheduler = FSRSScheduler()
        let initial = MemoryState(stability: 20, difficulty: 5, state: .review, lastReview: date)
        let forgotten = scheduler.review(initial, rating: .again, at: date.addingTimeInterval(86_400))
        #expect(forgotten.state == .relearning)
        #expect(forgotten.lapses == 1)
        let again = scheduler.review(forgotten, rating: .again, at: forgotten.due)
        #expect(again.lapses == 1)
        #expect(again.repetitions == 2)
    }
}
