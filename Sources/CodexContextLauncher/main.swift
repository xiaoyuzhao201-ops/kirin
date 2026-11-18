import AppKit
import LauncherCore

final class Launcher: NSObject, NSApplicationDelegate, NSComboBoxDelegate, NSTextFieldDelegate {
    private var window: NSWindow!
    private let session = NSSegmentedControl(labels: ["新建会话", "续接本机会话"], trackingMode: .selectOne, target: nil, action: nil)
    private let model = NSComboBox()
    private let context = NSTextField()
    private let threshold = NSTextField()
    private let sessionID = NSTextField()
    private let folderPath = NSTextField(labelWithString: "")
    private let cliPath = NSTextField(labelWithString: "")
    private let catalogStatus = NSTextField(labelWithString: "")
    private let estimate = NSTextField(wrappingLabelWithString: "")
    private let launch = NSButton(title: "在终端启动", target: nil, action: nil)
    private let preset = NSButton(title: "Astra 800K / 700K", target: nil, action: nil)
    private var folderRow: NSStackView!
    private var resumeRow: NSStackView!

    private var directory = FileManager.default.homeDirectoryForCurrentUser
    private var executable: URL?
    private var catalog: [CatalogModel] = []
    private var catalogGeneration = 0
    private var openingTerminal = false
    private var overridesModel = ""

