import AppKit
import ScreenCaptureKit
import AVFoundation

public final class ScreenRecorder: NSObject, SCStreamDelegate, SCStreamOutput, @unchecked Sendable {
    public static let shared = ScreenRecorder()

    private enum Phase {
        case idle, countdown, starting, recording, finishing
    }

    private var phase: Phase = .idle
    private var sessionID: UUID?
    private var startupCancellationRequested = false
    private var startupError: Error?
    private var stream: SCStream?
    private var writer: RecordingOutputWriter?
    private var toolbarWindow: RecordingToolbarWindow?
    private var countdownWindow: RecordingCountdownWindow?
    private let captureQueue = DispatchQueue(label: "com.cduyzh.shot.captureQueue")
    private let outputLock = NSLock()
    private var activeOutput: (stream: SCStream, writer: RecordingOutputWriter)?

    // 准备和保存阶段也保持忙碌，避免全局快捷键重入并覆盖当前录制。
    public private(set) var isRecording = false
    private var recordingRect: CGRect = .zero
    private var targetScreen: NSScreen?
    private var capturesSystemAudio = true
    private var onFinished: ((Result<URL, Error>) -> Void)?

    private override init() {
        super.init()
    }

    public func startRecording(
        in rect: CGRect? = nil,
        capturesSystemAudio: Bool = true,
        skipCountdown: Bool = false,
        completion: @escaping (Result<URL, Error>) -> Void
    ) {
        guard Thread.isMainThread else {
            DispatchQueue.main.async {
                self.startRecording(in: rect, capturesSystemAudio: capturesSystemAudio, skipCountdown: skipCountdown, completion: completion)
            }
            return
        }
        guard phase == .idle else {
            completion(.failure(recorderError(code: -1, message: "当前录制正在准备、录制或保存，请稍候。")))
            return
        }
        guard let screen = rect.flatMap({ DisplayHelper.screenContaining(point: $0.origin) }) ?? NSScreen.main ?? NSScreen.screens.first else {
            completion(.failure(recorderError(code: -2, message: "未找到可录制的显示器。")))
            return
        }

        let id = UUID()
        sessionID = id
        phase = skipCountdown ? .starting : .countdown
        isRecording = true
        startupCancellationRequested = false
        startupError = nil
        onFinished = completion
        targetScreen = screen
        recordingRect = rect ?? screen.frame
        self.capturesSystemAudio = capturesSystemAudio

        let fps = UserPreferences.shared.recordFPS == 30 ? 30 : 60
        let saveDirectory = UserPreferences.shared.saveDirectoryURL
        let captureRect = recordingRect
        if skipCountdown {
            beginCaptureSession(id: id, screen: screen, rect: captureRect, capturesSystemAudio: capturesSystemAudio, fps: fps, saveDirectory: saveDirectory)
        } else {
            let countdown = RecordingCountdownWindow(screen: screen)
            countdownWindow = countdown
            countdown.startCountdown(
                onFinished: { [weak self] in
                    guard let self = self, self.sessionID == id, self.phase == .countdown else { return }
                    self.countdownWindow = nil
                    self.phase = .starting
                    self.beginCaptureSession(id: id, screen: screen, rect: captureRect, capturesSystemAudio: capturesSystemAudio, fps: fps, saveDirectory: saveDirectory)
                },
                onCancelled: { [weak self] in
                    guard let self = self, self.sessionID == id else { return }
                    self.completeSession(id: id, result: .failure(self.cancellationError()), completion: self.onFinished)
                }
            )
        }
    }

