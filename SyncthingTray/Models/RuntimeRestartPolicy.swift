import Foundation

struct RuntimeRestartPolicy: Equatable {
    private static let retryDelays: [TimeInterval] = [5, 15, 30, 60, 120]

    private(set) var consecutiveFailures = 0
    private(set) var nextEligibleAttemptAt: Date?

    mutating func reset() {
        consecutiveFailures = 0
        nextEligibleAttemptAt = nil
    }

    func shouldAttempt(at date: Date = .now, force: Bool = false) -> Bool {
        if force {
            return true
        }

        guard let nextEligibleAttemptAt else {
            return true
        }

        return date >= nextEligibleAttemptAt
    }

    func remainingDelay(at date: Date = .now) -> TimeInterval? {
        guard let nextEligibleAttemptAt, nextEligibleAttemptAt > date else {
            return nil
        }

        return nextEligibleAttemptAt.timeIntervalSince(date)
    }

    @discardableResult
    mutating func recordFailure(at date: Date = .now) -> TimeInterval {
        let index = min(consecutiveFailures, Self.retryDelays.count - 1)
        let delay = Self.retryDelays[index]
        consecutiveFailures += 1
        nextEligibleAttemptAt = date.addingTimeInterval(delay)
        return delay
    }
}
