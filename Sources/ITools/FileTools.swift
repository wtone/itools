import AppKit
import IToolsCore

extension FileService {
    func performAction(_ action: String) {
        guard !working else { return }
        if action.hasPrefix("new-"), action != "new-template" {
            createFile(ext: String(action.dropFirst(4))); return
        }
        switch action {
        case "new-template": chooseTemplate()
        case "copy-path": copyPaths()
        case "copy-name": copyText(selection.map(\.lastPathComponent).joined(separator: "\n")); result = "已拷贝名称"
        case "terminal": terminal()
        case "copy": transfer(move: false)
        case "move": transfer(move: true)
        case "sync-move": moveToSync()
        case "cut": cut()
        case "paste": pasteCut()
        case "hidden": toggleHidden()
        case "hide": setHidden(true)
        case "show": setHidden(false)
        case "extension": toggleExtensions()
        case "hash": hash()
        case "rename": rename()
        case "open-with": openWith()
        case "icon": setIcon(reset: false)
        case "icon-reset": setIcon(reset: true)
        case "alias": desktopAliases()
        case "airdrop": airDrop()
        case "named-folder": namedFolders()
        case "dissolve": dissolveFolders()
        case "favorite": favoriteSelection()
        case "favorites": openFavorite()
        case "writable": grantWrite()
        case "delete": permanentlyDelete()
        case "trash": trash()
        case "repair": repairNames()
        case "scan": scanDisk()
        case "password": setArchivePassword()
        case "archive-test": testArchive()
        case "fastzip": openFastZip()
        case "archive": archive()
        case "fast-7z", "fast-zip", "fast-7z-trash", "fast-zip-trash", "zip", "zip-trash", "encrypt-7z", "encrypt-zip":
            archive(preset: action)
        default: break
        }
    }
    func chooseTemplate() {
        guard !templates.isEmpty else {
            if finderDirect {
                if let template = Panels.chooseFiles(multiple: false, startingAt: directory).first { createFile(template: template) }
            } else { result = "请先在 iTools「访达与文件」中导入文档模板。" }
            return
        }
        if finderDirect && templates.count == 1 { createFile(template: templates[0]); return }
        guard let index = FilePanels.choose("从模板新建", items: templates.map(\.lastPathComponent)) else { return }
        createFile(template: templates[index])
    }
    func favoriteSelection() {
        for url in selection {
            let folder = (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true ? url : url.deletingLastPathComponent()
            if !favorites.contains(folder) { favorites.append(folder) }
        }
        NoticeCenter.shared.perform { try Storage.save(favorites, "folders.json"); result = "已添加到常用目录" }
    }
    func openFavorite() {
        guard !favorites.isEmpty else { result = "请先添加常用目录。"; return }
        if finderDirect && favorites.count == 1 { NSWorkspace.shared.open(favorites[0]); return }
        guard let index = FilePanels.choose("打开常用目录", items: favorites.map(\.path)) else { return }
        NSWorkspace.shared.open(favorites[index])
    }
    func moveToSync() {
        guard (finderDirect || Panels.confirm("移动至同步文件夹", detail: "选择网盘或同步应用在本机的同步目录。文件移动后，由该应用负责上传与同步。", action: "选择目录…")),
              let folder = Panels.chooseFiles(multiple: false, directories: true).first else { return }
        transfer(move: true, destination: folder)
    }
    func setIcon(reset: Bool) {
        let icon: NSImage?
        if reset { icon = nil }
        else {
            guard let file = Panels.chooseFiles(types: ["png","jpg","jpeg","tiff","icns","heic"], multiple: false).first,
                  let image = NSImage(contentsOf: file) else { return }
            icon = image
        }
        guard finderDirect || Panels.confirm(reset ? "恢复默认图标？" : "替换所选项目的图标？", detail: selection.map(\.lastPathComponent).joined(separator: "\n"), action: "应用") else { return }
        var failed: [String] = []
        for file in selection { if !NSWorkspace.shared.setIcon(icon, forFile: file.path, options: []) { failed.append(file.lastPathComponent) } }
        result = failed.isEmpty ? "图标已更新" : "以下项目未能更改图标：\n" + failed.joined(separator: "\n")
        operationIssues = failed
    }
    func desktopAliases() {
        NoticeCenter.shared.perform {
            let desktop = FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask)[0]
            var created: [URL] = []
            for source in selection {
                let target = try FileOperations.uniqueURL(in: desktop, name: source.lastPathComponent + " 替身")
                guard !AdvancedFiles.exists(target) else { throw FileOperationError.conflict(target.lastPathComponent) }
                let data = try source.bookmarkData(options: .suitableForBookmarkFile, includingResourceValuesForKeys: nil, relativeTo: nil)
                try URL.writeBookmarkData(data, to: target); created.append(target)
            }
            result = "已在桌面创建 \(created.count) 个 Finder 替身"; reveal(created)
        }
    }
    func airDrop() {
        guard let sharing = NSSharingService(named: .sendViaAirDrop), sharing.canPerform(withItems: selection) else {
            NoticeCenter.shared.report(UserFacingError("当前设备或所选项目暂不可使用隔空投送。")); return
        }
        sharing.perform(withItems: selection)
    }
    func namedFolders() {
        NoticeCenter.shared.perform {
            let plan = try AdvancedFiles.namedFolderPlan(selection)
            guard finderDirect || Panels.confirm("使用文件名新建文件夹？", detail: "创建同名空文件夹（去掉扩展名），原文件保留在原位置。\n" + plan.map(\.path).joined(separator: "\n"), action: "新建") else { return }
            try AdvancedFiles.createFolders(plan); result = "已创建 \(plan.count) 个空文件夹"
            if finderDirect { reveal(plan) }
        }
    }
    func dissolveFolders() {
        NoticeCenter.shared.perform {
            let folders = selection
            let plan = try AdvancedFiles.dissolvePlan(folders)
            guard finderDirect || Panels.confirm("解散 \(folders.count) 个文件夹？", detail: "把 \(plan.count) 项直接子内容移到各自的上一级，然后移除空文件夹。遇到重名则取消。\n" + folders.map(\.path).joined(separator: "\n"), action: "解散") else { return }
            working = true
            queue.async {
                do {
                    let remaining = try AdvancedFiles.dissolve(folders, expected: plan)
                    DispatchQueue.main.async {
                        self.working = false; self.selection = plan.map { $0.1 } + remaining
                        self.result = "已移出 \(plan.count) 项。" + (remaining.isEmpty ? "" : "\n以下文件夹仍有内容或无法移除，已保留：\n" + remaining.map(\.path).joined(separator: "\n"))
                        self.operationIssues = remaining.map(\.path)
                        if self.finderDirect { self.reveal(self.selection) }
                    }
                } catch { DispatchQueue.main.async { self.working = false }; NoticeCenter.shared.report(error) }
            }
        }
    }
    func setHidden(_ hidden: Bool) {
        guard finderDirect || Panels.confirm(hidden ? "隐藏已选文件？" : "取消隐藏已选文件？", detail: "可在 Finder 按 ⌘⇧. 查看隐藏项目。点号开头的文件名不会被修改。", action: "应用") else { return }
        applyMetadata { url in var v = URLResourceValues(); v.isHidden = hidden; var file = url; try file.setResourceValues(v) }
        if !hidden, selection.contains(where: { $0.lastPathComponent.hasPrefix(".") }) {
            result += "\n点号开头的项目仍会被 Finder 隐藏；请按需重命名。"
            operationIssues.append("点号开头的文件名仍会被 Finder 隐藏。")
        }
    }
    func toggleExtensions() {
        applyMetadata { url in
            let current = try url.resourceValues(forKeys: [.hasHiddenExtensionKey]).hasHiddenExtension ?? false
            var v = URLResourceValues(); v.hasHiddenExtension = !current; var file = url; try file.setResourceValues(v)
        }
        result += "\n若 Finder 开启了「显示所有文件扩展名」，该全局设置会优先。"
    }
    func applyMetadata(_ work: (URL) throws -> Void) {
        var errors: [String] = []; var count = 0
        for file in selection { do { try work(file); count += 1 } catch { errors.append(file.lastPathComponent + "：" + error.localizedDescription) } }
        result = "已更新 \(count) 项。" + (errors.isEmpty ? "" : "\n" + errors.joined(separator: "\n"))
        operationIssues = errors
    }
    func grantWrite() {
        guard finderDirect || Panels.confirm("增加所有者写入权限？", detail: "仅修改当前用户拥有的所选文件或目录，不递归修改子文件。不改变其他用户的权限，也不解除系统保护或只读磁盘限制。", action: "授予写入") else { return }
        applyMetadata { try AdvancedFiles.grantOwnerWrite($0) }
    }
    func permanentlyDelete() {
        NoticeCenter.shared.perform {
            let files = selection; try AdvancedFiles.validateDeletion(files)
            guard FileDeletionConfirmation(files: files).run() else { return }
            working = true
            queue.async {
                var failures: [URL] = []; var messages: [String] = []
                do {
                    try AdvancedFiles.validateDeletion(files)
                    for file in files {
                        do { try FileManager.default.removeItem(at: file) }
                        catch { failures.append(file); messages.append(file.path + "：" + error.localizedDescription) }
                    }
                } catch { failures = files; messages.append(error.localizedDescription) }
                DispatchQueue.main.async {
                    self.selection = failures; self.working = false
                    self.result = "已彻底删除 \(files.count - failures.count) 项。\n" + messages.joined(separator: "\n")
                    self.operationIssues = messages
                }
            }
        }
    }
    func repairNames() {
        guard !selection.isEmpty, let plan = FileRenamePanel(files: selection, repair: true).run() else { return }
        NoticeCenter.shared.perform {
            try FileOperations.executeRename(plan); selection = selection.map { file in plan.first { $0.0 == file }?.1 ?? file }
            result = "已修复 \(plan.count) 个名称"
            if finderDirect { reveal(selection) }
        }
    }
    func scanDisk() {
        guard let root = directory else { return }
        let cancellation = ScanCancellation(); scanCancellation = cancellation; scanEntries = []; scanSummary = "正在扫描 " + root.path; working = true
        queue.async {
            do {
                let entries = try DiskScanner.scan(root, cancellation: cancellation)
                DispatchQueue.main.async {
                    self.scanEntries = entries; self.working = false; self.scanCancellation = nil
                    let unreadable = entries.reduce(0) { $0 + $1.unreadable }
                    self.scanSummary = (cancellation.cancelled ? "已停止，显示部分结果 · " : "扫描完成 · ") + root.path +
                        "\n逻辑大小 \(bytes(entries.reduce(0) { $0 + $1.bytes })) · \(entries.reduce(0) { $0 + $1.files }) 个文件 · \(unreadable) 个无法读取的项目"
                }
            } catch {
                DispatchQueue.main.async { self.working = false; self.scanCancellation = nil; self.scanSummary = "扫描失败：" + error.localizedDescription }
            }
        }
    }
}
enum FilePanels {
    static func choose(_ title: String, items: [String], detail: String = "") -> Int? {
        Panels.activateIfNeeded()
        let alert = NSAlert(); alert.messageText = title; alert.informativeText = detail
        let popup = NSPopUpButton(frame: NSRect(x: 0, y: 0, width: 400, height: 28), pullsDown: false); popup.addItems(withTitles: items)
        alert.accessoryView = popup; alert.addButton(withTitle: "继续"); alert.addButton(withTitle: "取消")
        return alert.runModal() == .alertFirstButtonReturn ? popup.indexOfSelectedItem : nil
    }
    static func password(_ title: String, confirm: Bool = true, allowClear: Bool = false) -> String? {
        Panels.activateIfNeeded()
        let alert = NSAlert(); alert.messageText = title
        alert.informativeText = confirm ? "输入密码并重复确认。密码仅在内存中保存，退出会话后清除。" : "此压缩包需要密码，请输入正确的密码。"
        let stack = NSStackView(); stack.orientation = .vertical; stack.alignment = .leading; stack.spacing = 8
        let first = NSSecureTextField(); first.placeholderString = "密码"; first.frame.size = NSSize(width: 350, height: 25)
        let second = NSSecureTextField(); second.placeholderString = "再次输入密码"; second.frame.size = first.frame.size
        stack.addArrangedSubview(first); if confirm { stack.addArrangedSubview(second) }
        stack.frame = NSRect(x: 0, y: 0, width: 350, height: confirm ? 62 : 28)
        first.widthAnchor.constraint(equalToConstant: 350).isActive = true
        second.widthAnchor.constraint(equalToConstant: 350).isActive = true
        alert.accessoryView = stack; alert.addButton(withTitle: "确定"); alert.addButton(withTitle: "取消"); alert.window.initialFirstResponder = first
        if allowClear { alert.addButton(withTitle: "清除已存密码") }
        let response = alert.runModal()
        if allowClear && response == .alertThirdButtonReturn { return "" }
        guard response == .alertFirstButtonReturn else { return nil }
        guard (!confirm || (!first.stringValue.isEmpty && first.stringValue == second.stringValue)),
              first.stringValue.utf8.count <= 1024, first.stringValue.rangeOfCharacter(from: .controlCharacters) == nil else {
            NoticeCenter.shared.report(UserFacingError("密码为空、两次输入不一致，或包含不支持的控制字符。")); return nil
        }
        return first.stringValue
    }
}
