import Foundation

/// 单帧动画/过渡先等待，不弹出恢复操作；连续失配才需要用户找回位置。
struct ScrollCaptureRecoveryState {
    private(set) var firstMissAt: TimeInterval?
    private(set) var misses = 0
    private(set) var direction: ScrollCaptureDirection = .up
    var hasGap: Bool { firstMissAt != nil }

    mutating func observeMiss(now: TimeInterval, travelDirection: ScrollCaptureDirection) -> Bool {
        if firstMissAt == nil {
            firstMissAt = now
            direction = travelDirection.opposite
        }
        misses += 1
        return misses >= 3 && now - (firstMissAt ?? now) >= 0.55
    }

    mutating func reset() {
        firstMissAt = nil
        misses = 0
    }
}
