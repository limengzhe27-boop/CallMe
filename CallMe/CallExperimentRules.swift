import Foundation

enum CallDelayUnit: String, CaseIterable, Identifiable {
    case seconds
    case minutes
    case hours

    var id: Self { self }

    var title: String {
        switch self {
        case .seconds: return "秒"
        case .minutes: return "分钟"
        case .hours: return "小时"
        }
    }

    var multiplier: TimeInterval {
        switch self {
        case .seconds: return 1
        case .minutes: return 60
        case .hours: return 3_600
        }
    }
}

enum CallExperimentRules {
    static let maximumDelay: TimeInterval = 24 * 60 * 60
    private static let emergencyNumbers = Set(["110", "112", "119", "120", "911", "999"])

    static func callerNameError(_ name: String) -> String? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return "姓名不能为空" }
        if trimmed.count > 30 { return "姓名最多 30 个字符" }
        return nil
    }

    static func callerNumberError(_ number: String) -> String? {
        let digits = number.filter(\.isNumber)
        if digits.isEmpty { return "号码不能为空" }
        if emergencyNumbers.contains(digits) { return "请勿使用紧急号码" }
        if digits.count > 20 { return "号码最多 20 位" }
        return nil
    }

    static func customDelay(_ value: String, unit: CallDelayUnit) -> TimeInterval? {
        guard let amount = Double(value), amount > 0 else { return nil }
        let seconds = amount * unit.multiplier
        guard seconds <= maximumDelay else { return nil }
        return seconds
    }

    static func delayDescription(_ seconds: TimeInterval) -> String {
        if seconds >= 3_600, seconds.truncatingRemainder(dividingBy: 3_600) == 0 {
            return "\(Int(seconds / 3_600)) 小时"
        }
        if seconds >= 60, seconds.truncatingRemainder(dividingBy: 60) == 0 {
            return "\(Int(seconds / 60)) 分钟"
        }
        return "\(Int(seconds)) 秒"
    }
}

struct CallTemplate: Codable, Identifiable, Equatable {
    let id: UUID
    var callerName: String
    var callerNumber: String
    var callerAvatarData: Data
    var styleRawValue: String
    var delay: TimeInterval
    var ringtoneRawValue: String
    var updatedAt: Date

    var style: IncomingCallStyle {
        IncomingCallStyle(rawValue: styleRawValue) ?? .phone
    }

    var ringtone: IncomingRingtone {
        IncomingRingtone(rawValue: ringtoneRawValue) ?? .system
    }
}

enum CallTemplateStore {
    private static var fileURL: URL? {
        guard let directory = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first else { return nil }
        return directory.appendingPathComponent("CallMe", isDirectory: true)
            .appendingPathComponent("templates.json")
    }

    static func load() -> [CallTemplate] {
        guard let fileURL,
              let data = try? Data(contentsOf: fileURL),
              let templates = try? JSONDecoder().decode([CallTemplate].self, from: data) else {
            return []
        }
        return templates.sorted { $0.updatedAt > $1.updatedAt }
    }

    static func save(_ templates: [CallTemplate]) {
        guard let fileURL,
              let data = try? JSONEncoder().encode(Array(templates.prefix(12))) else { return }
        let directory = fileURL.deletingLastPathComponent()
        try? FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        try? data.write(to: fileURL, options: .atomic)
    }
}

enum CallEventHistory {
    static let maximumCount = 200

    static func normalized(_ events: [String]) -> [String] {
        Array(events.prefix(maximumCount))
    }
}
