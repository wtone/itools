import SwiftUI
import IToolsCore

struct ClipboardPanelSettingsView: View {
    @ObservedObject var preferences: ClipboardPanelPreferences
    let open: () -> Void
    var body: some View {
        SectionBlock(title: "剪贴板独立面板", detail: "文字、图片、文件和快捷短语") {
            HStack {
                Picker("排列", selection: $preferences.layout) { ForEach(ClipboardLayout.allCases, id: \.self) { Text($0.title).tag($0) } }.frame(width: 260)
                Spacer(); Button("打开面板", action: open)
            }
            HStack {
                Picker("数字键", selection: $preferences.numberModifier) { ForEach(ClipboardNumberModifier.allCases, id: \.self) { Text($0.rawValue) } }.frame(width: 240)
                Picker("数字 / 回车", selection: $preferences.quickUse) { ForEach(ClipboardQuickUse.allCases, id: \.self) { Text($0.rawValue) } }.frame(width: 280)
            }
            Text("打开后可用 1–9 操作前九项记录；点击搜索框或按 ⌘F 搜索，搜索时数字作为输入内容。按 ↓ 或 Esc 返回列表后可继续用数字键。单击记录复制，双击记录粘贴，单击复制后面板保持打开。直接粘贴需辅助功能权限，并返回呼出面板时的应用。").font(.system(size: 12)).foregroundColor(.secondary)
            Text("横向模式下，鼠标滚轮可直接左右浏览记录；悬停在类型按钮上即可筛选，点击同样有效。").font(.system(size: 12)).foregroundColor(.secondary)
        }
    }
}
