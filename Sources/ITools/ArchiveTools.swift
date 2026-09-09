import AppKit
import IToolsCore

extension FileService {
    var archiveExecutable: URL {
        let bundle = Bundle.main.bundleURL
        let host = Bundle.main.bundleIdentifier == FinderHostLocation.workerBundleID
            ? bundle.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent() : bundle
        return host.appendingPathComponent("Contents/Helpers/7zz")
    }
    func setArchivePassword() {
        if finderDirect {
            guard let password = FilePanels.password("设置或清除压缩密码", allowClear: true) else { return }
            archivePassword = password.isEmpty ? nil : password
            return
        }
        guard let choice = FilePanels.choose("加密密码", items: ["设置 / 替换本次会话的密码", "清除本次会话的密码"], detail: finderDirect ? "密码仅保留在访达操作组件内存中；30 分钟未操作后清除，也可在此手动清除。" : "密码仅存在内存中，退出 iTools 后清除。") else { return }
        if choice == 1 { archivePassword = nil; result = "已清除加密密码"; return }
        if let password = FilePanels.password("设置加密密码") { archivePassword = password; result = "已设置本次会话的加密密码" }
    }
    func archive(preset: String? = nil) {
        guard !working, !selection.isEmpty else { return }
        var format = preset?.contains("7z") == true ? "7z" : "zip"
        var level = preset?.hasPrefix("fast-") == true ? 0 : 5
        var encrypted = preset?.hasPrefix("encrypt-") == true
        var removeOriginals = preset?.hasSuffix("-trash") == true
        if preset == nil {
            guard let settings = ArchivePanel.options() else { return }
            format = settings.format; level = settings.level; encrypted = settings.encrypt; removeOriginals = settings.trash
        }
        let password: String?
        if encrypted {
            guard let value = archivePassword ?? FilePanels.password("设置本次压缩密码") else { return }
            password = value
        } else { password = nil }
        let name = selection.count == 1 ? selection[0].lastPathComponent : "归档"
        let destination: URL
        if finderDirect, preset != nil {
            do { destination = try FileOperations.uniqueURL(in: selection[0].deletingLastPathComponent(), name: name + "." + format) }
            catch { NoticeCenter.shared.report(error); return }
        } else {
            guard let chosen = Panels.save(name: name + "." + format, types: [format]) else { return }
            destination = chosen
        }
        let sources = selection
        if removeOriginals && !finderDirect, !Panels.confirm("压缩后移除原件？", detail: "压缩包通过完整性校验、且原件未改变后，再确认将原件移到废纸篓。\n通用 ZIP / 7z 不保证保留 macOS 自定义图标、扩展属性和资源分叉。", action: "开始压缩") { return }
        let options = ArchiveOptions(format: format, level: level, password: password)
        let executable = archiveExecutable
        working = true; result = "正在压缩并校验，较大的文件需要一些时间…"
        queue.async {
            do {
                let initial = removeOriginals ? try FileSnapshot.capture(sources) : [:]
                try ArchiveEngine.create(sources, at: destination, executable: executable, options: options)
                let unchanged = try !removeOriginals || initial == FileSnapshot.capture(sources)
                DispatchQueue.main.async {
                    self.working = false; self.result = "已保存并校验 " + destination.path
                    if self.finderDirect { self.reveal([destination]) }
                    if removeOriginals {
                        guard unchanged else { self.result += "\n压缩过程中原件有变化，已保留全部原件。"; self.operationIssues = [self.result]; return }
                        guard self.finderDirect || Panels.confirm("压缩包已校验，移除原件？", detail: "请确保压缩包符合需要。以下原件将移到废纸篓：\n" + sources.map(\.path).joined(separator: "\n"), action: "移到废纸篓") else { return }
                        // Check again after the user reviewed the confirmation.
                        self.working = true
                        self.queue.async {
                            do {
                                guard try FileSnapshot.capture(sources) == initial else { throw UserFacingError("原件已改变，已保留原文件。") }
                                DispatchQueue.main.async { self.recycle(sources) }
                            } catch { DispatchQueue.main.async { self.working = false }; NoticeCenter.shared.report(error) }
                        }
                    }
                }
            } catch {
                DispatchQueue.main.async { self.working = false; self.result = "压缩未完成，原件保留。" }
                NoticeCenter.shared.report(error)
            }
        }
    }
    func testArchive() {
        guard let file = selection.first, selection.count == 1 else {
            NoticeCenter.shared.report(UserFacingError("请只选择一个压缩包进行校验。")); return
        }
        validateArchive(file, password: archivePassword, mayAskPassword: true)
    }
    private func validateArchive(_ file: URL, password: String?, mayAskPassword: Bool) {
        let executable = archiveExecutable; working = true
        queue.async {
            do { try ArchiveEngine.validate(file, executable: executable, password: password)
                DispatchQueue.main.async { self.working = false; self.result = "完整性校验通过：" + file.path }
            } catch {
                DispatchQueue.main.async {
                    // Keep working true until the password dialog has finished.
                    if error is ArchivePasswordRequired, mayAskPassword {
                        if let entered = FilePanels.password("输入压缩包密码", confirm: false) {
                            self.validateArchive(file, password: entered, mayAskPassword: false)
                        } else { self.working = false }
                    } else { NoticeCenter.shared.report(error); self.working = false }
                }
            }
        }
    }
    func openFastZip() {
        guard let app = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "cn.better365.FastZip") else {
            NoticeCenter.shared.report(UserFacingError("未找到 FastZip。可使用 iTools 内置的压缩功能。")); return
        }
        openInApplications([app: selection])
    }
}
enum ArchivePanel {
    struct Options { let format: String; let level: Int; let encrypt: Bool; let trash: Bool }
    static func options() -> Options? {
        Panels.activateIfNeeded()
        let alert = NSAlert(); alert.messageText = "自定义压缩"
        alert.informativeText = "0 级为快速打包（不压缩）。加密使用 AES-256；加密 ZIP 需用支持 AES 的解压软件打开。ZIP 密码使用英文/数字/半角符号，7z 支持中文密码。"
        let format = NSPopUpButton(); format.addItems(withTitles: ["ZIP", "7z"])
        let level = NSPopUpButton(); level.addItems(withTitles: ["0 · 仅打包", "1 · 快速", "5 · 标准", "9 · 最大压缩"]); level.selectItem(at: 2)
        let encrypt = NSButton(checkboxWithTitle: "使用密码加密", target: nil, action: nil)
        let trash = NSButton(checkboxWithTitle: "校验成功后确认将原件移到废纸篓", target: nil, action: nil)
        let stack = NSStackView(views: [format, level, encrypt, trash]); stack.orientation = .vertical; stack.alignment = .leading; stack.spacing = 10
        stack.frame = NSRect(x: 0, y: 0, width: 380, height: 140)
        format.widthAnchor.constraint(equalToConstant: 380).isActive = true
        level.widthAnchor.constraint(equalToConstant: 380).isActive = true
        alert.accessoryView = stack; alert.addButton(withTitle: "选择保存位置…"); alert.addButton(withTitle: "取消")
        guard alert.runModal() == .alertFirstButtonReturn else { return nil }
        return Options(format: format.indexOfSelectedItem == 0 ? "zip" : "7z", level: [0,1,5,9][level.indexOfSelectedItem], encrypt: encrypt.state == .on, trash: trash.state == .on)
    }
}
