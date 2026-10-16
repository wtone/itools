import Foundation

// Shared verbatim by the host and Finder extension to keep routing in sync.
public struct FinderAction {
    public let id: String
    public let title: String
    public let directory: Bool
    public let requiresPaths: Bool
    public init(_ id: String, _ title: String, directory: Bool = false, requiresPaths: Bool = true) {
        self.id = id; self.title = title; self.directory = directory; self.requiresPaths = requiresPaths
    }
}
public struct FinderActionGroup {
    public let title: String
    public let icon: String
    public let actions: [FinderAction]
    public init(title: String, icon: String, actions: [FinderAction]) {
        self.title = title; self.icon = icon; self.actions = actions
    }
}
public enum FinderActions {
    public static let visibilityActionID = "toggle-hidden-files"
    public static let groups: [FinderActionGroup] = [
        .init(title: "新建文件", icon: "doc.badge.plus", actions: [
            .init("new-txt", "文本文件 · TXT", directory: true), .init("new-md", "Markdown", directory: true),
            .init("new-rtf", "富文本 · RTF", directory: true), .init("new-json", "JSON", directory: true),
            .init("new-html", "HTML", directory: true), .init("new-csv", "CSV", directory: true),
            .init("new-xml", "XML", directory: true), .init("new-template", "从自定义模板新建…", directory: true)]),
        .init(title: "移动、复制与整理", icon: "folder", actions: [
            .init("move", "移动文件到…"), .init("copy", "复制文件到…"),
            .init("sync-move", "移动至同步文件夹…"), .init("cut", "剪切"), .init("paste", "粘贴移动到此处", directory: true),
            .init("copy-name", "拷贝文件（夹）名称"), .init("copy-path", "拷贝路径"),
            .init("named-folder", "使用文件名新建文件夹"), .init("dissolve", "解散文件夹"),
            .init("favorite", "添加到常用目录"), .init("favorites", "打开常用目录…"),
            .init("rename", "重命名…")]),
        .init(title: "图标、分享与打开", icon: "square.and.arrow.up", actions: [
            .init("icon", "设置文件（夹）图标…"), .init("icon-reset", "恢复默认图标"),
            .init("alias", "发送快捷方式到桌面"), .init("airdrop", "隔空投送…"),
            .init("terminal", "进入终端"), .init("open-with", "选择打开方式…")]),
        .init(title: "显示、权限与清理", icon: "eye", actions: [
            .init(visibilityActionID, "显示/不显示隐藏文件", requiresPaths: false),
            .init("show", "取消隐藏已选文件"), .init("hide", "隐藏已选文件"),
            .init("extension", "隐藏 / 显示文件扩展名"),
            .init("repair", "修复乱码文件名…"), .init("writable", "授予选择的文件写入权限"),
            .init("scan", "扫描磁盘 / 文件夹"), .init("hash", "计算 SHA-256"),
            .init("trash", "移到废纸篓"), .init("delete", "彻底删除…")]),
        .init(title: "压缩与加密", icon: "archivebox", actions: [
            .init("fast-7z", "快速打包为 7z"), .init("fast-zip", "快速打包为 ZIP"),
            .init("fast-7z-trash", "快速打包为 7z 并移到废纸篓"), .init("fast-zip-trash", "快速打包为 ZIP 并移到废纸篓"),
            .init("zip", "压缩为 ZIP"), .init("zip-trash", "压缩为 ZIP 并移到废纸篓"),
            .init("encrypt-7z", "加密压缩为 7z…"), .init("encrypt-zip", "加密压缩为 ZIP…"),
            .init("archive", "自定义压缩…"), .init("password", "设置加密密码…"),
            .init("archive-test", "校验压缩包…"), .init("fastzip", "用 FastZip 打开")])
    ]
    public static let all = groups.flatMap(\.actions)
    public static func action(_ id: String) -> FinderAction? { all.first { $0.id == id } }
}