    private func beginCaptureSession(
        id: UUID,
        screen: NSScreen,
        rect: CGRect,
        capturesSystemAudio: Bool,
        fps: Int,
        saveDirectory: URL
    ) {
        Task { @MainActor in
            var preparedWriter: RecordingOutputWriter?
            do {
                let shareableContent = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
                let displayID = DisplayHelper.displayID(for: screen)
                guard let scDisplay = shareableContent.displays.first(where: { $0.displayID == displayID }) else {
                    throw self.recorderError(code: -2, message: "当前显示器已不可用，请重新开始录制。")
                }
                guard !self.startupCancellationRequested else {
                    self.completeSession(id: id, result: .failure(self.cancellationError()), completion: self.onFinished)
                    return
                }

                let filter = SCContentFilter(display: scDisplay, excludingWindows: [])
                let formatter = DateFormatter()
                formatter.dateFormat = "yyyy-MM-dd_HH.mm.ss"
                let fileURL = saveDirectory.appendingPathComponent("cduyzhShot_\(formatter.string(from: Date())).mp4")
                let scale = screen.backingScaleFactor
                let pixelWidth = Int(rect.width * scale)
                let pixelHeight = Int(rect.height * scale)

                let newWriter = RecordingOutputWriter(outputURL: fileURL)
                preparedWriter = newWriter
                try newWriter.setup(width: pixelWidth, height: pixelHeight, capturesAudio: capturesSystemAudio, fps: fps)
                self.writer = newWriter

                let config = SCStreamConfiguration()
                config.width = pixelWidth
                config.height = pixelHeight
                config.showsCursor = true
                config.minimumFrameInterval = CMTime(value: 1, timescale: CMTimeScale(fps))
                if rect != screen.frame {
                    let relX = rect.origin.x - screen.frame.origin.x
                    let relY = screen.frame.height - (rect.origin.y - screen.frame.origin.y + rect.height)
                    config.sourceRect = CGRect(x: relX, y: relY, width: rect.width, height: rect.height)
                }
                if capturesSystemAudio {
                    config.capturesAudio = true
                    config.sampleRate = 48000
                    config.channelCount = 2
                }

                let scStream = SCStream(filter: filter, configuration: config, delegate: self)
                try scStream.addStreamOutput(self, type: .screen, sampleHandlerQueue: self.captureQueue)
                if capturesSystemAudio {
                    try scStream.addStreamOutput(self, type: .audio, sampleHandlerQueue: self.captureQueue)
                }
                self.stream = scStream
                self.setActiveOutput(stream: scStream, writer: newWriter)
                try await scStream.startCapture()

                self.phase = .recording
                if self.startupCancellationRequested || self.startupError != nil {
                    self.stopActiveSession(failure: self.startupError ?? self.cancellationError())
                } else {
                    self.showRecordingToolbar()
                    SoundManager.shared.playRecordingStartSound()
                }
            } catch {
                self.setActiveOutput(stream: nil, writer: nil)
                self.stream = nil
                self.writer = nil
                let completion = self.onFinished
                self.onFinished = nil
                if let preparedWriter = preparedWriter {
                    self.phase = .finishing
                    preparedWriter.finish { _ in
                        DispatchQueue.main.async {
                            try? FileManager.default.removeItem(at: preparedWriter.outputURL)
                            self.completeSession(id: id, result: .failure(error), completion: completion)
                        }
                    }
                } else {
                    self.completeSession(id: id, result: .failure(error), completion: completion)
                }
            }
        }
    }

    private func showRecordingToolbar() {
        let toolbar = RecordingToolbarWindow(capturesSystemAudio: capturesSystemAudio)
        guard let screen = targetScreen ?? NSScreen.main ?? NSScreen.screens.first else { return }
        let visibleFrame = screen.visibleFrame
        let x = min(max(recordingRect.midX - toolbar.frame.width / 2, visibleFrame.minX + 12), visibleFrame.maxX - toolbar.frame.width - 12)
        let y = min(recordingRect.maxY - toolbar.frame.height - 16, visibleFrame.maxY - toolbar.frame.height - 12)
        toolbar.setFrameOrigin(NSPoint(x: x, y: max(y, visibleFrame.minY + 12)))
        toolbar.onStop = { [weak self] in self?.stopRecording() }
        toolbar.orderFrontRegardless()
        toolbar.startTimer()
        toolbarWindow = toolbar
    }

    public func stopRecording() {
        guard Thread.isMainThread else {
            DispatchQueue.main.async { self.stopRecording() }
            return
        }
        switch phase {
        case .countdown:
            countdownWindow?.cancelCountdown()
        case .starting:
            startupCancellationRequested = true
        case .recording:
            stopActiveSession()
        case .idle, .finishing:
            break
        }
    }

