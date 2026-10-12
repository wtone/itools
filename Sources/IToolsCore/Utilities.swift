import Foundation
import CoreGraphics

public enum WindowLayout: String, CaseIterable, Identifiable {
    case left, right, topLeft, topRight, bottomLeft, bottomRight, firstThird, middleThird, lastThird, maximize, center
    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .left: return "左半屏"; case .right: return "右半屏"
        case .topLeft: return "左上角"; case .topRight: return "右上角"
        case .bottomLeft: return "左下角"; case .bottomRight: return "右下角"
        case .firstThird: return "左侧三分之一"; case .middleThird: return "居中三分之一"
        case .lastThird: return "右侧三分之一"; case .maximize: return "最大化"; case .center: return "居中"
        }
    }
    // Input and output use top-left-origin Accessibility coordinates, including negative screen origins.
    public func frame(in screen: CGRect, gap: CGFloat = 8) -> CGRect {
        let unit: CGRect
        switch self {
        case .left: unit = CGRect(x: 0, y: 0, width: 0.5, height: 1)
        case .right: unit = CGRect(x: 0.5, y: 0, width: 0.5, height: 1)
        case .topLeft: unit = CGRect(x: 0, y: 0, width: 0.5, height: 0.5)
        case .topRight: unit = CGRect(x: 0.5, y: 0, width: 0.5, height: 0.5)
        case .bottomLeft: unit = CGRect(x: 0, y: 0.5, width: 0.5, height: 0.5)
        case .bottomRight: unit = CGRect(x: 0.5, y: 0.5, width: 0.5, height: 0.5)
        case .firstThird: unit = CGRect(x: 0, y: 0, width: 1.0/3, height: 1)
        case .middleThird: unit = CGRect(x: 1.0/3, y: 0, width: 1.0/3, height: 1)
        case .lastThird: unit = CGRect(x: 2.0/3, y: 0, width: 1.0/3, height: 1)
        case .maximize: unit = CGRect(x: 0, y: 0, width: 1, height: 1)
        case .center: unit = CGRect(x: 0.15, y: 0.1, width: 0.7, height: 0.8)
        }
        let rect = CGRect(x: screen.minX + unit.minX * screen.width, y: screen.minY + unit.minY * screen.height,
                          width: unit.width * screen.width, height: unit.height * screen.height)
        return rect.insetBy(dx: min(max(0, gap), rect.width/4), dy: min(max(0, gap), rect.height/4))
    }
}
public enum LinkTools {
    public static func clean(_ input: String) -> String {
        guard var url = URLComponents(string: input), ["http", "https"].contains(url.scheme?.lowercased() ?? ""), url.host != nil else { return input }
        let tracking: Set<String> = ["fbclid", "gclid", "dclid", "msclkid", "mc_cid", "mc_eid", "igshid"]
        let items = url.queryItems?.filter { !$0.name.lowercased().hasPrefix("utm_") && !tracking.contains($0.name.lowercased()) }
        guard items != url.queryItems else { return input }
        url.queryItems = (items?.isEmpty == true) ? nil : items
        return url.string ?? input
    }
    public static func translationURL(text: String) -> URL? {
        var c = URLComponents(string: "https://translate.google.com/")!
        c.queryItems = [.init(name: "sl", value: "auto"), .init(name: "tl", value: "zh-CN"), .init(name: "text", value: text), .init(name: "op", value: "translate")]
        return c.url
    }
}
public enum CapabilityState: String { case builtIn = "内置", planned = "待实现" }
public struct Capability: Identifiable {
    public var id: String
    public var title: String
    public var state: CapabilityState
    public var note: String
}
public enum CapabilityCatalog {
    public static let all: [Capability] = [
        .init(id: "capture", title: "截图、延时截图、标注、贴图、OCR、取色", state: .builtIn, note: "离线 OCR；标注支持画笔、矩形、箭头、文字和遮盖"),
        .init(id: "record", title: "录屏、麦克风录音、GIF 转换", state: .builtIn, note: "AVFoundation 兼容 Intel；系统声音使用虚拟音频设备"),
        .init(id: "stitch", title: "图片纵向拼接", state: .builtIn, note: "手动导入多张图，按顺序拼接；不是自动滚动捕获"),
        .init(id: "clipboard", title: "剪贴板历史、分组、收藏、快捷短语", state: .builtIn, note: "文本、富文本、图片和文件；本地保存"),
        .init(id: "finder", title: "访达右键、新建模板、文件整理", state: .builtIn, note: "Finder Sync 扩展需在系统设置启用"),
        .init(id: "monitor", title: "CPU、内存、GPU、磁盘、网络、电池、温度、风扇", state: .builtIn, note: "SMC 只读；CPU 温度按芯片适配，传感器随机型而异"),
        .init(id: "windows", title: "窗口布局、防休眠、便笺、链接清理", state: .builtIn, note: "窗口操作需辅助功能权限"),
        .init(id: "scroll", title: "自动滚动长截图、带壳截图、视频编辑时间线", state: .planned, note: "当前未提供；需独立实现截图捕获与视频编辑能力"),
        .init(id: "sync", title: "iCloud 同步、全局短语自动展开", state: .planned, note: "当前未提供；剪贴板历史与短语目前仅在本机使用"),
        .init(id: "mixer", title: "每应用音量、Dock 悬浮预览、鼠标增强", state: .planned, note: "需要独立的 Intel 兼容实现，当前未提供"),
        .init(id: "fan", title: "风扇转速控制、充电上限控制", state: .planned, note: "涉及机型适配与特权辅助进程；目前仅读取")
    ]
}
