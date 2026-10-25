import AppKit
import AudioToolbox

public final class SoundManager {
    public static let shared = SoundManager()

    private init() {}

    public func playCameraShutterSound() {
        guard UserPreferences.shared.playCaptureSound else { return }
        // Standard macOS system sound for camera snapshot
        AudioServicesPlaySystemSound(1108) // Camera shutter
    }

    public func playRecordingStartSound() {
        guard UserPreferences.shared.playCaptureSound else { return }
        NSSound(named: "Tink")?.play()
    }

    public func playRecordingStopSound() {
        guard UserPreferences.shared.playCaptureSound else { return }
        NSSound(named: "Pop")?.play()
    }
}
