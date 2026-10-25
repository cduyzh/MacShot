import Foundation

/// 版本与构建信息以当前运行的应用包为准。
struct AppVersion: Equatable {
    let version: String
    let build: String
    let buildDate: Date?
    let releaseDate: String?
    let isApplicationBundle: Bool

    static let current: AppVersion = {
        let bundle = Bundle.main
        let version = nonemptyString(bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString"))
        let build = nonemptyString(bundle.object(forInfoDictionaryKey: "CFBundleVersion"))
        let isApplicationBundle = bundle.bundleURL.pathExtension.lowercased() == "app"
        let fallback = isApplicationBundle ? nil : ReleaseHistory.shared.latest
        return AppVersion(
            version: version ?? fallback?.version ?? "未标记",
            build: build ?? fallback?.build ?? "未标记",
            buildDate: parseBuildDate(nonemptyString(bundle.object(forInfoDictionaryKey: "CDUYZHBuildDate"))),
            releaseDate: nonemptyString(bundle.object(forInfoDictionaryKey: "CDUYZHReleaseDate")),
            isApplicationBundle: isApplicationBundle
        )
    }()

    var displayString: String { "\(version) (\(build))" }

    var releaseRecord: AppRelease? {
        ReleaseHistory.shared.releases.first { $0.version == version && $0.build == build }
    }

    var releaseDateDisplayString: String? {
        if let releaseDate, let formatted = AppRelease.formattedDate(releaseDate) {
            return formatted
        }
        return releaseRecord?.dateDisplayString
    }

    var buildDateDisplayString: String? {
        guard let buildDate else { return nil }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter.string(from: buildDate)
    }

    private static func nonemptyString(_ value: Any?) -> String? {
        guard let value = value as? String else { return nil }
        let result = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return result.isEmpty ? nil : result
    }

    private static func parseBuildDate(_ value: String?) -> Date? {
        guard let value else { return nil }
        let formatter = ISO8601DateFormatter()
        if let date = formatter.date(from: value) { return date }
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: value)
    }
}

struct AppRelease: Decodable, Identifiable {
    let version: String
    let build: String
    let date: String
    let title: String
    let summary: String
    let highlights: [String]
    let notes: [String]

    var id: String { "\(version)|\(build)" }
    var displayString: String { "\(version) (\(build))" }
    var dateDisplayString: String { Self.formattedDate(date) ?? date }

    private enum CodingKeys: String, CodingKey {
        case version, build, date, title, summary, highlights, notes
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        version = try values.decode(String.self, forKey: .version)
        build = try values.decode(String.self, forKey: .build)
        date = try values.decode(String.self, forKey: .date)
        title = try values.decode(String.self, forKey: .title)
        summary = try values.decode(String.self, forKey: .summary)
        highlights = try values.decodeIfPresent([String].self, forKey: .highlights) ?? []
        notes = try values.decodeIfPresent([String].self, forKey: .notes) ?? []
    }

    static func formattedDate(_ value: String) -> String? {
        let parser = DateFormatter()
        parser.locale = Locale(identifier: "en_US_POSIX")
        parser.timeZone = TimeZone(secondsFromGMT: 0)
        parser.dateFormat = "yyyy-MM-dd"
        parser.isLenient = false
        guard let date = parser.date(from: value), parser.string(from: date) == value else { return nil }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy 年 M 月 d 日"
        return formatter.string(from: date)
    }
}

/// 随应用发布的本地记录，不进行联网更新检查。
struct ReleaseHistory {
    let releases: [AppRelease]
    let isAvailable: Bool

    static let shared = load()
    var latest: AppRelease? { releases.first }

    private struct Document: Decodable {
        let releases: [AppRelease]
    }

    private static func load() -> ReleaseHistory {
        let main = Bundle.main
        let resourceBundleName = "cduyzhShot_cduyzhShot.bundle"
        var bundles = [main]
        // 手工打包与 SwiftPM 命令行启动均使用同一份资源；资源缺失时保留可打开的空态。
        let locations = [
            main.resourceURL,
            main.bundleURL,
            main.executableURL?.deletingLastPathComponent()
        ].compactMap { $0 }
        for location in locations {
            if let bundle = Bundle(url: location.appendingPathComponent(resourceBundleName)) {
                bundles.append(bundle)
            }
        }
        for bundle in bundles {
            guard let url = bundle.url(forResource: "ReleaseHistory", withExtension: "json"),
                  let data = try? Data(contentsOf: url),
                  let document = try? JSONDecoder().decode(Document.self, from: data) else { continue }
            var seen = Set<String>()
            let releases = document.releases.filter {
                !$0.version.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    && !$0.build.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    && seen.insert($0.id).inserted
            }.sorted {
                let versionOrder = $0.version.compare($1.version, options: .numeric)
                return versionOrder == .orderedSame
                    ? $0.build.compare($1.build, options: .numeric) == .orderedDescending
                    : versionOrder == .orderedDescending
            }
            return ReleaseHistory(releases: releases, isAvailable: !releases.isEmpty)
        }
        return ReleaseHistory(releases: [], isAvailable: false)
    }
}
