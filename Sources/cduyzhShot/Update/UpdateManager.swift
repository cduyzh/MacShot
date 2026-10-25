import Foundation
import AppKit

/// 远端版本更新信息
public struct RemoteReleaseInfo: Equatable, Codable {
    public let version: String
    public let build: String?
    public let title: String
    public let releaseNotes: String
    public let releaseDate: String?
    public let downloadURL: URL?
    public let htmlURL: URL?

    public init(
        version: String,
        build: String? = nil,
        title: String,
        releaseNotes: String,
        releaseDate: String? = nil,
        downloadURL: URL? = nil,
        htmlURL: URL? = nil
    ) {
        self.version = version
        self.build = build
        self.title = title
        self.releaseNotes = releaseNotes
        self.releaseDate = releaseDate
        self.downloadURL = downloadURL
        self.htmlURL = htmlURL
    }
}

/// 语义版本号比对工具
public enum VersionComparator {
    public static func isRemoteNewer(
        remoteVersion: String,
        remoteBuild: String?,
        localVersion: String,
        localBuild: String?
    ) -> Bool {
        let cleanRemote = cleanVersionString(remoteVersion)
        let cleanLocal = cleanVersionString(localVersion)

        let remoteComponents = cleanRemote.split(separator: ".").compactMap { Int($0) }
        let localComponents = cleanLocal.split(separator: ".").compactMap { Int($0) }

        let maxCount = max(remoteComponents.count, localComponents.count)
        for i in 0..<maxCount {
            let r = i < remoteComponents.count ? remoteComponents[i] : 0
            let l = i < localComponents.count ? localComponents[i] : 0
            if r > l { return true }
            if r < l { return false }
        }

        // 版本号相同时比对构建号
        if let rBuildStr = remoteBuild, let lBuildStr = localBuild,
           let rBuild = Int(rBuildStr), let lBuild = Int(lBuildStr) {
            return rBuild > lBuild
        }
        return false
    }

    private static func cleanVersionString(_ str: String) -> String {
        var s = str.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.lowercased().hasPrefix("v") {
            s.removeFirst()
        }
        return s
    }
}

/// 更新检测结果
public enum UpdateCheckResult: Equatable {
    case upToDate(currentVersion: String, build: String)
    case updateAvailable(RemoteReleaseInfo)
    case error(String)
}

/// 更新检测状态
public enum UpdateCheckState: Equatable {
    case idle
    case checking
    case completed(UpdateCheckResult)
}

/// 软件更新管理器
public final class UpdateManager: ObservableObject {
    public static let shared = UpdateManager()

    public static let defaultGitHubEndpoint = "https://api.github.com/repos/cduyzh/SnapScreen/releases/latest"

    @Published public private(set) var checkState: UpdateCheckState = .idle
    @Published public private(set) var latestRelease: RemoteReleaseInfo?
    @Published public private(set) var lastCheckDate: Date?
    @Published public private(set) var statusMessage: String = "未检测"

    private var activeTask: URLSessionDataTask?

    private init() {
        self.lastCheckDate = UserPreferences.shared.lastUpdateCheckDate
        if let last = self.lastCheckDate {
            self.statusMessage = "上次检查：\(Self.formatDate(last))"
        }
    }

    public var isChecking: Bool {
        if case .checking = checkState { return true }
        return false
    }

