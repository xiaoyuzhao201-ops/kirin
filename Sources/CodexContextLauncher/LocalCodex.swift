import AppKit
import LauncherCore

enum LocalCodexError: LocalizedError {
    case cliMissing, terminalMissing, catalogUnavailable

    var errorDescription: String? {
        switch self {
        case .cliMissing: return "找不到 Codex CLI。请安装 Codex 或手动选择可执行文件。"
        case .terminalMissing: return "找不到 macOS 终端应用。"
        case .catalogUnavailable: return "模型目录读取失败。可刷新或手动输入模型 ID，并沿用窗口与压缩设置。"
        }
    }
}

enum LocalCodex {
    static func findExecutable() -> URL? {
        let workspace = NSWorkspace.shared
        let home = FileManager.default.homeDirectoryForCurrentUser
        var candidates: [URL] = []
        if let bundle = workspace.urlForApplication(withBundleIdentifier: "com.openai.codex") {
            candidates.append(
                bundle.appendingPathComponent("Contents/Resources/codex-cli/CodexCLI.app/Contents/MacOS/codex")
            )
            candidates.append(bundle.appendingPathComponent("Contents/Resources/codex"))
        }
        let paths = ProcessInfo.processInfo.environment["PATH"]?.split(separator: ":") ?? []
        let directories = ["/opt/homebrew/bin", "/usr/local/bin", home.appendingPathComponent(".local/bin").path]
            + paths.map(String.init).filter { $0.hasPrefix("/") }
        candidates += directories.map { URL(fileURLWithPath: $0).appendingPathComponent("codex") }
        return candidates.first { FileManager.default.isExecutableFile(atPath: $0.path) }
    }

    static func readCatalog(executable: URL, workingDirectory: URL) throws -> [CatalogModel] {
        let process = Process()
        process.executableURL = executable
        process.arguments = ["debug", "models"]
        process.currentDirectoryURL = workingDirectory
        process.standardInput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        let output = Pipe()
        process.standardOutput = output
        try process.run()
        // Drain stdout before waiting so a large model catalog cannot fill the pipe.
        let timeout = DispatchWorkItem { if process.isRunning { process.interrupt() } }
        DispatchQueue.global().asyncAfter(deadline: .now() + 20, execute: timeout)
        defer { timeout.cancel() }
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0,
              let models = try? JSONDecoder().decode(ModelCatalog.self, from: data).models,
              !models.isEmpty else { throw LocalCodexError.catalogUnavailable }
        return models
    }

    static func openInTerminal(executable: URL, arguments: [String], completion: @escaping (Error?) -> Void) {
        let workspace = NSWorkspace.shared
        guard let terminal = workspace.urlForApplication(withBundleIdentifier: "com.apple.Terminal") else {
            completion(LocalCodexError.terminalMissing)
            return
        }
        let manager = FileManager.default
        let directory = manager.temporaryDirectory.appendingPathComponent("codex-launch-\(UUID().uuidString)")
        let script = directory.appendingPathComponent("启动 Codex.command")
        do {
            try manager.createDirectory(at: directory, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        } catch {
            completion(error)
            return
        }
        do {
            let contents = TerminalCommand.file(executable: executable, arguments: arguments)
            try contents.write(to: script, atomically: true, encoding: .utf8)
            try manager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: script.path)
        } catch {
            try? manager.removeItem(at: directory)
            completion(error)
            return
        }

        workspace.open([script], withApplicationAt: terminal, configuration: .init()) { _, error in
            if error != nil { try? manager.removeItem(at: directory) }
            DispatchQueue.main.async { completion(error) }
        }
    }
}
