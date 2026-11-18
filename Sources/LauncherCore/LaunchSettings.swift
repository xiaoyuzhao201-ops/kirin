import Foundation

public struct ModelCatalog: Decodable {
    public let models: [CatalogModel]
}

public struct CatalogModel: Decodable {
    public let slug: String
    public let visibility: String?
    public let priority: Int?
    public let contextWindow: Int?
    public let maxContextWindow: Int?
    public let effectiveContextWindowPercent: Int?
    public let autoCompactTokenLimit: Int?

    enum CodingKeys: String, CodingKey {
        case slug, visibility, priority
        case contextWindow = "context_window"
        case maxContextWindow = "max_context_window"
        case effectiveContextWindowPercent = "effective_context_window_percent"
        case autoCompactTokenLimit = "auto_compact_token_limit"
    }

    public var defaultWindow: Int? {
        positive(contextWindow) ?? positive(maxContextWindow)
    }

    public var maximumWindow: Int? {
        positive(maxContextWindow) ?? positive(contextWindow)
    }

    private func positive(_ value: Int?) -> Int? {
        value.flatMap { $0 > 0 ? $0 : nil }
    }

    public func budgets(using windowOverride: Int?) -> ContextBudgets? {
        guard let window = windowOverride ?? defaultWindow else { return nil }
        let effectivePercent = effectiveContextWindowPercent ?? 95
        guard (1...100).contains(effectivePercent) else { return nil }
        let usable = percent(effectivePercent, of: window)
        let compactMaximum = min(percent(90, of: window), usable)
        return ContextBudgets(
            nominal: window,
            usable: usable,
            compactMaximum: compactMaximum,
            defaultThreshold: min(autoCompactTokenLimit ?? compactMaximum, compactMaximum)
        )
    }
}

private func percent(_ percent: Int, of value: Int) -> Int {
    (value / 100) * percent + ((value % 100) * percent) / 100
}

public struct ContextBudgets {
    public let nominal: Int
    public let usable: Int
    public let compactMaximum: Int
    public let defaultThreshold: Int
}

public enum SessionDestination {
    case new(directory: URL)
    case resume(id: UUID?)
}

public enum LaunchError: LocalizedError {
    case invalidModel, unknownWindow, invalidWindow, invalidThreshold
    case windowTooLarge(Int), thresholdTooLarge(Int)

    public var errorDescription: String? {
        switch self {
        case .invalidModel: return "模型 ID 不能包含空格或控制字符。"
        case .unknownWindow: return "当前模型目录缺少这个模型的窗口数据。可以清空数值并沿用 Codex 设置。"
        case .invalidWindow: return "上下文窗口请输入正整数。"
        case .invalidThreshold: return "压缩阈值请输入正整数。"
        case .windowTooLarge(let maximum): return "上下文窗口上限为 \(maximum.formatted()) Token。"
        case .thresholdTooLarge(let maximum): return "当前窗口允许的压缩阈值上限为 \(maximum.formatted()) Token。"
        }
    }
}

public struct LaunchSettings {
    public let model: String
    public let window: Int?
    public let threshold: Int?
    public let budgets: ContextBudgets?

    public init(model: String, window: String, threshold: String, catalog: [CatalogModel]) throws {
        let modelID = model.trimmingCharacters(in: .whitespacesAndNewlines)
        let invalid = CharacterSet.whitespacesAndNewlines.union(.controlCharacters)
        guard !modelID.unicodeScalars.contains(where: invalid.contains) else {
            throw LaunchError.invalidModel
        }
        self.model = modelID
        self.window = try Self.optionalInteger(window, error: .invalidWindow)
        self.threshold = try Self.optionalInteger(threshold, error: .invalidThreshold)

        let modelInfo = catalog.first { $0.slug == modelID }
        // The catalog's cap can be absent. Its declared default is the verified bound in that case.
        if let window = self.window {
            guard let maximum = modelInfo?.maximumWindow else { throw LaunchError.unknownWindow }
            guard window <= maximum else { throw LaunchError.windowTooLarge(maximum) }
        }
        budgets = modelInfo?.budgets(using: self.window)
        if let threshold = self.threshold {
            guard let budgets else { throw LaunchError.unknownWindow }
            guard threshold <= budgets.compactMaximum else {
                throw LaunchError.thresholdTooLarge(budgets.compactMaximum)
            }
        }
    }

    public func arguments(for destination: SessionDestination) -> [String] {
        var args: [String] = []
        switch destination {
        case .new(let directory):
            args += ["--cd", directory.path]
        case .resume(let id):
            args.append("resume")
            if let id {
                args.append(id.uuidString.lowercased())
            } else {
                args += ["--all", "--include-non-interactive"]
            }
        }
        if !model.isEmpty { args.append("--model=\(model)") }
        if window != nil || threshold != nil { args.append("--no-daemon") }
        if let window { args += ["-c", "model_context_window=\(window)"] }
        if let threshold { args += ["-c", "model_auto_compact_token_limit=\(threshold)"] }
        return args
    }

    private static func optionalInteger(_ text: String, error: LaunchError) throws -> Int? {
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return nil }
        guard value.utf8.allSatisfy({ (48...57).contains($0) }), let number = Int(value), number > 0 else {
            throw error
        }
        return number
    }
}

public enum TerminalCommand {
    public static func file(executable: URL, arguments: [String]) -> String {
        let command = ([executable.path] + arguments).map(shellQuote).joined(separator: " ")
        return """
        #!/bin/zsh
        /bin/rm -f -- "$0"
        /bin/rmdir -- "${0:h}" 2>/dev/null
        exec \(command)

        """
    }

    private static func shellQuote(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}
