import AppKit
import SwiftUI

/// A real AppKit responder is reliable inside a nonactivating macOS 12+ clipboard panel.
struct ClipboardSearchField: NSViewRepresentable {
    @Binding var text: String
    @Binding var focused: Bool
    let placeholder: String
    var fontSize: CGFloat = 11

    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeNSView(context: Context) -> Field {
        let field = Field()
        field.isBezeled = false; field.isBordered = false; field.drawsBackground = false
        field.isEditable = true; field.isSelectable = true; field.focusRingType = .none
        field.usesSingleLineMode = true; field.lineBreakMode = .byClipping
        field.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        field.setAccessibilityIdentifier("itools.clipboard.search")
        field.setAccessibilityLabel("搜索剪贴板")
        field.delegate = context.coordinator
        return field
    }
    func updateNSView(_ field: Field, context: Context) {
        context.coordinator.parent = self
        field.font = .systemFont(ofSize: fontSize)
        field.textColor = .labelColor; field.placeholderString = placeholder
        if field.stringValue != text && (field.currentEditor() as? NSTextView)?.hasMarkedText() != true {
            field.stringValue = text
        }
        field.wantsFocus = focused
        field.applyFocus()
    }
    final class Field: NSTextField {
        var wantsFocus = false
        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            DispatchQueue.main.async { [weak self] in self?.applyFocus() }
        }
        func applyFocus() {
            guard let window = window, window.isKeyWindow else { return }
            if wantsFocus {
                if let editor = currentEditor(), window.firstResponder === editor { return }
                window.makeFirstResponder(self)
            }
        }
    }
    final class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: ClipboardSearchField
        init(_ parent: ClipboardSearchField) { self.parent = parent }
        func controlTextDidChange(_ notification: Notification) {
            guard let field = notification.object as? NSTextField else { return }
            if parent.text != field.stringValue { parent.text = field.stringValue }
        }
        func controlTextDidBeginEditing(_ notification: Notification) {
            if !parent.focused { parent.focused = true }
        }
        func controlTextDidEndEditing(_ notification: Notification) {
            guard let field = notification.object as? Field else { return }
            // AppKit can deliver an old editor's end notification while the same field is regaining focus.
            DispatchQueue.main.async { [weak self, weak field] in
                guard let self = self, let field = field, field.window?.isKeyWindow == true,
                      field.currentEditor() == nil, self.parent.focused else { return }
                self.parent.focused = false
            }
        }
    }
}
