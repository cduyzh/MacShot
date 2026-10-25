import AppKit

public final class UserPreferences: ObservableObject {
    public static let shared = UserPreferences()

    private let defaults = UserDefaults.standard

    private enum Keys {
        static let hotkeyScreenshot = "hotkeyScreenshot"
        static let hotkeyRecording = "hotkeyRecording"
        static let hotkeyScroll = "hotkeyScroll"
        static let hotkeyPin = "hotkeyPin"
        static let saveDirectory = "saveDirectory"
        static let captureSystemAudio = "captureSystemAudio"
        static let playCaptureSound = "playCaptureSound"
        static let autoCopyToClipboard = "autoCopyToClipboard"
        static let copyAsTempFileToClipboard = "copyAsTempFileToClipboard"
        static let showFloatingThumbnail = "showFloatingThumbnail"
        static let showMagnifier = "showMagnifier"
        static let cacheRetentionDays = "cacheRetentionDays"
        static let maxCacheSizeMB = "maxCacheSizeMB"
        static let autoCleanCacheEnabled = "autoCleanCacheEnabled"
        static let screenshotFormat = "screenshotFormat"
        static let recordFPS = "recordFPS"
        static let autoCheckForUpdates = "autoCheckForUpdates"
        static let lastUpdateCheckDate = "lastUpdateCheckDate"
        static let customUpdateURL = "customUpdateURL"
        static let githubToken = "githubToken"
    }

    @Published public var hotkeyScreenshot: KeyCombo {
        didSet { saveKeyCombo(hotkeyScreenshot, key: Keys.hotkeyScreenshot) }
    }

    @Published public var hotkeyRecording: KeyCombo {
        didSet { saveKeyCombo(hotkeyRecording, key: Keys.hotkeyRecording) }
    }

    @Published public var hotkeyScroll: KeyCombo {
        didSet { saveKeyCombo(hotkeyScroll, key: Keys.hotkeyScroll) }
    }

    @Published public var hotkeyPin: KeyCombo {
        didSet { saveKeyCombo(hotkeyPin, key: Keys.hotkeyPin) }
    }

    @Published public var saveDirectoryPath: String {
        didSet { defaults.set(saveDirectoryPath, forKey: Keys.saveDirectory) }
    }

    @Published public var captureSystemAudio: Bool {
        didSet { defaults.set(captureSystemAudio, forKey: Keys.captureSystemAudio) }
    }

    @Published public var playCaptureSound: Bool {
        didSet { defaults.set(playCaptureSound, forKey: Keys.playCaptureSound) }
    }

    @Published public var autoCopyToClipboard: Bool {
        didSet { defaults.set(autoCopyToClipboard, forKey: Keys.autoCopyToClipboard) }
    }

    @Published public var copyAsTempFileToClipboard: Bool {
        didSet { defaults.set(copyAsTempFileToClipboard, forKey: Keys.copyAsTempFileToClipboard) }
    }

    @Published public var showFloatingThumbnail: Bool {
        didSet { defaults.set(showFloatingThumbnail, forKey: Keys.showFloatingThumbnail) }
    }

    @Published public var showMagnifier: Bool {
        didSet { defaults.set(showMagnifier, forKey: Keys.showMagnifier) }
    }

    @Published public var cacheRetentionDays: Int {
        didSet { defaults.set(cacheRetentionDays, forKey: Keys.cacheRetentionDays) }
    }

    @Published public var maxCacheSizeMB: Int {
        didSet { defaults.set(maxCacheSizeMB, forKey: Keys.maxCacheSizeMB) }
    }

    @Published public var autoCleanCacheEnabled: Bool {
        didSet { defaults.set(autoCleanCacheEnabled, forKey: Keys.autoCleanCacheEnabled) }
    }

    @Published public var screenshotFormat: String {
        didSet { defaults.set(screenshotFormat, forKey: Keys.screenshotFormat) }
    }

    @Published public var recordFPS: Int {
        didSet { defaults.set(recordFPS, forKey: Keys.recordFPS) }
    }

    @Published public var autoCheckForUpdates: Bool {
        didSet { defaults.set(autoCheckForUpdates, forKey: Keys.autoCheckForUpdates) }
    }

    @Published public var lastUpdateCheckDate: Date? {
        didSet { defaults.set(lastUpdateCheckDate, forKey: Keys.lastUpdateCheckDate) }
    }

