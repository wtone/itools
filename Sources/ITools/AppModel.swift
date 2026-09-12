import AppKit
import SwiftUI
import Combine
import IToolsCore

enum ToolPage: String, CaseIterable, Identifiable {
    case overview = "总览", capture = "截图与录制", clipboard = "剪贴板与短语", files = "访达与文件", monitor = "系统状态", utilities = "窗口与效率", settings = "设置"
    var id: String { rawValue }
    var icon: String {
        switch self {
        case .overview: return "square.grid.2x2"; case .capture: return "viewfinder"; case .clipboard: return "doc.on.clipboard"
        case .files: return "folder"; case .monitor: return "waveform.path.ecg"; case .utilities: return "rectangle.3.offgrid"
        case .settings: return "gearshape"
        }
    }
    var subtitle: String {
        switch self {
        case .overview: return "把常用工具收在一起，让这台 Mac 继续顺手。"
        case .capture: return "截取、标注与记录，灵感就在眼前。"
        case .clipboard: return "复制过的内容，需要时找得到。"
        case .files: return "新建、整理与快速打开，少走几层文件夹。"
        case .monitor: return "看看这台 Mac 此刻的工作状态。"
        case .utilities: return "安排好窗口，专注手头的事。"
        case .settings: return "只运行需要的功能，按需授予系统权限。"
        }
    }
}
final class AppModel: ObservableObject {
    @Published var page: ToolPage = .overview
    @Published var captureEnabled = true { didSet { UserDefaults.standard.set(captureEnabled, forKey: "capture.enabled") } }
    @Published var filesEnabled = true { didSet { UserDefaults.standard.set(filesEnabled, forKey: "files.enabled") } }
    let clipboard = ClipboardService()
    let clipboardPanel = ClipboardPanelPreferences(persist: !ProcessInfo.processInfo.arguments.contains("--smoke-test"))
    lazy var shortcuts = ShortcutManager()
    @Published var utilityAnchor = ""
    let capture = CaptureService()
    let recorder = RecordingService()
    let monitor = MonitorService()
    let menuBar = MenuBarPreferences(persistChanges: !ProcessInfo.processInfo.arguments.contains("--smoke-test"))
    let quickPanel = QuickPanelPreferences(persist: !ProcessInfo.processInfo.arguments.contains("--smoke-test"))
    let quickSystem = QuickSystemService()
    let cleaning = CleaningService()
    let files = FileService()
    let finderMenu = FinderMenuPreferences(persist: !ProcessInfo.processInfo.arguments.contains("--smoke-test"))
    let loginItem = LoginItemController()
    let windows = WindowService()
    let awake = AwakeService()
    var showWindow: (() -> Void)?
    var showClipboard: ((Bool) -> Void)?
    var clipboardSelectionAction: ((String) -> Void)?
    var showGuide: (() -> Void)?
    var showShortcutSettings: ((ShortcutCategory?) -> Void)?
    var showToolbox: (() -> Void)?
    var performQuickAction: ((QuickAction) -> Void)?
    init() {
        captureEnabled = UserDefaults.standard.object(forKey: "capture.enabled") as? Bool ?? true
        filesEnabled = UserDefaults.standard.object(forKey: "files.enabled") as? Bool ?? true
        capture.onShow = { [weak self] in self?.navigate(.capture) }
    }
    func navigate(_ page: ToolPage) { self.page = page; showWindow?() }
    func start() { _ = AppFocus.shared; clipboard.start(); monitor.start() }
    func stop() { cleaning.stop(); quickSystem.removeDesktopCover(); clipboard.stop(); clipboard.flush(); monitor.stop(); awake.stop(); shortcuts.stop() }
    func takeScreenshot(ocr: Bool = false) {
        guard captureEnabled else { navigate(.settings); NoticeCenter.shared.success("请先启用截图模块"); return }
        capture.capture(ocr: ocr)
    }
}
