import Foundation

/// FSRS-6 with default weights, 1m/10m learning steps and a 10m relearning step.
/// Deterministic intervals keep previews and persisted review results identical.
/// Equations: https://github.com/open-spaced-repetition/awesome-fsrs/wiki/The-Algorithm
public struct FSRSScheduler: Sendable {
    public static let weights: [Double] = [
        0.212, 1.2931, 2.3065, 8.2956, 6.4133, 0.8334, 3.0194,
        0.001, 1.8722, 0.1666, 0.796, 1.4835, 0.0614, 0.2629,
        1.6483, 0.6014, 1.8729, 0.5425, 0.0912, 0.0658, 0.1542
    ]
    public let desiredRetention: Double
    public let maximumInterval: Int
    private var w: [Double] { Self.weights }
    private var factor: Double { pow(0.9, -1 / w[20]) - 1 }

    public init(desiredRetention: Double = 0.9, maximumInterval: Int = 36_500) {
        self.desiredRetention = desiredRetention.isFinite ? min(0.99, max(0.7, desiredRetention)) : 0.9
        self.maximumInterval = max(1, maximumInterval)
    }

    public func retrievability(_ memory: MemoryState, at date: Date) -> Double {
        guard let last = memory.lastReview, memory.stability > 0 else { return 0 }
        let days = max(0, floor(date.timeIntervalSince(last) / 86_400))
        return pow(1 + factor * days / memory.stability, -w[20])
    }

    public func intervalDays(stability: Double) -> Int {
        let raw = stability / factor * (pow(desiredRetention, -1 / w[20]) - 1)
        guard raw.isFinite else { return maximumInterval }
        return Int(min(Double(maximumInterval), max(1, raw.rounded(.toNearestOrEven))))
    }

    public func review(_ previous: MemoryState, rating: ReviewRating, at date: Date) -> MemoryState {
        var next = previous
        let grade = Double(rating.rawValue)
        let isInitial = previous.lastReview == nil || previous.state == .new
        if isInitial {
            next.stability = w[rating.rawValue - 1]
            next.difficulty = clampDifficulty(initialDifficulty(grade))
            next.state = .learning
            next.step = 0
        } else {
            let stability = max(0.001, previous.stability)
            let difficulty = clampDifficulty(previous.difficulty)
            let elapsed = max(0, date.timeIntervalSince(previous.lastReview ?? date))
            if elapsed < 86_400 {
                let growth = exp(w[17] * (grade - 3 + w[18])) * pow(stability, -w[19])
                next.stability = stability * (rating == .again ? growth : max(1, growth))
            } else {
                let recall = retrievability(previous, at: date)
                if rating == .again {
                    let forgotten = w[11] * pow(difficulty, -w[12])
                        * (pow(stability + 1, w[13]) - 1) * exp(w[14] * (1 - recall))
                    next.stability = min(forgotten, stability / exp(w[17] * w[18]))
                } else {
                    let modifier = rating == .hard ? w[15] : (rating == .easy ? w[16] : 1)
                    next.stability = stability * (1 + exp(w[8]) * (11 - difficulty)
                        * pow(stability, -w[9]) * (exp(w[10] * (1 - recall)) - 1) * modifier)
                }
            }
            let damped = difficulty - w[6] * (grade - 3) * (10 - difficulty) / 9
            next.difficulty = clampDifficulty(w[7] * initialDifficulty(4) + (1 - w[7]) * damped)
        }
        next.stability = max(0.001, next.stability)

        let seconds: Double
        switch next.state {
        case .new, .learning:
            switch rating {
            case .again: next.step = 0; seconds = 60
            case .hard: seconds = next.step == 0 ? 330 : 600
            case .good:
                if next.step == 0 { next.step = 1; seconds = 600 }
                else { next.state = .review; next.step = 0; seconds = Double(intervalDays(stability: next.stability)) * 86_400 }
            case .easy:
                next.state = .review; next.step = 0
                seconds = Double(intervalDays(stability: next.stability)) * 86_400
            }
        case .review:
            if rating == .again {
                next.state = .relearning; next.step = 0; next.lapses += 1; seconds = 600
            } else {
                seconds = Double(intervalDays(stability: next.stability)) * 86_400
            }
        case .relearning:
            switch rating {
            case .again: seconds = 600
            case .hard: seconds = 900
            case .good, .easy:
                next.state = .review; next.step = 0
                seconds = Double(intervalDays(stability: next.stability)) * 86_400
            }
        }
        next.lastReview = date
        next.due = date.addingTimeInterval(seconds)
        next.repetitions += 1
        return next
    }

    private func initialDifficulty(_ grade: Double) -> Double { w[4] - exp(w[5] * (grade - 1)) + 1 }
    private func clampDifficulty(_ value: Double) -> Double { min(10, max(1, value)) }
}