    private func stopActiveSession(failure: Error? = nil) {
        guard phase == .recording, let id = sessionID else { return }
        phase = .finishing
        toolbarWindow?.showFinishing()
        let finishingStream = stream
        let finishingWriter = writer
        let completion = onFinished
        let capturedAudio = capturesSystemAudio
        let wasCancelledDuringStartup = startupCancellationRequested
        stream = nil
        writer = nil
        onFinished = nil
        setActiveOutput(stream: nil, writer: nil)
        SoundManager.shared.playRecordingStopSound()

        Task { @MainActor in
            var finishError = failure
            do {
                try await finishingStream?.stopCapture()
            } catch {
                finishError = finishError ?? error
            }
            guard let finishingWriter = finishingWriter else {
                self.completeSession(id: id, result: .failure(finishError ?? self.recorderError(code: -3, message: "录制文件未能完成，请重试。")), completion: completion)
                return
            }
            let finalError = finishError
            finishingWriter.finish { result in
                DispatchQueue.main.async {
                    if let finalError = finalError {
                        if wasCancelledDuringStartup {
                            try? FileManager.default.removeItem(at: finishingWriter.outputURL)
                        }
                        self.completeSession(id: id, result: .failure(finalError), completion: completion)
                    } else {
                        if case .success(let url) = result {
                            self.deliverRecording(url: url, capturesSystemAudio: capturedAudio)
                        }
                        self.completeSession(id: id, result: result, completion: completion)
                    }
                }
            }
        }
    }

    private func completeSession(id: UUID, result: Result<URL, Error>, completion: ((Result<URL, Error>) -> Void)?) {
        guard sessionID == id else { return }
        setActiveOutput(stream: nil, writer: nil)
        toolbarWindow?.stopTimer()
        toolbarWindow?.orderOut(nil)
        toolbarWindow = nil
        countdownWindow = nil
        stream = nil
        writer = nil
        onFinished = nil
        targetScreen = nil
        sessionID = nil
        startupCancellationRequested = false
        startupError = nil
        phase = .idle
        isRecording = false
        completion?(result)
    }

    private func deliverRecording(url: URL, capturesSystemAudio: Bool) {
        PasteboardHelper.copyFile(at: url)
        NotificationHelper.notifyRecordingSaved(url: url)
        guard UserPreferences.shared.showFloatingThumbnail else { return }
        // 视频缩略图解码不占用主线程，保存完成的反馈可以立即返回。
        DispatchQueue.global(qos: .utility).async {
            let generator = AVAssetImageGenerator(asset: AVAsset(url: url))
            generator.appliesPreferredTrackTransform = true
            generator.maximumSize = CGSize(width: 720, height: 480)
            let time = CMTime(seconds: 0.1, preferredTimescale: 60)
            guard let image = try? generator.copyCGImage(at: time, actualTime: nil) else { return }
            DispatchQueue.main.async {
                FloatingThumbnailWindow.shared.show(
                    image: image,
                    fileURL: url,
                    message: capturesSystemAudio ? "录屏已保存，含系统声音，可直接 ⌘V 粘贴" : "录屏已保存，无声音，可直接 ⌘V 粘贴"
                )
            }
        }
    }

    private func setActiveOutput(stream: SCStream?, writer: RecordingOutputWriter?) {
        outputLock.lock()
        if let stream = stream, let writer = writer {
            activeOutput = (stream, writer)
        } else {
            activeOutput = nil
        }
        outputLock.unlock()
    }

    private func recorderError(code: Int, message: String) -> Error {
        NSError(domain: "cduyzhShot.Recorder", code: code, userInfo: [NSLocalizedDescriptionKey: message])
    }

    private func cancellationError() -> Error {
        recorderError(code: -99, message: "已取消录制。")
    }

    // MARK: - SCStreamOutput
    public func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        outputLock.lock()
        let writer = activeOutput.flatMap { $0.stream === stream ? $0.writer : nil }
        outputLock.unlock()
        guard let writer = writer else { return }
        switch type {
        case .screen:
            writer.appendVideoSampleBuffer(sampleBuffer)
        case .audio:
            writer.appendAudioSampleBuffer(sampleBuffer)
        default:
            break
        }
    }

    // MARK: - SCStreamDelegate
    public func stream(_ stream: SCStream, didStopWithError error: Error) {
        DispatchQueue.main.async {
            guard self.stream === stream else { return }
            if self.phase == .starting {
                self.startupError = error
            } else if self.phase == .recording {
                self.stopActiveSession(failure: error)
            }
        }
    }
}