    func applicationDidFinishLaunching(_ notification: Notification) {
        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 650, height: 400),
            styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false
        )
        window.title = "Codex 上下文启动器"
        window.isReleasedWhenClosed = false

        session.selectedSegment = 0
        session.target = self
        session.action = #selector(changeSession)
        model.placeholderString = "留空沿用默认模型或原会话模型"
        model.delegate = self
        model.completes = true
        model.isEditable = true
        model.widthAnchor.constraint(equalToConstant: 340).isActive = true
        context.placeholderString = "留空沿用 Codex 设置"
        threshold.placeholderString = "留空沿用 Codex 设置"
        sessionID.placeholderString = "留空在终端按标题选择"
        for field in [context, threshold, sessionID] {
            field.delegate = self
            field.widthAnchor.constraint(equalToConstant: 340).isActive = true
        }

        folderPath.lineBreakMode = .byTruncatingMiddle
        folderPath.widthAnchor.constraint(equalToConstant: 340).isActive = true
        cliPath.lineBreakMode = .byTruncatingMiddle
        cliPath.widthAnchor.constraint(equalToConstant: 340).isActive = true
        catalogStatus.textColor = .secondaryLabelColor
        catalogStatus.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        catalogStatus.lineBreakMode = .byTruncatingTail
        catalogStatus.widthAnchor.constraint(lessThanOrEqualToConstant: 600).isActive = true
        estimate.widthAnchor.constraint(equalToConstant: 598).isActive = true
        estimate.font = .systemFont(ofSize: NSFont.smallSystemFontSize)

        folderRow = row("项目目录", folderPath, button("选择…", #selector(chooseFolder)))
        resumeRow = row("会话 ID", sessionID)
        let modes = row("会话", session)
        let modelRow = row("模型 ID", model, button("刷新", #selector(refreshCatalog)))
        let quickActions = row("", preset, button("清空覆盖", #selector(resetOverrides)))
        preset.target = self
        preset.action = #selector(applyPreset)
        launch.target = self
        launch.action = #selector(openSession)
        launch.bezelStyle = .rounded
        launch.keyEquivalent = "\r"
        let upper = NSStackView(views: [
            modes, folderRow, resumeRow, modelRow, quickActions,
            row("上下文窗口", context), row("压缩阈值", threshold),
            estimate, catalogStatus, row("Codex CLI", cliPath, button("更换…", #selector(chooseCLI))),
        ])
        upper.orientation = .vertical
        upper.alignment = .leading
        upper.spacing = 12
        upper.detachesHiddenViews = true

        let content = window.contentView!
        for view in [upper, launch] {
            view.translatesAutoresizingMaskIntoConstraints = false
            content.addSubview(view)
        }
        NSLayoutConstraint.activate([
            upper.topAnchor.constraint(equalTo: content.topAnchor, constant: 24),
            upper.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 26),
            upper.trailingAnchor.constraint(lessThanOrEqualTo: content.trailingAnchor, constant: -26),
            launch.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -26),
            launch.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -21),
            launch.topAnchor.constraint(greaterThanOrEqualTo: upper.bottomAnchor, constant: 12),
        ])

        folderPath.stringValue = (directory.path as NSString).abbreviatingWithTildeInPath
        executable = LocalCodex.findExecutable()
        updateCLIPath()
        changeSession()
        window.center()
        window.makeKeyAndOrderFront(nil)
        window.makeFirstResponder(nil)
        NSApplication.shared.activate(ignoringOtherApps: true)
        refreshCatalog()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    private func row(_ title: String, _ controls: NSView...) -> NSStackView {
        let caption = NSTextField(labelWithString: title)
        caption.widthAnchor.constraint(equalToConstant: 94).isActive = true
        caption.alignment = .right
        let row = NSStackView(views: [caption] + controls)
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 12
        return row
    }

    private func button(_ title: String, _ action: Selector) -> NSButton {
        let button = NSButton(title: title, target: self, action: action)
        button.bezelStyle = .rounded
        return button
    }

    @objc private func changeSession() {
        folderRow.isHidden = session.selectedSegment == 1
        resumeRow.isHidden = session.selectedSegment != 1
        updateValidation()
    }

    @objc private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.directoryURL = directory
        panel.prompt = "使用此目录"
        panel.beginSheetModal(for: window) { [weak self] response in
            guard let self, response == .OK, let folder = panel.url else { return }
            self.directory = folder
            self.folderPath.stringValue = (folder.path as NSString).abbreviatingWithTildeInPath
            self.refreshCatalog()
        }
    }

    @objc private func chooseCLI() {
        let panel = NSOpenPanel()
        panel.message = "选择 Codex CLI 可执行文件。"
        panel.prompt = "使用此文件"
        panel.directoryURL = executable?.deletingLastPathComponent()
        panel.beginSheetModal(for: window) { [weak self] response in
            guard let self, response == .OK, let program = panel.url else { return }
            guard FileManager.default.isExecutableFile(atPath: program.path) else {
                self.showError("请选择可执行的 Codex CLI 文件。")
                return
            }
            self.executable = program
            self.updateCLIPath()
            self.refreshCatalog()
        }
    }

    private func updateCLIPath() {
        cliPath.stringValue = (executable?.path as NSString?)?.abbreviatingWithTildeInPath ?? "未找到"
        cliPath.toolTip = executable?.path
    }

    @objc private func refreshCatalog() {
        catalogGeneration += 1
        let request = catalogGeneration
        catalog = []
        model.removeAllItems()
        updateValidation()
        guard let executable else {
            catalogStatus.stringValue = LocalCodexError.cliMissing.localizedDescription
            return
        }
        catalogStatus.stringValue = "正在读取模型目录…"
        let directory = self.directory
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let result = Result { try LocalCodex.readCatalog(executable: executable, workingDirectory: directory) }
            DispatchQueue.main.async { self?.applyCatalog(result, request: request) }
        }
    }

    private func applyCatalog(_ result: Result<[CatalogModel], Error>, request: Int) {
        guard request == catalogGeneration else { return }
        switch result {
        case .success(let models):
            catalog = models
            let listed = models.filter { $0.visibility != "hide" }
                .sorted { ($0.priority ?? Int.max, $0.slug) < ($1.priority ?? Int.max, $1.slug) }
            model.addItems(withObjectValues: listed.map(\.slug))
            catalogStatus.stringValue = "已读取 \(listed.count) 个模型。也可以手动输入模型 ID。"
        case .failure:
            catalogStatus.stringValue = LocalCodexError.catalogUnavailable.localizedDescription
        }
        updateValidation()
    }

    @objc private func applyPreset() {
        model.stringValue = "gpt-6.2-astra"
        overridesModel = model.stringValue
        context.stringValue = "800000"
        threshold.stringValue = "700000"
        updateValidation()
    }

    @objc private func resetOverrides() {
        model.stringValue = ""
        context.stringValue = ""
        threshold.stringValue = ""
        updateValidation()
    }

    func controlTextDidChange(_ notification: Notification) { updateValidation() }
    func comboBoxSelectionDidChange(_ notification: Notification) {
        DispatchQueue.main.async { [weak self] in self?.updateValidation() }
    }

    private func settings() throws -> LaunchSettings {
        try LaunchSettings(
            model: model.stringValue, window: context.stringValue, threshold: threshold.stringValue, catalog: catalog
        )
    }

    private func destination() -> SessionDestination? {
        guard session.selectedSegment == 1 else { return .new(directory: directory) }
        let id = sessionID.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        if id.isEmpty { return .resume(id: nil) }
        return UUID(uuidString: id).map { .resume(id: $0) }
    }

    private func updateValidation() {
        let currentModel = model.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        if currentModel != overridesModel {
            context.stringValue = ""
            threshold.stringValue = ""
            overridesModel = currentModel
        }
        preset.isEnabled = catalog.contains { $0.slug == "gpt-6.2-astra" }
        estimate.textColor = .secondaryLabelColor
        launch.isEnabled = false
        do {
            let settings = try settings()
            guard destination() != nil else {
                estimate.textColor = .systemRed
                estimate.stringValue = "请输入有效的会话 ID，或留空从列表选择。"
                return
            }
            if let budgets = settings.budgets {
                let compact = settings.threshold ?? budgets.defaultThreshold
                let maximum = catalog.first { $0.slug == settings.model }?.maximumWindow
                let cap = maximum.map { " ｜窗口上限 \($0.formatted())" } ?? ""
                estimate.stringValue = "目录估算  \(budgets.nominal.formatted()) 标称 ｜\(budgets.usable.formatted()) 可用 ｜\(compact.formatted()) 压缩\(cap)"
            } else {
                estimate.stringValue = "空白项沿用 Codex 设置。数值按 Token 计。"
            }
            launch.isEnabled = executable != nil && !openingTerminal
        } catch {
            estimate.textColor = .systemRed
            estimate.stringValue = error.localizedDescription
        }
    }

    @objc private func openSession() {
        guard !openingTerminal, let executable, let destination = destination() else { return }
        do {
            let settings = try settings()
            openingTerminal = true
            updateValidation()
            LocalCodex.openInTerminal(executable: executable, arguments: settings.arguments(for: destination)) { [weak self] error in
                guard let self else { return }
                self.openingTerminal = false
                if let error {
                    self.updateValidation()
                    self.showError(error.localizedDescription)
                } else {
                    NSApplication.shared.terminate(nil)
                }
            }
        } catch {
            showError(error.localizedDescription)
        }
    }

    private func showError(_ message: String) {
        let alert = NSAlert()
        alert.messageText = "启动失败"
        alert.informativeText = message
        alert.addButton(withTitle: "好")
        alert.beginSheetModal(for: window)
    }
}

let app = NSApplication.shared
let launcher = Launcher()
let menuBar = NSMenu()
let applicationMenu = NSMenu()
applicationMenu.addItem(withTitle: "退出启动器", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
let applicationItem = NSMenuItem()
applicationItem.submenu = applicationMenu
menuBar.addItem(applicationItem)

let editMenu = NSMenu(title: "编辑")
editMenu.addItem(withTitle: "剪切", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
editMenu.addItem(withTitle: "拷贝", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
editMenu.addItem(withTitle: "粘贴", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
editMenu.addItem(withTitle: "全选", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
let editItem = NSMenuItem()
editItem.submenu = editMenu
menuBar.addItem(editItem)
app.mainMenu = menuBar
app.setActivationPolicy(.regular)
app.delegate = launcher
app.run()
