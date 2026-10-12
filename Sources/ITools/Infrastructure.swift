import AppKit
import SwiftUI
import AVFoundation
import Carbon
import IToolsCore
import UniformTypeIdentifiers

struct UserFacingError: LocalizedError {
    let message: String
    init(_ message: String) { self.message = message }
    var errorDescription: String? { message }
}
final class NoticeCenter: ObservableObject {
    static let shared = NoticeCenter()
    @Published var error: String?
    @Published var message: String = "所有工具准备就绪"
    var errorPresenter: ((String) -> Void)?
    func report(_ error: Error) { DispatchQueue.main.async {
        if let presenter = self.errorPresenter { presenter(error.localizedDescription) }
        else { self.error = error.localizedDescription }
    } }
    func success(_ text: String) { DispatchQueue.main.async { self.message = text } }
    func perform(_ work: () throws -> Void) { do { try work() } catch { report(error) } }
}
enum Storage {
    private static let lock = NSRecursiveLock()
    private static var unreadable = Set<String>()
    private static let smokeRoot = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("itools-smoke-" + UUID().uuidString, isDirectory: true)
    static var root: URL {
        if ProcessInfo.processInfo.arguments.contains("--finder-direct-test"),
           let path = ProcessInfo.processInfo.environment["ITOOLS_FINDER_TEST_OUTPUT"] {
            return URL(fileURLWithPath: path).appendingPathComponent("State", isDirectory: true)
        }
        if ProcessInfo.processInfo.arguments.contains("--smoke-test") {
            if let output = ProcessInfo.processInfo.environment["ITOOLS_SMOKE_OUTPUT"] {
                return URL(fileURLWithPath: output).appendingPathComponent("State", isDirectory: true)
            }
            return smokeRoot
        }
        return FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("ITools", isDirectory: true)
    }
    static func url(_ name: String) -> URL { root.appendingPathComponent(name) }
    static func load<T: Decodable>(_ type: T.Type, _ name: String, fallback: T) -> T {
        lock.lock(); defer { lock.unlock() }
        let file = url(name)
        guard FileManager.default.fileExists(atPath: file.path) else { return fallback }
        do { return try JSONDecoder().decode(type, from: Data(contentsOf: file)) }
        catch {
            unreadable.insert(name)
            NoticeCenter.shared.report(UserFacingError("无法读取 \(name)：\(error.localizedDescription)。已停止写入该文件以保留原数据；请备份并修复或移走文件后重启。"))
            return fallback
        }
    }
    static func save<T: Encodable>(_ object: T, _ name: String) throws {
        lock.lock(); defer { lock.unlock() }
        guard !unreadable.contains(name) else { throw UserFacingError("\(name) 读取失败，已禁止覆盖原数据。请修复文件后重启。") }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let data = try JSONEncoder().encode(object)
        try data.write(to: url(name), options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url(name).path)
    }
}
enum Panels {
    static func activateIfNeeded() {
        if Bundle.main.bundleIdentifier == FinderHostLocation.workerBundleID { NSApp.activate(ignoringOtherApps: true) }
    }
    static func chooseFiles(types: [String]? = nil, multiple: Bool = true, directories: Bool = false, startingAt: URL? = nil) -> [URL] {
        activateIfNeeded()
        let panel = NSOpenPanel(); panel.allowsMultipleSelection = multiple
        panel.canChooseDirectories = directories; panel.canChooseFiles = !directories
        panel.directoryURL = startingAt
        if let types = types { panel.allowedContentTypes = types.compactMap { UTType(filenameExtension: $0) } }
        return panel.runModal() == .OK ? panel.urls : []
    }
    static func save(name: String, types: [String]) -> URL? {
        activateIfNeeded()
        let panel = NSSavePanel(); panel.nameFieldStringValue = name
        panel.allowedContentTypes = types.compactMap { UTType(filenameExtension: $0) }
        panel.canCreateDirectories = true
        return panel.runModal() == .OK ? panel.url : nil
    }
    static func confirm(_ title: String, detail: String, action: String) -> Bool {
        activateIfNeeded()
        let alert = NSAlert(); alert.messageText = title; alert.informativeText = detail
        alert.addButton(withTitle: action); alert.addButton(withTitle: "取消")
        return alert.runModal() == .alertFirstButtonReturn
    }
    static func text(_ title: String, initial: String = "") -> String? {
        activateIfNeeded()
        let alert = NSAlert(); alert.messageText = title
        let field = NSTextField(string: initial); field.frame = NSRect(x: 0, y: 0, width: 330, height: 26)
        alert.accessoryView = field; alert.addButton(withTitle: "确定"); alert.addButton(withTitle: "取消")
        alert.window.initialFirstResponder = field
        return alert.runModal() == .alertFirstButtonReturn ? field.stringValue : nil
    }
}
final class AppFocus {
    static let shared = AppFocus()
    private(set) var previous: NSRunningApplication?
    private var observer: NSObjectProtocol?
    private var pastePending = false
    init() {
        captureFrontmost()
        observer = NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { [weak self] note in
            guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                  self?.isTarget(app) == true else { return }
            self?.previous = app
        }
    }
    private func isTarget(_ app: NSRunningApplication) -> Bool {
        guard !app.isTerminated, app.processIdentifier != ProcessInfo.processInfo.processIdentifier,
              app.activationPolicy == .regular, !(app.bundleIdentifier?.hasPrefix("app.itools.mac") ?? false) else { return false }
        if PermissionCenter.shared.visitingSettings { return false }
        return true
    }
    @discardableResult func captureFrontmost() -> NSRunningApplication? {
        if let front = NSWorkspace.shared.frontmostApplication, isTarget(front) { previous = front }
        return previous.flatMap { !$0.isTerminated ? $0 : nil }
    }
    @discardableResult func paste(to target: NSRunningApplication? = nil, prepare: (() -> Bool)? = nil,
                                   completion: @escaping (Bool) -> Void = { _ in }) -> Bool {
        guard Permissions.requireEventPosting() else { completion(false); return false }
        guard !pastePending else { NoticeCenter.shared.success("正在切换到粘贴目标，请稍候。"); completion(false); return false }
        guard let app = target ?? captureFrontmost(), !app.isTerminated,
              app.processIdentifier != ProcessInfo.processInfo.processIdentifier else {
            NoticeCenter.shared.report(UserFacingError("没有可粘贴的目标应用。请先聚焦输入框，再用快捷键打开剪贴板。")); completion(false); return false
        }
        let expectedClipboard = NSPasteboard.general.changeCount
        let deadline = ProcessInfo.processInfo.systemUptime + 2
        pastePending = true
        func finish(_ success: Bool, _ message: String? = nil) {
            self.pastePending = false
            if let message = message { NoticeCenter.shared.report(UserFacingError(message)) }
            completion(success)
        }
        func check() {
            let flags = CGEventSource.flagsState(.combinedSessionState)
            let modifiersReleased = flags.intersection([.maskCommand, .maskControl, .maskAlternate, .maskShift]).isEmpty
            let readiness = PasteReadiness.evaluate(targetAlive: !app.isTerminated,
                clipboardUnchanged: NSPasteboard.general.changeCount == expectedClipboard,
                foreground: NSWorkspace.shared.frontmostApplication?.processIdentifier == app.processIdentifier,
                modifiersReleased: modifiersReleased, timedOut: ProcessInfo.processInfo.systemUptime >= deadline)
            switch readiness {
            case .waiting: DispatchQueue.main.asyncAfter(deadline: .now() + 0.04, execute: check)
            case .targetClosed: finish(false, "目标应用已退出，未发送粘贴操作。")
            case .clipboardChanged: finish(false, "切换期间剪贴板已被更新，本次粘贴已取消，请重新选择内容。")
            case .timedOut: finish(false, "未能切换到目标应用，或快捷键尚未松开。请聚焦输入框并松开按键后重试。")
            case .ready:
                guard Permissions.requireEventPosting() else { finish(false); return }
                guard let source = CGEventSource(stateID: .privateState),
                      let down = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: true),
                      let up = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: false) else {
                    finish(false, "未能创建粘贴按键事件，请重新打开 iTools 后再试。"); return
                }
                guard prepare?() ?? true else { finish(false); return }
                down.flags = .maskCommand; up.flags = .maskCommand
                down.post(tap: .cghidEventTap); up.post(tap: .cghidEventTap)
                NoticeCenter.shared.success("已向「\(app.localizedName ?? "目标应用")」发送粘贴操作")
                finish(true)
            }
        }
        NSApp.hide(nil)
        guard app.activate(options: .activateIgnoringOtherApps) else {
            finish(false, "无法激活目标应用。请先点选目标输入框，再重新打开剪贴板。"); return false
        }
        DispatchQueue.main.async(execute: check)
        return true
    }
    deinit { if let observer = observer { NSWorkspace.shared.notificationCenter.removeObserver(observer) } }
}
final class HotKeyCenter {
    static let shared = HotKeyCenter()
    private var handler: EventHandlerRef?
    private var refs: [UInt32: EventHotKeyRef] = [:]
    private var chords: [UInt32: KeyChord] = [:]
    private var actions: [UInt32: () -> Void] = [:]
    init() {
        var kind = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, event, _ in
            var id = EventHotKeyID()
            guard let event = event else { return OSStatus(eventNotHandledErr) }
            GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil,
                              MemoryLayout<EventHotKeyID>.size, nil, &id)
            DispatchQueue.main.async { HotKeyCenter.shared.actions[id.id]?() }
            return noErr
        }, 1, &kind, nil, &handler)
    }
    @discardableResult func register(_ id: UInt32, key: UInt32, modifiers: UInt32, action: @escaping () -> Void) -> OSStatus {
        if chords[id] == KeyChord(key, modifiers), refs[id] != nil { actions[id] = action; return noErr }
        var ref: EventHotKeyRef?
        let status = RegisterEventHotKey(key, modifiers, EventHotKeyID(signature: 0x49544F4C, id: id), GetApplicationEventTarget(), 0, &ref)
        if status == noErr, let ref = ref {
            unregister(id); refs[id] = ref; actions[id] = action; chords[id] = KeyChord(key, modifiers)
        }
        return status
    }
    func unregister(_ id: UInt32) { if let ref = refs.removeValue(forKey: id) { UnregisterEventHotKey(ref) }; actions.removeValue(forKey: id); chords.removeValue(forKey: id) }
    func stop() { refs.values.forEach { UnregisterEventHotKey($0) }; refs.removeAll(); actions.removeAll(); chords.removeAll() }
    deinit { stop(); if let handler = handler { RemoveEventHandler(handler) } }
}
@discardableResult func copyText(_ text: String) -> Bool {
    NSPasteboard.general.clearContents(); return NSPasteboard.general.setString(text, forType: .string)
}
func bytes(_ value: UInt64) -> String { ByteCountFormatter.string(fromByteCount: Int64(clamping: value), countStyle: .binary) }
