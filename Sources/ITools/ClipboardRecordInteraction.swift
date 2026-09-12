import SwiftUI

enum ClipboardRecordInteraction {
    static let hint = "单击复制 · 双击粘贴到之前的应用"
}

extension View {
    /// Resolve a double click before committing a single click. In particular, a short
    /// phrase containing {{clipboard}} must not be expanded once for each half of a double click.
    func clipboardRecordActions(copy: @escaping () -> Void, paste: @escaping () -> Void) -> some View {
        contentShape(Rectangle())
            .gesture(TapGesture(count: 2).exclusively(before: TapGesture(count: 1)).onEnded { result in
                switch result {
                case .first: paste()
                case .second: copy()
                }
            })
            .help(ClipboardRecordInteraction.hint)
            .accessibilityAction(named: Text("复制记录"), copy)
            .accessibilityAction(named: Text("粘贴记录"), paste)
    }
}
