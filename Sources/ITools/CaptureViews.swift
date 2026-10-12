import SwiftUI
import AppKit
import IToolsCore
import AVFoundation

struct CapturePage: View {
    @ObservedObject var capture: CaptureService
    @ObservedObject var recorder: RecordingService
    @State private var tab = 0
    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            Picker("工具", selection: $tab) { Text("截图与标注").tag(0); Text("录屏与录音").tag(1) }.pickerStyle(.segmented).frame(width: 340)
            if tab == 0 {
                HStack {
                    Button { capture.capture() } label: { Label("区域截图", systemImage: "viewfinder") }.buttonStyle(.borderedProminent)
                    Button("长截图") { capture.startLongCapture() }.help("在任意显示器框选滚动内容，选区透明，周围保留灰色蒙层")
                    Button("全屏") { capture.capture(fullScreen: true) }
                    Button("延时 3 秒") { capture.capture(delay: 3) }
                    Button("打开图片") { capture.openImage() }
                    Menu("更多") {
                        Button("手动滚动长截图") { capture.startLongCapture(automatic: false) }
                        Button("纵向拼接图片（按文件名排序）") { capture.stitch() }
                        Button("取色并复制 HEX") { capture.pickColor() }
                        Button("打开截图文件夹") {
                            NoticeCenter.shared.perform {
                                try FileManager.default.createDirectory(at: capture.folder, withIntermediateDirectories: true)
                                NSWorkspace.shared.open(capture.folder)
                            }
                        }
                    }.frame(width: 85)
                    if capture.busy { ProgressView().controlSize(.small) }
                }.disabled(capture.busy)
                Text("区域截图先框选，再拖动边缘调整大小、移动选区或直接标注；点击「完成并复制」保存到剪贴板。长截图可在任意显示器框选，蒙层持续保留。")
                    .font(.system(size: 11)).foregroundColor(.secondary)
                if capture.document.image != nil { EditorView(capture: capture, document: capture.document).padding(16).instrumentSurface() }
                else { EmptyState(icon: "viewfinder", title: "从一张截图开始", detail: "拖动选择区域，按空格选择窗口，Esc 取消。也可以打开已有图片进行标注。") }
                if !capture.recognizedText.isEmpty {
                    SectionBlock(title: "识别结果", detail: "文字与二维码内容") {
                        TextEditor(text: $capture.recognizedText).font(.system(size: 13)).frame(height: 120).border(Color.secondary.opacity(0.2))
                        HStack {
                            Button("复制文字") { copyText(capture.recognizedText) }
                            Button("在 Google 翻译中打开…") {
                                if Panels.confirm("将文字交给 Google 翻译？", detail: "此操作会在浏览器打开识别结果，文字将发送给 Google。", action: "打开翻译"),
                                   let url = LinkTools.translationURL(text: capture.recognizedText) { NSWorkspace.shared.open(url) }
                            }
                        }
                    }
                }
                if !capture.pickedColor.isEmpty { Text("最近取色：" + capture.pickedColor).font(.system(size: 12)).textSelection(.enabled) }
                if !capture.recent.isEmpty {
                    SectionBlock(title: "最近截图") {
                        GlassScrollView(.horizontal) {
                            HStack(spacing: 12) {
                                ForEach(Array(capture.recent.prefix(12)), id: \.self) { url in
                                    Button { capture.openImage(url) } label: {
                                        VStack {
                                            if let image = NSImage(contentsOf: url) { Image(nsImage: image).resizable().scaledToFit().frame(width: 116, height: 72) }
                                            Text(url.lastPathComponent).font(.system(size: 9)).lineLimit(1).frame(width: 116)
                                        }
                                    }.buttonStyle(.plain)
                                }
                            }
                        }
                    }
                }
            } else { RecordingPage(service: recorder) }
        }
    }
}
struct EditorView: View {
    @ObservedObject var capture: CaptureService
    @ObservedObject var document: AnnotationDocument
    @State private var zoom = 1.0
    @ViewBuilder private var historyControls: some View {
        if document.editingTextID == nil {
            Button("撤销") { document.undo() }.disabled(!document.canUndo).keyboardShortcut("z", modifiers: .command)
            Button("重做") { document.redo() }.disabled(!document.canRedo).keyboardShortcut("z", modifiers: [.command, .shift])
        } else {
            Button("撤销") { document.undo() }.disabled(!document.canUndo)
            Button("重做") { document.redo() }.disabled(!document.canRedo)
        }
    }
    private var tools: some View {
        ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(MarkTool.allCases) { tool in
                        Button { document.tool = tool; if tool != .select { document.select(nil) } } label: {
                            Group {
                                if tool == .text { Text("T").font(.system(size: 17, weight: .semibold, design: .serif)) }
                                else { Image(systemName: tool.icon) }
                            }.frame(width: 25, height: 23)
                                .foregroundColor(document.interactionTool == tool ? accent : .primary)
                        }.help(tool.rawValue).accessibilityLabel(tool.rawValue)
                    }
                }
            }
            .frame(height: 36)
    }
    private var styleControls: some View {
        HStack(spacing: 12) {
                ColorPicker("颜色", selection: $document.color).labelsHidden().frame(width: 36)
                    .onChange(of: document.color) { _ in document.applyStyle() }
                Slider(value: $document.lineWidth, in: 2...30, onEditingChanged: { editing in if !editing { document.applyStyle() } })
                    .frame(width: 95).help(document.selected?.tool == .text ? "文字大小" : "线条粗细")
                Text(document.selected?.tool.rawValue ?? "新标注").font(.system(size: 11)).foregroundColor(.secondary)
                Spacer()
                Button("删除") { document.deleteSelected() }.disabled(document.selected == nil)
                historyControls
            }.controlSize(.small)
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 11) {
            tools
            styleControls
            Text("悬停标注即可拖动，控制点调整大小；双击文字直接编辑，点击其他位置保存。⌘Z 撤销，⇧⌘Z 重做。")
                .font(.system(size: 11)).foregroundColor(.secondary)
            GeometryReader { geometry in
                ScrollView([.horizontal, .vertical]) {
                    AnnotationCanvas(document: document)
                        .frame(width: geometry.size.width * zoom,
                               height: max(335, (geometry.size.width - 28) * (document.image?.size.height ?? 1) / max(1, document.image?.size.width ?? 1)) * zoom)
                }
            }.frame(height: 335).cornerRadius(6)
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.secondary.opacity(0.18)))
            HStack {
                Text(document.editingTextID != nil ? "正在编辑文字 · 点击其他位置保存 · Esc 取消" : document.interactionTool.rawValue + "工具").font(.system(size: 11)).foregroundColor(.secondary)
                Slider(value: $zoom, in: 1...3).frame(width: 75).help("放大图片以精确标注")
                Text("\(Int(zoom * 100))%").font(.system(size: 10)).monospacedDigit()
                Button("适合宽度") { zoom = 1 }.controlSize(.small)
                Spacer()
            }
            HStack {
                Spacer()
                Button("OCR 识别") { capture.recognize() }.disabled(capture.busy)
                Button("贴图") { capture.pin() }
                Button("完成并复制") { capture.copyImage() }.buttonStyle(.borderedProminent).disabled(capture.busy)
                Button("导出…") { capture.exportImage() }
            }
        }
    }
}
struct RecordingPage: View {
    @ObservedObject var service: RecordingService
    var body: some View {
        VStack(alignment: .leading, spacing: 25) {
            HStack(spacing: 16) {
                Image(systemName: service.state == .recording ? "record.circle.fill" : "record.circle")
                    .font(.system(size: 42)).foregroundColor(service.isActive ? .red : accent)
                VStack(alignment: .leading, spacing: 5) {
                    Text(service.state.rawValue).font(.system(size: 21, weight: .medium))
                    Text(String(format: "%02d:%02d", Int(service.elapsed)/60, Int(service.elapsed)%60))
                        .font(.system(size: 15)).monospacedDigit().foregroundColor(.secondary)
                }
                Spacer()
                if service.isActive {
                    Button(service.state == .paused ? "继续" : "暂停") { service.pauseResume() }
                        .disabled(service.state != .recording && service.state != .paused)
                    Button("停止并保存") { service.stop() }.buttonStyle(.borderedProminent)
                        .disabled(service.state == .preparing || service.state == .stopping)
                }
            }.padding(20).instrumentSurface()
            VStack(alignment: .leading, spacing: 17) {
                HStack {
                    Picker("帧率", selection: $service.fps) { Text("15 fps · 省资源").tag(15); Text("30 fps · 日常").tag(30); Text("60 fps · 流畅").tag(60) }.frame(width: 255)
                    Toggle("显示鼠标", isOn: $service.showCursor)
                }
                Toggle("同时录制音频输入", isOn: $service.microphone)
                Picker("音频设备", selection: $service.deviceID) {
                    Text("系统默认输入").tag("")
                    ForEach(service.audioDevices, id: \.uniqueID) { device in Text(device.localizedName).tag(device.uniqueID) }
                }.frame(maxWidth: 440)
                Text("如需录制系统声音，可选择已安装的虚拟音频输入。此版本不会自动安装音频驱动。").font(.system(size: 12)).foregroundColor(.secondary)
                HStack {
                    Button("录制主屏幕…") { service.start() }.buttonStyle(.borderedProminent)
                    Button("选择录屏区域…") { service.selectRegion() }
                    Button("仅录音…") { service.start(audioOnly: true) }
                }
            }.disabled(service.isActive)
            Divider()
            SectionBlock(title: "视频处理", detail: "全部在本机处理") {
                HStack {
                    Button("视频转 GIF…") { service.convertGIF() }
                    Button("裁剪视频时段…") { service.exportVideo(trim: true) }
                    Button("压缩为 720p…") { service.exportVideo(trim: false) }
                    if service.converting { ProgressView().controlSize(.small) }
                }.disabled(service.converting)
                Text("GIF 支持 30 秒以内视频，输出 10 fps、最长边 720px。").font(.system(size: 11)).foregroundColor(.secondary)
            }
            if let url = service.latest {
                HStack {
                    Image(systemName: "checkmark.circle").foregroundColor(.green)
                    Text(url.lastPathComponent).lineLimit(1); Spacer()
                    Button("打开") { NSWorkspace.shared.open(url) }
                    Button("在访达显示") { NSWorkspace.shared.activateFileViewerSelecting([url]) }
                }
            }
        }
    }
}
