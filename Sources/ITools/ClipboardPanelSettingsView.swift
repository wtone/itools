import SwiftUI
import IToolsCore

struct ClipboardPanelSettingsView: View {
    @ObservedObject var preferences: ClipboardPanelPreferences
    let open: () -> Void
    var body: some View {
        SectionBlock(title: "剪贴板独立面板", detail: "文字、图片、文件和快捷短语") {
            HStack {
                Picker("排列", selection: $preferences.layout) { ForEach(ClipboardLayout.allCases, id: \.self) { Text($0.rawValue) } }.frame(width: 240)
                Spacer(); Button("打开面板", action: open)
            }
            HStack {
                Picker("数字键", selection: $preferences.numberModifier) { ForEach(ClipboardNumberModifier.allCases, id: \.self) { Text($0.rawValue) } }.frame(width: 240)
                Picker("数字 / 回车 / 双击", selection: $preferences.quickUse) { ForEach(ClipboardQuickUse.allCases, id: \.self) { Text($0.rawValue) } }.frame(width: 280)
            }
            Text("单击选择，按钮复制或粘贴；1–9 选择筛选结果的前九项。搜索时直接输入数字用于搜索，Esc 返回列表。直接粘贴需辅助功能权限，并返回呼出面板时的应用。").font(.system(size: 12)).foregroundColor(.secondary)
        }
    }
}
