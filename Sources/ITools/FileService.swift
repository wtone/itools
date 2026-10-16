import AppKit
import Combine
import IToolsCore

final class FileService: ObservableObject {
    @Published var selection: [URL] = []
    @Published var favorites: [URL] = []
    @Published var templates: [URL] = []
    @Published var result = ""
    @Published var working = false
    @Published var cutFiles: [URL] = []
    @Published var scanEntries: [DiskEntry] = []
    @Published var scanSummary = ""
    var scanCancellation: ScanCancellation?
    var archivePassword: String?
    var finderDirect = false
    var finderApplication: String?
    var systemOperationInProgress = false
    var fileClipboard = NativeFileClipboard()
    var recycledFiles: [URL: URL] = [:]
    var openedApplications: [URL] = []
    var applicationOpener: (([URL], URL, @escaping (Error?) -> Void) -> Void)?
    var recycleHandler: (([URL], @escaping ([URL: URL], Error?) -> Void) -> Void)?
    var operationIssues: [String] = []
    var revealedFiles: [URL] = []
    var openedDirectory: URL?
    // Tests can observe the exact URL sent to Terminal without injecting keystrokes.
    var terminalOpener: ((URL, URL, @escaping (Error?) -> Void) -> Void)?
    @Published var pendingFinderAction: String?
    var pendingActionTitle: String {
        FinderActions.action(pendingFinderAction ?? "")?.title ?? "选择文件"
    }
    let queue = DispatchQueue(label: "itools.files", qos: .userInitiated)
    init() {
        favorites = Storage.load([URL].self, "folders.json", fallback: [])
        refreshTemplates()
    }
    var directory: URL? {
        guard let first = selection.first else { return nil }
        return (try? first.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true ? first : first.deletingLastPathComponent()
    }
    func choose() { let p = NSOpenPanel(); p.canChooseFiles = true; p.canChooseDirectories = true; p.allowsMultipleSelection = true; if p.runModal() == .OK { selection = p.urls } }
    func refreshTemplates() { templates = ((try? FileManager.default.contentsOfDirectory(at: Storage.url("Templates"), includingPropertiesForKeys: nil)) ?? []).sorted { $0.lastPathComponent < $1.lastPathComponent } }
    func createFile(ext: String = "txt", template: URL? = nil) {
        guard let directory = directory ?? Panels.chooseFiles(multiple: false, directories: true).first else { return }
        NoticeCenter.shared.perform {
            let proposed = template?.lastPathComponent ?? "未命名.\(ext)"
            let name: String
            if finderDirect { name = try FileOperations.uniqueURL(in: directory, name: proposed).lastPathComponent }
            else { guard let entered = Panels.text("新建文件名称", initial: proposed) else { return }; name = entered }
            try FileOperations.validateName(name)
            let url: URL
            if let template = template {
                url = directory.appendingPathComponent(name)
                guard !FileManager.default.fileExists(atPath: url.path) else { throw FileOperationError.conflict(name) }
                try FileManager.default.copyItem(at: template, to: url)
            } else {
                let content: String
                switch ext { case "json": content = "{\n}\n"; case "html": content = "<!doctype html>\n<html lang=\"zh-CN\"><meta charset=\"utf-8\"><title>文档</title><body></body></html>\n"
                case "xml": content = "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n<document/>\n"; case "md": content = "# 新文档\n"; case "rtf": content = "{\\rtf1\\ansi }"; default: content = "" }
                url = try FileOperations.create(in: directory, name: name, data: Data(content.utf8))
            }
            selection = [url]; reveal([url]); NoticeCenter.shared.success("已新建 " + name)
        }
    }
    func importTemplate() {
        guard let url = Panels.chooseFiles(multiple: false).first else { return }
        NoticeCenter.shared.perform {
            let directory = Storage.url("Templates")
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let destination = try FileOperations.uniqueURL(in: directory, name: url.lastPathComponent)
            try FileManager.default.copyItem(at: url, to: destination); refreshTemplates()
        }
    }
    func addFavorite() {
        guard let url = Panels.chooseFiles(multiple: false, directories: true).first, !favorites.contains(url) else { return }
        favorites.append(url); NoticeCenter.shared.perform { try Storage.save(favorites, "folders.json") }
    }
    func removeFavorite(_ url: URL) { favorites.removeAll { $0 == url }; NoticeCenter.shared.perform { try Storage.save(favorites, "folders.json") } }
    func copyPaths() { copyText(selection.map(\.path).joined(separator: "\n")); NoticeCenter.shared.success("已复制文件路径") }
    func terminal() {
        guard let directory = directory else { return }
        // Launch Services opens this folder in Terminal; no shell or AppleScript interpolation.
        guard let terminal = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.Terminal") else {
            NoticeCenter.shared.report(UserFacingError("未找到系统终端应用。")); return
        }
        working = true; systemOperationInProgress = true; openedDirectory = directory
        let completion: (Error?) -> Void = { error in
            DispatchQueue.main.async {
                self.systemOperationInProgress = false; self.working = false
                if let error = error { NoticeCenter.shared.report(error) }
            }
        }
        if let opener = terminalOpener { opener(directory, terminal, completion) }
        else { NSWorkspace.shared.open([directory], withApplicationAt: terminal, configuration: .init()) { _, error in completion(error) } }
    }
    func openWith() {
        guard !selection.isEmpty else { return }
        if finderDirect, let chosen = finderApplication {
            if chosen == "system-default" {
                var groups: [URL: [URL]] = [:]
                for file in selection {
                    guard let app = NSWorkspace.shared.urlForApplication(toOpen: file) else {
                        NoticeCenter.shared.report(UserFacingError("系统没有为 \(file.lastPathComponent) 设置默认应用，请使用「打开方式」选择应用。")); return
                    }
                    groups[app, default: []].append(file)
                }
                openInApplications(groups); return
            }
            let app = URL(fileURLWithPath: chosen)
            guard let bundle = Bundle(url: app), bundle.bundleIdentifier != nil,
                  let executable = bundle.executableURL, FileManager.default.isExecutableFile(atPath: executable.path) else {
                NoticeCenter.shared.report(UserFacingError("所选应用已移动或不可用，请重新打开「打开方式」菜单。")); return
            }
            openInApplications([app: selection]); return
        }
        guard let app = Panels.chooseFiles(types: ["app"], multiple: false, startingAt: URL(fileURLWithPath: "/Applications")).first else { return }
        openInApplications([app: selection])
    }
    func openInApplications(_ groups: [URL: [URL]]) {
        guard !groups.isEmpty else { return }
        working = true; systemOperationInProgress = true; openedApplications = Array(groups.keys)
        let pending = DispatchGroup()
        for (app, files) in groups {
            pending.enter()
            let done: (Error?) -> Void = { error in
                DispatchQueue.main.async {
                    if let error = error { NoticeCenter.shared.report(error) }
                    pending.leave()
                }
            }
            if let opener = applicationOpener { opener(files, app, done) }
            else { NSWorkspace.shared.open(files, withApplicationAt: app, configuration: .init()) { _, error in done(error) } }
        }
        pending.notify(queue: .main) { self.systemOperationInProgress = false; self.working = false }
    }
    func transfer(move: Bool, destination: URL? = nil, files: [URL]? = nil, clipboardChange: Int? = nil) {
        let sources = files ?? selection
        guard !working, !sources.isEmpty, let destination = destination ?? Panels.chooseFiles(multiple: false, directories: true, startingAt: directory).first else { return }
        if move && !finderDirect && !Panels.confirm("移动 \(sources.count) 项文件？", detail: "目标：\(destination.path)\n同名文件会跳过。", action: "移动") { return }
        working = true
        queue.async {
            var errors: [String] = []; var completed: [URL] = []; var successfulSources: [URL] = []
            for source in sources {
                do { completed.append(try FileOperations.transfer(source, to: destination, move: move)); successfulSources.append(source) }
                catch { errors.append(source.lastPathComponent + ": " + error.localizedDescription) }
            }
            DispatchQueue.main.async {
                self.working = false; self.selection = completed
                if move { self.cutFiles.removeAll { successfulSources.contains($0) } }
                if let change = clipboardChange { self.fileClipboard.didMove(successfulSources, from: sources, changeCount: change) }
                self.result = "已\(move ? "移动" : "复制") \(completed.count) 项。" + (errors.isEmpty ? "" : "\n" + errors.joined(separator: "\n"))
                self.operationIssues = errors
                if self.finderDirect { self.reveal(completed) }
                NoticeCenter.shared.success(self.result)
            }
        }
    }
    func cut() {
        guard fileClipboard.write(selection) else { NoticeCenter.shared.report(UserFacingError("无法把文件放入系统剪贴板，请重试。")); return }
        cutFiles = selection; NoticeCenter.shared.success("文件已放入系统剪贴板；在 Finder 用 ⌥⌘V 移动，或右键粘贴移动")
    }
    func pasteCut() {
        let files = fileClipboard.files
        guard !files.isEmpty else { NoticeCenter.shared.report(UserFacingError("剪贴板中没有文件。请先在 Finder 拷贝文件，或使用 iTools「剪切」。")); return }
        guard let directory = directory else { return }
        cutFiles = files
        transfer(move: true, destination: directory, files: files, clipboardChange: fileClipboard.pasteboard.changeCount)
    }
    func reveal(_ urls: [URL]) {
        guard !urls.isEmpty else { return }; revealedFiles = urls
        if !ProcessInfo.processInfo.arguments.contains("--finder-direct-test") { NSWorkspace.shared.activateFileViewerSelecting(urls) }
    }
    func toggleHidden() {
        guard Panels.confirm("切换 \(selection.count) 项的隐藏状态？", detail: "可以在访达用 ⌘⇧. 查看隐藏文件。", action: "切换") else { return }
        NoticeCenter.shared.perform {
            for var url in selection {
                let old = try url.resourceValues(forKeys: [.isHiddenKey]).isHidden ?? false
                var values = URLResourceValues(); values.isHidden = !old; try url.setResourceValues(values)
            }
            NoticeCenter.shared.success("已切换隐藏状态")
        }
    }
    func trash() {
        guard !selection.isEmpty, finderDirect || Panels.confirm("将 \(selection.count) 项移到废纸篓？", detail: selection.prefix(8).map(\.lastPathComponent).joined(separator: "\n"), action: "移到废纸篓") else { return }
        recycle(selection)
    }
    func recycle(_ sources: [URL]) {
        working = true; systemOperationInProgress = true
        let completion: ([URL: URL], Error?) -> Void = { moved, error in
            DispatchQueue.main.async {
                self.recycledFiles = moved
                self.selection = sources.filter { moved[$0] == nil }
                self.systemOperationInProgress = false; self.working = false
                if let error = error { NoticeCenter.shared.report(error) }
            }
        }
        if let handler = recycleHandler { handler(sources, completion) }
        else { NSWorkspace.shared.recycle(sources, completionHandler: completion) }
    }
    func hash() {
        guard !working, !selection.isEmpty else { return }; working = true
        let files = selection
        queue.async {
            let results = files.map { file -> String in
                do { return file.lastPathComponent + "\n" + (try FileOperations.sha256(file)) }
                catch { return file.lastPathComponent + "\n" + error.localizedDescription }
            }
            DispatchQueue.main.async { self.result = results.joined(separator: "\n\n"); self.working = false }
        }
    }
    func rename() {
        guard !selection.isEmpty else { return }
        let panel = FileRenamePanel(files: selection)
        guard let plan = panel.run() else { return }
        NoticeCenter.shared.perform {
            try FileOperations.executeRename(plan); selection = plan.map { $0.1 }; result = "重命名完成"
            if finderDirect { reveal(selection) }
        }
    }
    func receive(_ url: URL) {
        guard url.absoluteString.utf8.count < 32768, url.scheme == "itools", url.host == "finder",
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return }
        let paths = (components.queryItems ?? []).filter { $0.name == "path" }.compactMap(\.value)
        guard paths.count <= 200, paths.allSatisfy({ $0.hasPrefix("/") && !$0.contains("\0") }) else { return }
        guard !working, let action = components.queryItems?.first(where: { $0.name == "action" })?.value,
              FinderActions.action(action) != nil || action == "hidden",
              !paths.isEmpty || FinderActions.action(action)?.requiresPaths == false else { return }
        selection = paths.map { URL(fileURLWithPath: $0).standardizedFileURL }
        pendingFinderAction = components.queryItems?.first { $0.name == "action" }?.value
        // Custom URL schemes have no authenticated sender. Only stage a request; require an in-app click.
        result = FinderActions.action(action)?.requiresPaths == false
            ? "已接收访达显示设置请求。请确认后执行操作。" : "已接收访达选择。请检查文件后执行操作。"
    }
    func executePending() {
        guard let action = pendingFinderAction else { return }; pendingFinderAction = nil
        performAction(action)
    }
}
