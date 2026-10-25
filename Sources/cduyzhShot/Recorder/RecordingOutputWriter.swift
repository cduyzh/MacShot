import AppKit
import AVFoundation
import CoreMedia

public final class RecordingOutputWriter {
    public let outputURL: URL
    private var assetWriter: AVAssetWriter?
    private var videoInput: AVAssetWriterInput?
    private var audioInput: AVAssetWriterInput?
    private let writerQueue = DispatchQueue(label: "com.cduyzh.shot.writerQueue")

    private var isRecording = false
    private var sessionStarted = false
    private var startTime: CMTime = .invalid

    public init(outputURL: URL) {
        self.outputURL = outputURL
    }

    public func setup(
        width: Int,
        height: Int,
        capturesAudio: Bool,
        fps: Int = 60
    ) throws {
        if FileManager.default.fileExists(atPath: outputURL.path) {
            try? FileManager.default.removeItem(at: outputURL)
        }

        let writer = try AVAssetWriter(outputURL: outputURL, fileType: .mp4)

        // Video Input (H.264)
        // Ensure even dimensions for H.264
        let alignedWidth = (width / 2) * 2
        let alignedHeight = (height / 2) * 2

        let videoSettings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: alignedWidth,
            AVVideoHeightKey: alignedHeight,
            AVVideoCompressionPropertiesKey: [
                AVVideoAverageBitRateKey: max(alignedWidth * alignedHeight * 6, 4_000_000),
                AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel,
                AVVideoExpectedSourceFrameRateKey: fps
            ]
        ]

        let vInput = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
        vInput.expectsMediaDataInRealTime = true

        if writer.canAdd(vInput) {
            writer.add(vInput)
            self.videoInput = vInput
        }

        // Audio Input (AAC Stereo 48kHz)
        if capturesAudio {
            let audioSettings: [String: Any] = [
                AVFormatIDKey: kAudioFormatMPEG4AAC,
                AVNumberOfChannelsKey: 2,
                AVSampleRateKey: 48000.0,
                AVEncoderBitRateKey: 192000
            ]

            let aInput = AVAssetWriterInput(mediaType: .audio, outputSettings: audioSettings)
            aInput.expectsMediaDataInRealTime = true

            if writer.canAdd(aInput) {
                writer.add(aInput)
                self.audioInput = aInput
            }
        }

        guard writer.startWriting() else {
            throw writer.error ?? NSError(domain: "cduyzhShot.Recording", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to start writing"])
        }

        self.assetWriter = writer
        self.isRecording = true
    }

    public func appendVideoSampleBuffer(_ sampleBuffer: CMSampleBuffer) {
        writerQueue.async { [weak self] in
            guard let self = self, self.isRecording, let writer = self.assetWriter, let vInput = self.videoInput else {
                return
            }

            let pts = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
            guard pts.isValid else { return }

            if !self.sessionStarted {
                writer.startSession(atSourceTime: pts)
                self.startTime = pts
                self.sessionStarted = true
            }

            if vInput.isReadyForMoreMediaData {
                vInput.append(sampleBuffer)
            }
        }
    }

    public func appendAudioSampleBuffer(_ sampleBuffer: CMSampleBuffer) {
        writerQueue.async { [weak self] in
            guard let self = self, self.isRecording, self.sessionStarted, let aInput = self.audioInput else {
                return
            }

            if aInput.isReadyForMoreMediaData {
                aInput.append(sampleBuffer)
            }
        }
    }

    public func finish(completion: @escaping (Result<URL, Error>) -> Void) {
        writerQueue.async { [weak self] in
            guard let self = self else { return }
            self.isRecording = false

            self.videoInput?.markAsFinished()
            self.audioInput?.markAsFinished()

            guard let writer = self.assetWriter else {
                completion(.failure(NSError(domain: "cduyzhShot.Recording", code: -2, userInfo: [NSLocalizedDescriptionKey: "Writer is nil"])))
                return
            }

            writer.finishWriting {
                DispatchQueue.main.async {
                    if let error = writer.error {
                        completion(.failure(error))
                    } else {
                        completion(.success(self.outputURL))
                    }
                }
            }
        }
    }
}
