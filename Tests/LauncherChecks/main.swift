import Foundation
import LauncherCore

enum CheckError: LocalizedError {
    case failure(String)
    var errorDescription: String? {
        switch self { case .failure(let message): return message }
    }
}

func expect(_ condition: @autoclosure () -> Bool, _ description: String) throws {
    guard condition() else { throw CheckError.failure(description) }
}

func expectFailure(_ description: String, _ operation: () throws -> Void) throws {
    do {
        try operation()
    } catch is LaunchError {
        return
    }
    throw CheckError.failure(description)
}

let json = """
{"models": [
  {"slug": "gpt-6.2-astra", "context_window": 272000, "max_context_window": 872000},
  {"slug": "gpt-6.2-sol", "context_window": 500000, "max_context_window": 872000},
  {"slug": "local-model", "context_window": 64000, "effective_context_window_percent": 90, "auto_compact_token_limit": 40000}
]}
"""
let models = try JSONDecoder().decode(ModelCatalog.self, from: Data(json.utf8)).models

func settings(_ model: String, _ window: String = "", _ threshold: String = "") throws -> LaunchSettings {
    try LaunchSettings(model: model, window: window, threshold: threshold, catalog: models)
}

let astra = try settings("gpt-6.2-astra", "800000", "700000")
let id = UUID(uuidString: "abcdeabc-f123-1234-9abc-cdef12345678")!
try expect(astra.budgets?.usable == 760000, "Astra usable context")
try expect(astra.budgets?.compactMaximum == 720000, "Astra compaction cap")
try expect(astra.arguments(for: .resume(id: id)) == [
    "resume", id.uuidString.lowercased(), "--model=gpt-6.2-astra", "--no-daemon",
    "-c", "model_context_window=800000", "-c", "model_auto_compact_token_limit=700000",
], "Native Astra resume arguments")

let sol = try settings("gpt-6.2-sol")
try expect(sol.budgets?.usable == 475000, "Default Sol usable context")
try expect(sol.budgets?.defaultThreshold == 450000, "Default Sol compaction")
try expect(sol.arguments(for: .resume(id: nil)) == ["resume", "--all", "--include-non-interactive", "--model=gpt-6.2-sol"], "No overrides on default Sol")

_ = try settings("gpt-6.2-astra", "872000", "784800")
try expectFailure("Reject window one token above model cap") { _ = try settings("gpt-6.2-astra", "872001") }
try expectFailure("Reject threshold one token above 90 percent") { _ = try settings("gpt-6.2-astra", "", "244801") }
try expectFailure("Reject unverified custom window") { _ = try settings("other/model-2026", "30000") }
try expectFailure("Use declared default as bound when no cap is known") { _ = try settings("local-model", "64001") }
let local = try settings("local-model")
try expect(local.budgets?.usable == 57600, "Respect model-specific usable percentage")
try expect(local.budgets?.defaultThreshold == 40000, "Respect model-specific threshold")

let custom = try settings("other/model-2026")
let folder = URL(fileURLWithPath: "/tmp/Custom project")
try expect(custom.arguments(for: .new(directory: folder)) == ["--cd", folder.path, "--model=other/model-2026"], "Manual model selection")
let defaults = try settings("")
try expect(defaults.arguments(for: .resume(id: nil)) == ["resume", "--all", "--include-non-interactive"], "Keep saved model when no explicit override")
for value in ["0", "-1", "1.5", "100,000", "9223372036854775808"] {
    try expectFailure("Reject malformed window \(value)") { _ = try settings("gpt-6.2-sol", value) }
    try expectFailure("Reject malformed threshold \(value)") { _ = try settings("gpt-6.2-sol", "", value) }
}
try expectFailure("Reject embedded newline in model ID") { _ = try settings("embedded\nnewline") }

func checkTerminalArguments() throws {
    let temp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: temp, withIntermediateDirectories: false)
    defer { try? FileManager.default.removeItem(at: temp) }
    let script = temp.appendingPathComponent("Launch test.command")
    let arguments = ["%s\\n", "带 空格", "O'Connor", "$()", "`printf altered`", "line\nbreak"]
    let contents = TerminalCommand.file(executable: URL(fileURLWithPath: "/usr/bin/printf"), arguments: arguments)
    try contents.write(to: script, atomically: true, encoding: .utf8)
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/bin/zsh")
    process.arguments = [script.path]
    let output = Pipe()
    process.standardOutput = output
    try process.run()
    let data = output.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()
    try expect(process.terminationStatus == 0, "Terminal script runs successfully")
    try expect(String(decoding: data, as: UTF8.self) == arguments.dropFirst().joined(separator: "\n") + "\n", "Pass special characters as literal arguments")
    try expect(!FileManager.default.fileExists(atPath: script.path), "Terminal script removes itself")
}

try checkTerminalArguments()
print("PASS: model defaults, numeric bounds, launch isolation, resume, and Terminal argument escaping")