    @Published public var customUpdateURL: String {
        didSet { defaults.set(customUpdateURL, forKey: Keys.customUpdateURL) }
    }

    @Published public var githubToken: String {
        didSet { defaults.set(githubToken, forKey: Keys.githubToken) }
    }

    public var saveDirectoryURL: URL {
        let url = URL(fileURLWithPath: saveDirectoryPath)
        // Fallback check: if directory doesn't exist or isn't writable, fallback to ~/Downloads
        var isDir: ObjCBool = false
        if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir), isDir.boolValue, FileManager.default.isWritableFile(atPath: url.path) {
            return url
        }
        let fallback = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: "/Users/\(NSUserName())/Downloads")
        return fallback
    }

    private init() {
        let defaultScreenshot = KeyCombo(keyCode: 0, modifiers: UInt32(NSEvent.ModifierFlags.control.rawValue), characters: "a")
        let defaultRecording = KeyCombo(keyCode: 33, modifiers: UInt32(NSEvent.ModifierFlags.control.rawValue), characters: "[")
        let defaultScroll = KeyCombo(keyCode: 1, modifiers: UInt32(NSEvent.ModifierFlags.option.rawValue), characters: "s")
        let defaultPin = KeyCombo(keyCode: 35, modifiers: UInt32(NSEvent.ModifierFlags.option.rawValue), characters: "p")

        let downloadsPath = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first?.path ?? "/Users/\(NSUserName())/Downloads"

        self.hotkeyScreenshot = UserPreferences.loadKeyCombo(key: Keys.hotkeyScreenshot) ?? defaultScreenshot
        self.hotkeyRecording = UserPreferences.loadKeyCombo(key: Keys.hotkeyRecording) ?? defaultRecording
        self.hotkeyScroll = UserPreferences.loadKeyCombo(key: Keys.hotkeyScroll) ?? defaultScroll
        self.hotkeyPin = UserPreferences.loadKeyCombo(key: Keys.hotkeyPin) ?? defaultPin

        var initialSavePath = defaults.string(forKey: Keys.saveDirectory) ?? downloadsPath
        if initialSavePath.contains("Desktop") || !FileManager.default.fileExists(atPath: initialSavePath) {
            initialSavePath = downloadsPath
            defaults.set(initialSavePath, forKey: Keys.saveDirectory)
        }
        self.saveDirectoryPath = initialSavePath
        self.captureSystemAudio = defaults.object(forKey: Keys.captureSystemAudio) as? Bool ?? true
        self.playCaptureSound = defaults.object(forKey: Keys.playCaptureSound) as? Bool ?? true
        self.autoCopyToClipboard = defaults.object(forKey: Keys.autoCopyToClipboard) as? Bool ?? true
        self.copyAsTempFileToClipboard = defaults.object(forKey: Keys.copyAsTempFileToClipboard) as? Bool ?? true
        self.showFloatingThumbnail = defaults.object(forKey: Keys.showFloatingThumbnail) as? Bool ?? true
        self.showMagnifier = defaults.object(forKey: Keys.showMagnifier) as? Bool ?? true
        self.cacheRetentionDays = defaults.object(forKey: Keys.cacheRetentionDays) as? Int ?? 7
        self.maxCacheSizeMB = defaults.object(forKey: Keys.maxCacheSizeMB) as? Int ?? 500
        self.autoCleanCacheEnabled = defaults.object(forKey: Keys.autoCleanCacheEnabled) as? Bool ?? true
        self.screenshotFormat = defaults.string(forKey: Keys.screenshotFormat) ?? "PNG"
        self.recordFPS = defaults.object(forKey: Keys.recordFPS) as? Int ?? 60
        self.autoCheckForUpdates = defaults.object(forKey: Keys.autoCheckForUpdates) as? Bool ?? true
        self.lastUpdateCheckDate = defaults.object(forKey: Keys.lastUpdateCheckDate) as? Date
        self.customUpdateURL = defaults.string(forKey: Keys.customUpdateURL) ?? ""
        self.githubToken = defaults.string(forKey: Keys.githubToken) ?? ""
    }

    private func saveKeyCombo(_ combo: KeyCombo, key: String) {
        if let data = try? JSONEncoder().encode(combo) {
            defaults.set(data, forKey: key)
        }
    }

    private static func loadKeyCombo(key: String) -> KeyCombo? {
        guard let data = UserDefaults.standard.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(KeyCombo.self, from: data)
    }
}