    /// 发起更新检测
    /// - Parameters:
    ///   - isUserInitiated: 是否为用户主动点击（如果是主动点击，检查完毕后会弹出对应结果提示窗口）
    ///   - completion: 完成回调
    public func checkForUpdates(isUserInitiated: Bool = false, completion: ((UpdateCheckResult) -> Void)? = nil) {
        guard !isChecking else { return }

        checkState = .checking
        statusMessage = "正在检查更新…"

        let endpointString = UserPreferences.shared.customUpdateURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? Self.defaultGitHubEndpoint
            : UserPreferences.shared.customUpdateURL.trimmingCharacters(in: .whitespacesAndNewlines)

        guard let url = URL(string: endpointString) else {
            let errorMsg = "更新地址无效：\(endpointString)"
            finish(result: .error(errorMsg), isUserInitiated: isUserInitiated, completion: completion)
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 15
        request.setValue("cduyzhShot/\(AppVersion.current.version)", forHTTPHeaderField: "User-Agent")
        request.setValue("application/vnd.github.v3+json, application/json", forHTTPHeaderField: "Accept")

        let token = UserPreferences.shared.githubToken.trimmingCharacters(in: .whitespacesAndNewlines)
        if !token.isEmpty {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        activeTask?.cancel()
        activeTask = URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.activeTask = nil

                if let error = error as NSError? {
                    if error.domain == NSURLErrorDomain && error.code == NSURLErrorCancelled {
                        self.checkState = .idle
                        return
                    }
                    let msg = "连接更新服务器失败：\(error.localizedDescription)"
                    self.finish(result: .error(msg), isUserInitiated: isUserInitiated, completion: completion)
                    return
                }

                guard let httpResponse = response as? HTTPURLResponse else {
                    self.finish(result: .error("未收到有效的服务器响应"), isUserInitiated: isUserInitiated, completion: completion)
                    return
                }

                if httpResponse.statusCode == 404 {
                    let isGitHub = url.host?.contains("github.com") == true
                    let msg = isGitHub
                        ? "未发现已发布的版本记录（HTTP 404）。若该仓库为私有仓库，请在设置中配置 GitHub 个人访问令牌（PAT）；或确认仓库 Releases 中已创建发布产物。"
                        : "更新文件未找到（HTTP 404），请检查更新地址是否正确。"
                    self.finish(result: .error(msg), isUserInitiated: isUserInitiated, completion: completion)
                    return
                }

                if httpResponse.statusCode == 401 || httpResponse.statusCode == 403 {
                    let msg = "访问受限（HTTP \(httpResponse.statusCode)）。若为私人仓库，请检查 GitHub 个人访问令牌是否有效；若未配置 Token，可能已达到 GitHub 匿名 API 请求频率上限。"
                    self.finish(result: .error(msg), isUserInitiated: isUserInitiated, completion: completion)
                    return
                }

                guard (200...299).contains(httpResponse.statusCode), let data = data else {
                    let msg = "服务器返回错误代码：HTTP \(httpResponse.statusCode)"
                    self.finish(result: .error(msg), isUserInitiated: isUserInitiated, completion: completion)
                    return
                }

                do {
                    let releaseInfo = try Self.parseReleaseData(data)
                    let currentVersion = AppVersion.current.version
                    let currentBuild = AppVersion.current.build

                    let hasNewer = VersionComparator.isRemoteNewer(
                        remoteVersion: releaseInfo.version,
                        remoteBuild: releaseInfo.build,
                        localVersion: currentVersion,
                        localBuild: currentBuild
                    )

                    if hasNewer {
                        self.finish(result: .updateAvailable(releaseInfo), isUserInitiated: isUserInitiated, completion: completion)
                    } else {
                        self.finish(result: .upToDate(currentVersion: currentVersion, build: currentBuild), isUserInitiated: isUserInitiated, completion: completion)
                    }
                } catch {
                    let msg = "解析更新数据失败：\(error.localizedDescription)"
                    self.finish(result: .error(msg), isUserInitiated: isUserInitiated, completion: completion)
                }
            }
        }
        activeTask?.resume()
    }

