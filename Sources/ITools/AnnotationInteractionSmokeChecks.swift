import AppKit

enum AnnotationInteractionSmokeChecks {
    static func run(destination: URL) throws {
        let image = NSImage(size: NSSize(width: 640, height: 400))
        image.lockFocus(); NSColor.white.setFill(); CGRect(x: 0, y: 0, width: 640, height: 400).fill(); image.unlockFocus()
        let document = AnnotationDocument(image: image), canvas = CanvasView(document: AnnotationDocument())
        canvas.update(document: document)
        let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 680, height: 460), styleMask: .borderless, backing: .buffered, defer: true)
        window.isReleasedWhenClosed = false; window.contentView = canvas; canvas.frame = CGRect(x: 0, y: 0, width: 680, height: 460)
        defer { window.close() }
        func mouse(_ type: NSEvent.EventType, at point: CGPoint, clicks: Int = 1) -> NSEvent {
            let rect = canvas.imageRect, size = document.image!.size
            let location = CGPoint(x: rect.minX+point.x/size.width*rect.width, y: rect.minY+point.y/size.height*rect.height)
            return NSEvent.mouseEvent(with: type, location: location, modifierFlags: [], timestamp: 0, windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: clicks, pressure: 1)!
        }
        func editor() throws -> InlineAnnotationTextView {
            guard let editor = canvas.subviews.compactMap({ $0 as? InlineAnnotationTextView }).first,
                  window.firstResponder === editor else { throw UserFacingError("Smoke: text editing did not focus an editor inside the image") }
            return editor
        }
        for tool in [MarkTool.line, .rectangle, .ellipse, .arrow, .text, .pen, .fill] {
            let mark = Annotation(tool: tool, points: tool == .text ? [CGPoint(x: 100, y: 170)] : [CGPoint(x: 100, y: 170), CGPoint(x: 240, y: 260)], color: .systemBlue, width: 5, text: "Hover text")
            document.marks = [mark]; document.select(nil); document.tool = .pen
            let center = CGPoint(x: mark.bounds.midX, y: mark.bounds.midY)
            canvas.mouseMoved(with: mouse(.mouseMoved, at: center))
            guard document.hoveredID == mark.id, document.interactionTool == .select, document.tool == .pen else { throw UserFacingError("Smoke: hover did not automatically offer movement for \(tool.rawValue)") }
            canvas.mouseDown(with: mouse(.leftMouseDown, at: center))
            canvas.mouseDragged(with: mouse(.leftMouseDragged, at: CGPoint(x: center.x+10, y: center.y+7)))
            canvas.mouseUp(with: mouse(.leftMouseUp, at: CGPoint(x: center.x+10, y: center.y+7)))
            guard abs(document.marks[0].points[0].x-mark.points[0].x-10) < 0.01 else { throw UserFacingError("Smoke: hover drag did not move \(tool.rawValue) while pen tool was selected") }
            document.undo()
            let corner = CGPoint(x: mark.bounds.maxX, y: mark.bounds.maxY)
            canvas.mouseMoved(with: mouse(.mouseMoved, at: corner))
            canvas.mouseDown(with: mouse(.leftMouseDown, at: corner))
            canvas.mouseDragged(with: mouse(.leftMouseDragged, at: CGPoint(x: corner.x+32, y: corner.y+18)))
            canvas.mouseUp(with: mouse(.leftMouseUp, at: CGPoint(x: corner.x+32, y: corner.y+18)))
            guard document.marks[0].bounds.width > mark.bounds.width else { throw UserFacingError("Smoke: hover handle did not resize \(tool.rawValue)") }
            document.undo()
            canvas.mouseMoved(with: mouse(.mouseMoved, at: CGPoint(x: 550, y: 350)))
            guard document.hoveredID == nil, document.interactionTool == .pen else { throw UserFacingError("Smoke: hovering empty canvas lost the previous drawing tool") }
        }
        let wideArrow = Annotation(tool: .arrow, points: [CGPoint(x: 100, y: 170), CGPoint(x: 240, y: 170)], color: .systemBlue, width: 12)
        document.marks = [wideArrow]; document.select(nil); document.tool = .rectangle
        canvas.mouseMoved(with: mouse(.mouseMoved, at: wideArrow.arrowHead[0]))
        guard document.hoveredID == wideArrow.id else { throw UserFacingError("Smoke: hovering the arrowhead missed its visible wings") }
        print("PASS: hover offers handles and direct dragging/resizing for lines, boxes, circles, arrows, text, pen and fill without switching tools; empty canvas resumes drawing")

        document.marks = []; document.select(nil); document.tool = .text
        canvas.mouseDown(with: mouse(.leftMouseDown, at: CGPoint(x: 85, y: 280)))
        let inline = try editor()
        inline.insertText("First line\n图片内直接编辑", replacementRange: NSRange(location: 0, length: 0))
        guard document.selected?.text == "First line\n图片内直接编辑", document.selected!.bounds.height > 40,
              abs(document.selected!.bounds.maxY-280) < 0.01 else { throw UserFacingError("Smoke: inline multiline editing did not preserve the text's top anchor") }
        window.makeFirstResponder(canvas)
        guard document.editingTextID == nil, !canvas.subviews.contains(where: { $0 is InlineAnnotationTextView }) else { throw UserFacingError("Smoke: losing focus did not commit and close inline editor") }
        let originalText = document.selected!
        document.undo(); guard document.marks.isEmpty else { throw UserFacingError("Smoke: inline text creation generated more than one undo operation") }
        document.redo(); guard document.marks[0].text == originalText.text else { throw UserFacingError("Smoke: inline creation redo failed") }

        document.tool = .rectangle; document.select(nil)
        let center = CGPoint(x: originalText.bounds.midX, y: originalText.bounds.midY)
        canvas.mouseDown(with: mouse(.leftMouseDown, at: center, clicks: 2))
        let editing = try editor()
        editing.insertText("Inline edited", replacementRange: NSRange(location: 0, length: editing.string.utf16.count))
        window.makeFirstResponder(canvas)
        guard document.marks[0].text == "Inline edited", document.marks[0].id == originalText.id else { throw UserFacingError("Smoke: double-click did not edit the existing text in place") }
        document.undo(); guard document.marks[0].text == originalText.text else { throw UserFacingError("Smoke: inline text edit undo failed") }
        document.redo(); guard document.marks[0].text == "Inline edited" else { throw UserFacingError("Smoke: inline text edit redo failed") }
        print("PASS: T creates a native multiline editor inside the image; double-click edits existing text; losing focus commits one undoable change")

        let textBounds = document.marks[0].bounds
        canvas.mouseDown(with: mouse(.leftMouseDown, at: CGPoint(x: textBounds.minX+4, y: textBounds.maxY-10), clicks: 2))
        let caretEditor = try editor()
        guard caretEditor.selectedRange().location < caretEditor.string.utf16.count else { throw UserFacingError("Smoke: double-click always placed the inline caret at the end of the text") }
        window.makeFirstResponder(canvas)

        func startExistingEdit() throws -> InlineAnnotationTextView {
            let b = document.marks[0].bounds
            canvas.mouseDown(with: mouse(.leftMouseDown, at: CGPoint(x: b.midX, y: b.midY), clicks: 2))
            return try editor()
        }
        let exporting = try startExistingEdit()
        exporting.insertText("Export latest draft", replacementRange: NSRange(location: 0, length: exporting.string.utf16.count))
        guard let rendered = document.render(), document.editingTextID == nil, document.marks[0].text == "Export latest draft" else { throw UserFacingError("Smoke: export lost the active inline draft") }
        canvas.update(document: document)
        try rendered.png!.write(to: destination.appendingPathComponent("inline-text-export.png"))
        document.undo(); guard document.marks[0].text == "Inline edited" else { throw UserFacingError("Smoke: exporting the inline draft broke undo") }

        let clearing = try startExistingEdit()
        clearing.insertText("", replacementRange: NSRange(location: 0, length: clearing.string.utf16.count))
        window.makeFirstResponder(canvas)
        guard document.marks.isEmpty else { throw UserFacingError("Smoke: empty text left an invisible annotation") }
        document.undo(); guard document.marks[0].text == "Inline edited" else { throw UserFacingError("Smoke: deleting text cannot be undone") }
        let cancelling = try startExistingEdit()
        cancelling.insertText("Cancelled draft", replacementRange: NSRange(location: 0, length: cancelling.string.utf16.count))
        let escape = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: window.windowNumber, context: nil, characters: "\u{1b}", charactersIgnoringModifiers: "\u{1b}", isARepeat: false, keyCode: 53)!
        cancelling.keyDown(with: escape)
        guard document.marks[0].text == "Inline edited", document.editingTextID == nil else { throw UserFacingError("Smoke: Esc did not restore original text") }
        print("PASS: exporting commits the latest inline draft; deleting all text is undoable; Esc cancels edits without replacing the object")

        let preview = try startExistingEdit()
        preview.insertText("图片内编辑\nInline editing", replacementRange: NSRange(location: 0, length: preview.string.utf16.count))
        for (appearance, name) in [(NSAppearance.Name.aqua, "inline-editor-light"), (.darkAqua, "inline-editor-dark")] {
            window.appearance = NSAppearance(named: appearance); canvas.layoutSubtreeIfNeeded()
            guard let rep = canvas.bitmapImageRepForCachingDisplay(in: canvas.bounds) else { throw UserFacingError("Smoke: inline preview allocation failed") }
            canvas.cacheDisplay(in: canvas.bounds, to: rep)
            try rep.representation(using: .png, properties: [:])!.write(to: destination.appendingPathComponent(name + ".png"))
        }
        window.makeFirstResponder(canvas)
        print("PASS: native inline editor renders directly over the image in light and dark appearances; no modal or system pasteboard used")
    }
}
