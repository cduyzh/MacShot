import Foundation

/// 静止只有在确实尝试自动滚动后才是“可能触底”；失配和回看不能作为触底证据。
struct ScrollCaptureEndDetector {
    private var stationarySince: TimeInterval?
    private var attempts = 0

    mutating func reset() {
        stationarySince = nil
        attempts = 0
    }

    mutating func observe(_ result: ImageStitcher.FrameResult, attemptedAutoScroll: Bool, now: TimeInterval) -> Bool {
        guard result == .unchanged, attemptedAutoScroll else { reset(); return false }
        stationarySince = stationarySince ?? now
        attempts += 1
        return attempts >= 6 && now - (stationarySince ?? now) >= 1.2
    }
}