    /// 解析 GitHub Release JSON 或 release.json 格式数据
    public static func parseReleaseData(_ data: Data) throws -> RemoteReleaseInfo {
        let json = try JSONSerialization.jsonObject(with: data, options: [])
        guard let dict = json as? [String: Any] else {
            throw NSError(domain: "UpdateManager", code: 1001, userInfo: [NSLocalizedDescriptionKey: "更新数据根结构须为 JSON 对象"])
        }

        // 尝试解析 GitHub API Release 格式
        if let tagName = dict["tag_name"] as? String {
            let version = tagName.trimmingCharacters(in: .whitespacesAndNewlines)
            let name = (dict["name"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? version
            let body = (dict["body"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let htmlUrlString = dict["html_url"] as? String
            let publishedAt = dict["published_at"] as? String

            var downloadUrl: URL?
            if let assets = dict["assets"] as? [[String: Any]] {
                // 优先选取 zip 或 dmg 产物
                let preferredAsset = assets.first { asset in
                    let assetName = (asset["name"] as? String ?? "").lowercased()
                    return assetName.hasSuffix(".zip") || assetName.hasSuffix(".dmg")
                } ?? assets.first
                if let urlStr = preferredAsset?["browser_download_url"] as? String {
                    downloadUrl = URL(string: urlStr)
                }
            }

            // 从 release 标题或 tag 中尝试解析 build 号（如 v1.1.0-build2 或 build 2）
            var extractedBuild: String?
            if let match = name.range(of: #"(?:build|构建)\s*(\d+)"#, options: [.regularExpression, .caseInsensitive]) {
                extractedBuild = String(name[match].split(separator: " ").last ?? "")
            }

            return RemoteReleaseInfo(
                version: version,
                build: extractedBuild,
                title: name.isEmpty ? version : name,
                releaseNotes: body,
                releaseDate: publishedAt.flatMap { Self.formatISODate($0) },
                downloadURL: downloadUrl,
                htmlURL: htmlUrlString.flatMap { URL(string: $0) }
            )
        }

        // 尝试解析 release.json 格式 (package_release.sh 生成格式)
        if let version = dict["version"] as? String {
            let build = dict["build"] as? String ?? (dict["build"] as? Int).map { String($0) }
            let title = dict["title"] as? String ?? "cduyzhShot \(version)"
            var notes = ""
            if let highlights = dict["highlights"] as? [String], !highlights.isEmpty {
                notes = highlights.map { "• \($0)" }.joined(separator: "\n")
            } else if let summary = dict["summary"] as? String {
                notes = summary
            }

            var downloadUrl: URL?
            if let dlStr = dict["downloadUrl"] as? String {
                downloadUrl = URL(string: dlStr)
            } else if let archive = dict["archive"] as? String, let customURL = dict["customURL"] as? String {
                downloadUrl = URL(string: customURL)?.deletingLastPathComponent().appendingPathComponent(archive)
            }

            return RemoteReleaseInfo(
                version: version,
                build: build,
                title: title,
                releaseNotes: notes,
                releaseDate: dict["releaseDate"] as? String,
                downloadURL: downloadUrl,
                htmlURL: (dict["html_url"] as? String).flatMap { URL(string: $0) }
            )
        }

        throw NSError(domain: "UpdateManager", code: 1002, userInfo: [NSLocalizedDescriptionKey: "无法识别的版本数据格式"])
    }

    private func finish(result: UpdateCheckResult, isUserInitiated: Bool, completion: ((UpdateCheckResult) -> Void)?) {
        checkState = .completed(result)
        let now = Date()
        lastCheckDate = now
        UserPreferences.shared.lastUpdateCheckDate = now

        switch result {
        case .upToDate(let version, let build):
            latestRelease = nil
            statusMessage = "当前已是最新版本 (\(version)) · \(Self.formatDate(now))"
            if isUserInitiated {
                showUpToDateAlert(version: version, build: build)
            }

        case .updateAvailable(let release):
            latestRelease = release
            statusMessage = "发现新版本 \(release.version)！"
            // 无论用户手动触发还是后台检测，发现新版本时均弹出更新提示
            UpdateWindowController.shared.show(release: release)

        case .error(let message):
            statusMessage = "检查失败：\(message)"
            if isUserInitiated {
                showErrorAlert(message: message)
            }
        }

        completion?(result)
    }

    private func showUpToDateAlert(version: String, build: String) {
        let alert = NSAlert()
        alert.messageText = "您使用的是最新版本"
        alert.informativeText = "cduyzhShot \(version) (\(build)) 目前已是最新版本，未发现新更新。"
        alert.alertStyle = .informational
        alert.addButton(withTitle: "好")
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }

    private func showErrorAlert(message: String) {
        let alert = NSAlert()
        alert.messageText = "检查更新失败"
        alert.informativeText = message
        alert.alertStyle = .warning
        alert.addButton(withTitle: "好")
        alert.addButton(withTitle: "打开设置…")
        NSApp.activate(ignoringOtherApps: true)
        let response = alert.runModal()
        if response == .alertSecondButtonReturn {
            SettingsWindowController.shared.showAbout()
        }
    }

    private static func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "M月d日 HH:mm"
        return formatter.string(from: date)
    }

    private static func formatISODate(_ isoString: String) -> String {
        let isoFormatter = ISO8601DateFormatter()
        if let date = isoFormatter.date(from: isoString) {
            let outFormatter = DateFormatter()
            outFormatter.locale = Locale(identifier: "zh_CN")
            outFormatter.dateFormat = "yyyy年M月d日"
            return outFormatter.string(from: date)
        }
        return isoString.prefix(10).description
    }
}
