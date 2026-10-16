import SwiftUI
import AppKit
import IToolsCore
import FinderSync
import AVFoundation
import CoreImage

struct FilesPage: View {
    @ObservedObject var service: FileService
    @ObservedObject var menuPreferences: FinderMenuPreferences
    var body: some View {
        VStack(alignment: .leading, spacing: 23) {
            HStack {
                Button { service.choose() } label: { Label("选择文件或文件夹…", systemImage: "folder") }.buttonStyle(ToolButtonStyle()).disabled(service.working)
                Spacer()
                FinderMenuSettingsButton(preferences: menuPreferences)
                Button("启用访达扩展…") { FIFinderSyncController.showExtensionManagementInterface() }
                if service.working { ProgressView().controlSize(.small) }
            }
            if service.selection.isEmpty {
                EmptyState(icon: "folder.badge.gearshape", title: "让文件少绕路", detail: "选择文件后使用下方工具。启用 iTools Finder 扩展后，也能从访达右键菜单进入。")
            } else {
                VStack(alignment: .leading, spacing: 7) {
                    ForEach(Array(service.selection.prefix(12)), id: \.self) { url in
                        HStack(spacing: 9) {
                            Image(nsImage: NSWorkspace.shared.icon(forFile: url.path)).resizable().frame(width: 20, height: 20)
                            Text(url.path).font(.system(size: 12)).lineLimit(1).truncationMode(.middle).textSelection(.enabled)
                        }
                    }
                    if service.selection.count > 12 { Text("以及另外 \(service.selection.count-12) 项").font(.system(size: 11)).foregroundColor(.secondary) }
                }.padding(14).frame(maxWidth: .infinity, alignment: .leading).instrumentSurface(radius: 12)
            }
            if service.pendingFinderAction != nil {
                HStack {
                    Text("访达请求：\(service.pendingActionTitle)").font(.system(size: 12)); Spacer()
                    Button("确认并执行") { service.executePending() }.disabled(service.working)
                    Button("取消") { service.pendingFinderAction = nil }
                }
            }
            SectionBlock(title: "iTools 访达工具", detail: "可将常用操作放到 Finder 一级右键菜单，其余保留在子菜单") {
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], alignment: .leading, spacing: 12) {
                    ForEach(FinderActions.groups, id: \.title) { group in
                        Menu {
                            ForEach(group.actions, id: \.id) { action in
                                Button(action.title) { service.performAction(action.id) }
                                    .disabled(action.requiresPaths && service.selection.isEmpty)
                            }
                        } label: { Label(group.title, systemImage: group.icon) }
                        .disabled(service.selection.isEmpty && group.actions.allSatisfy(\.requiresPaths))
                    }
                    Button("选择文件后扫描大小") { service.scanDisk() }
                        .disabled(service.selection.isEmpty)
                }.disabled(service.working)
                Text("压缩包括 ZIP / 7z、AES 加密和完整性校验。密码仅保留至退出应用。")
                    .font(.system(size: 11)).foregroundColor(.secondary)
            }
            if !service.scanSummary.isEmpty {
                SectionBlock(title: "磁盘扫描", detail: "包含隐藏文件，不跟随符号链接；按逻辑大小排序，硬链接逐项计数") {
                    HStack {
                        Text(service.scanSummary).font(.system(size: 12)).textSelection(.enabled)
                        Spacer()
                        if service.scanCancellation != nil { Button("停止扫描") { service.scanCancellation?.cancel() } }
                    }
                    ForEach(Array(service.scanEntries.prefix(100))) { entry in
                        HStack {
                            Button(entry.url.lastPathComponent) { NSWorkspace.shared.activateFileViewerSelecting([entry.url]) }
                                .lineLimit(1).truncationMode(.middle)
                            Spacer()
                            Text("\(entry.files) 个文件").foregroundColor(.secondary)
                            Text(bytes(entry.bytes)).monospacedDigit().frame(width: 90, alignment: .trailing)
                        }.font(.system(size: 12))
                    }
                    if service.scanEntries.count > 100 { Text("显示最大的 100 项；统计包含全部项目。").font(.caption) }
                }
            }
            Divider()
            SectionBlock(title: "新建文件", detail: "选择文件夹后新建，或在对话框中选择位置") {
                HStack {
                    ForEach(["txt", "md", "json", "html", "rtf", "csv", "xml"], id: \.self) { ext in Button(ext.uppercased()) { service.createFile(ext: ext) } }
                    Spacer(); Button("导入模板…") { service.importTemplate() }
                }
                if !service.templates.isEmpty {
                    ForEach(service.templates, id: \.self) { template in
                        Button { service.createFile(template: template) } label: { Label(template.lastPathComponent, systemImage: "doc.badge.plus") }
                    }
                }
                Text("Word、Excel、PPT、Pages 等格式可导入真实空白文档作为模板，保留原格式结构。").font(.system(size: 11)).foregroundColor(.secondary)
            }
            SectionBlock(title: "常用文件夹") {
                HStack { Button("添加文件夹…") { service.addFavorite() }; Spacer() }
                ForEach(service.favorites, id: \.self) { folder in
                    HStack {
                        Button(folder.lastPathComponent) { NSWorkspace.shared.open(folder) }
                        Text(folder.path).lineLimit(1).truncationMode(.middle).font(.system(size: 11)).foregroundColor(.secondary)
                        Spacer()
                        Button("设为目标") { service.selection = [folder] }
                        Button { service.removeFavorite(folder) } label: { Image(systemName: "minus.circle") }
                    }
                }
            }
            if !service.result.isEmpty {
                Text(service.result).font(.system(size: 12)).textSelection(.enabled).padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading).instrumentSurface(radius: 10)
            }
        }
    }
}
struct MonitorPage: View {
    @ObservedObject var service: MonitorService
    @ObservedObject var menuPreferences: MenuBarPreferences
    var restoreMenuPosition: (() -> Void)? = nil
    private var snapshot: MonitorSnapshot { service.snapshot }
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            MenuBarSettingsView(preferences: menuPreferences, monitor: service, restorePosition: restoreMenuPosition)
            HStack {
                Label(service.enabled ? "正在观察这台 Mac" : "监控已暂停，显示最后一次读数", systemImage: service.enabled ? "circle.fill" : "pause.circle").font(.system(size: 12)).foregroundColor(service.enabled ? .green : .secondary)
                Spacer(); Toggle("状态监控", isOn: $service.enabled).toggleStyle(.switch).controlSize(.small)
            }
            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 15) {
                    HStack {
                        MetricView(title: "CPU", value: snapshot.cpu.map { String(format: "%.1f%%", $0) } ?? "采样中", detail: "所有核心的平均负载")
                        InstrumentIcon(name: "cpu", size: 42)
                    }
                    HistoryChart(values: service.cpuHistory, color: accent).frame(height: 105)
                }.padding(20).instrumentSurface(tint: accent)
                VStack(alignment: .leading, spacing: 15) {
                    HStack {
                        MetricView(title: "内存", value: String(format: "%.1f%%", snapshot.memoryPercent), detail: "\(bytes(snapshot.memoryUsed)) / \(bytes(snapshot.memoryTotal))")
                        InstrumentIcon(name: "memorychip", color: InterfaceStyle.cyan, size: 42)
                    }
                    HistoryChart(values: service.memoryHistory, color: InterfaceStyle.cyan).frame(height: 105)
                }.padding(20).instrumentSurface(tint: InterfaceStyle.cyan)
            }
            HStack { Text("最近 2 分钟").font(.system(size: 10)).foregroundColor(.secondary); Spacer(); Text("每 2 秒采样，传感器每 10 秒读取").font(.system(size: 10)).foregroundColor(.secondary) }
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 25) {
                    InstrumentIcon(name: "rectangle.3.offgrid", color: InterfaceStyle.violet, size: 42)
                    MetricView(title: "GPU 使用率", value: MetricFormatting.percent(snapshot.gpu),
                               detail: snapshot.gpuDevices.isEmpty ? "当前驱动未提供读数" : snapshot.gpuDevices.joined(separator: " / "))
                    HistoryChart(values: service.gpuHistory, color: InterfaceStyle.violet).frame(width: 200, height: 65)
                }
                Text("多显卡的菜单栏读数取当前最高使用率；不支持的驱动显示「—」。").font(.system(size: 11)).foregroundColor(.secondary)
            }.padding(20).instrumentSurface(tint: InterfaceStyle.violet)
            SectionBlock(title: "硬件与存储") {
                HStack(spacing: 25) {
                    MetricView(title: "CPU 温度", value: snapshot.cpuTemperature.map { String(format: "%.1f°C", $0) } ?? "不可用", detail: snapshot.cpuTemperature == nil ? "暂未读到温度" : snapshot.cpuTemperatureIsCoreMaximum ? "核心最高温度 · SMC 只读" : "SMC · 只读")
                    MetricView(title: "风扇", value: snapshot.fan.map { String(format: "%.0f", $0) } ?? "不可用", detail: "RPM" + (snapshot.fan2.map { String(format: " · 第二风扇 %.0f", $0) } ?? ""))
                    MetricView(title: "磁盘可用", value: bytes(snapshot.diskFree), detail: "总容量 " + bytes(snapshot.diskTotal))
                }
            }
            SectionBlock(title: "网络与交换空间") {
                HStack(spacing: 25) {
                    MetricView(title: "下载速率", value: MetricFormatting.rate(snapshot.networkAvailable ? snapshot.download : nil), detail: "物理网络接口汇总")
                    MetricView(title: "上传速率", value: MetricFormatting.rate(snapshot.networkAvailable ? snapshot.upload : nil), detail: "排除回环与 VPN 重复计数")
                    MetricView(title: "交换空间", value: bytes(snapshot.swap), detail: "系统实际使用")
                }
            }
            SectionBlock(title: "电池与运行时间") {
                HStack(spacing: 25) {
                    MetricView(title: snapshot.charging ? "电池 · 正在充电" : "电池电量", value: snapshot.battery.map { String(format: "%.0f%%", $0) } ?? "无电池", detail: snapshot.batteryTemperature.map { String(format: "温度 %.1f°C", $0) } ?? "温度不可用")
                    MetricView(title: "电池健康", value: snapshot.batteryHealth.map { String(format: "%.0f%%", $0) } ?? "不可用", detail: snapshot.batteryCycles.map { "循环 \($0) 次" } ?? "循环次数不可用")
                    MetricView(title: "开机时间", value: "\(Int(snapshot.uptime)/3600) 小时", detail: "\(Int(snapshot.uptime)/86400) 天 \(Int(snapshot.uptime)%86400/3600) 小时")
                }
                Text("温度与风扇传感器因机型而异。内存统计包括活跃、系统固定占用和压缩内存，扣除可清除页；可能与活动监视器不同。")
                    .font(.system(size: 11)).foregroundColor(.secondary)
                Button("打开活动监视器") { NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/Utilities/Activity Monitor.app")) }
            }
        }
    }
}
struct HistoryChart: View {
    let values: [Double]
    let color: Color
    var body: some View {
        GeometryReader { proxy in
            let samples = Array(values.suffix(60))
            let points = samples.enumerated().map { index, value in
                CGPoint(x: Double(60 - samples.count + index) / 59 * proxy.size.width,
                        y: (1 - min(100, max(0, value.isFinite ? value : 0)) / 100) * proxy.size.height)
            }
            ZStack {
                Path { p in
                    for level in [0.0, 0.5, 1.0] {
                        let y = proxy.size.height * level
                        p.move(to: CGPoint(x: 0, y: y)); p.addLine(to: CGPoint(x: proxy.size.width, y: y))
                    }
                }.stroke(InterfaceStyle.border.opacity(0.65), style: StrokeStyle(lineWidth: 0.6, dash: [3, 4]))
                if let first = points.first, let last = points.last {
                    Path { p in
                        p.move(to: CGPoint(x: first.x, y: proxy.size.height))
                        for point in points { p.addLine(to: point) }
                        p.addLine(to: CGPoint(x: last.x, y: proxy.size.height)); p.closeSubpath()
                    }.fill(LinearGradient(colors: [color.opacity(0.25), color.opacity(0.025)], startPoint: .top, endPoint: .bottom))
                    Path { p in p.addLines(points) }.stroke(color, style: StrokeStyle(lineWidth: 1.8, lineCap: .round, lineJoin: .round))
                    Circle().fill(color).frame(width: 4, height: 4).position(last)
                }
            }
        }.accessibilityLabel("最近两分钟使用率曲线")
    }
}
struct UtilitiesPage: View {
    @ObservedObject var model: AppModel
    @ObservedObject var awake: AwakeService
    @State private var minutes = 30
    @State private var displayAwake = false
    @AppStorage("scratchpad") private var note = ""
    @State private var link = ""
    @State private var qrText = ""
    @State private var qrImage: NSImage?
    var body: some View {
        VStack(alignment: .leading, spacing: 26) {
            SectionBlock(title: "窗口布局", detail: "作用于打开 iTools 之前的应用窗口") {
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                    ForEach(WindowLayout.allCases) { layout in
                        WindowLayoutButton(layout: layout) { model.windows.apply(layout) }
                    }
                    WindowLayoutButton(layout: nil) { model.windows.restore() }
                }
                HStack { Text("窗口工具需要辅助功能权限。").font(.system(size: 11)).foregroundColor(.secondary); Button("查看 / 设置窗口快捷键") { model.showShortcutSettings?(.windows) } }
            }
            SectionBlock(title: "保持唤醒", detail: awake.active ? "运行中" : "未开启") {
                HStack {
                    Picker("时长", selection: $minutes) { Text("30 分钟").tag(30); Text("1 小时").tag(60); Text("2 小时").tag(120); Text("直到关闭").tag(0) }.frame(width: 180)
                    Toggle("同时保持屏幕亮起", isOn: $displayAwake)
                    Spacer()
                    Button(awake.active ? "停止防休眠" : "开始防休眠") { if awake.active { awake.stop() } else { awake.start(minutes: minutes, keepDisplay: displayAwake) } }
                }
                if let until = awake.until { Text("结束时间：\(until.formatted(date: .omitted, time: .shortened))").font(.system(size: 11)).foregroundColor(.secondary) }
                Text("保持系统处于唤醒状态；合盖、关机或主动睡眠仍由 macOS 决定。").font(.system(size: 11)).foregroundColor(.secondary)
            }
            SectionBlock(title: "临时便笺", detail: "自动保存到本机") {
                TextEditor(text: $note).font(.system(size: 13)).frame(height: 135).border(Color.secondary.opacity(0.2))
                HStack {
                    Button("复制内容") { copyText(note) }
                    Button("导出…") { if let url = Panels.save(name: "便笺.txt", types: ["txt"]) { NoticeCenter.shared.perform { try note.write(to: url, atomically: true, encoding: .utf8) } } }
                    Spacer()
                    Button("清空…") { if Panels.confirm("清空便笺？", detail: "请先复制或导出需要的内容。", action: "清空") { note = "" } }
                }
            }.id("utility.note")
            SectionBlock(title: "清理链接") {
                HStack {
                    TextField("粘贴包含跟踪参数的网页链接", text: $link).textFieldStyle(.roundedBorder)
                    Button("清理并复制") { link = LinkTools.clean(link); copyText(link) }.disabled(link.isEmpty)
                }
                Text("只删除 utm_*、fbclid 等常见跟踪参数，保留业务参数。").font(.system(size: 11)).foregroundColor(.secondary)
            }.id("utility.link")
            SectionBlock(title: "文字转二维码", detail: "本地生成") {
                HStack {
                    TextField("文字或链接", text: $qrText).textFieldStyle(.roundedBorder).onChange(of: qrText) { _ in qrImage = nil }
                    Button("生成") {
                        NoticeCenter.shared.perform { qrImage = try QRCodeRenderer.image(text: qrText) }
                    }.disabled(qrText.isEmpty || qrText.utf8.count > 2000)
                }
                Text("\(qrText.utf8.count) / 2000 字节 · 修改内容后请重新生成")
                    .font(.system(size: 11)).foregroundColor(qrText.utf8.count > 2000 ? .red : .secondary)
                if let image = qrImage {
                    HStack {
                        Image(nsImage: image).interpolation(.none).resizable().scaledToFit().frame(width: 170, height: 170)
                        Button("复制二维码") {
                            guard let data = image.png else { NoticeCenter.shared.report(UserFacingError("二维码编码失败。")); return }
                            NSPasteboard.general.clearContents()
                            if NSPasteboard.general.setData(data, forType: .png) { NoticeCenter.shared.success("已复制二维码") }
                            else { NoticeCenter.shared.report(UserFacingError("未能复制二维码，请重试。")) }
                        }
                        Button("保存…") { if let url = Panels.save(name: "二维码.png", types: ["png"]) { NoticeCenter.shared.perform { guard let data = image.png else { throw UserFacingError("二维码编码失败。") }; try data.write(to: url, options: .atomic); NoticeCenter.shared.success("二维码已保存") } } }
                    }
                }
            }.id("utility.qr")
        }
    }
}
struct SettingsPage: View {
    @ObservedObject var model: AppModel
    @ObservedObject var clipboard: ClipboardService
    @ObservedObject var monitor: MonitorService
    @State private var permissionRefresh = 0
    @ObservedObject private var permissions = PermissionCenter.shared
    @AppStorage("appearance") private var appearance = "system"
    var body: some View {
        VStack(alignment: .leading, spacing: 25) {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 330), spacing: 24)], alignment: .leading, spacing: 24) {
            LoginItemSettingsView(controller: model.loginItem, minimumHeight: 205)
            SectionBlock(title: "快捷键与操作指南", detail: "分类查看、直接编辑；在其他应用中也可呼出", minimumHeight: 205) {
                HStack {
                    Button("打开快捷键与操作指南…") { model.showShortcutSettings?(nil) }
                    Spacer()
                }
                Text("常用操作已预设按键，其余功能可按需分配。重复或无法注册的组合会提示；修改立即保存。").font(.system(size: 12)).foregroundColor(.secondary)
            }
            }
            ClipboardPanelSettingsView(preferences: model.clipboardPanel, open: { model.showClipboard?(false) })
            SectionBlock(title: "Finder 右键菜单", detail: "勾选常用操作显示在一级，其他操作保留在 iTools 子菜单") {
                HStack {
                    FinderMenuSettingsButton(preferences: model.finderMenu)
                    Spacer()
                    FinderMenuSelectionSummary(preferences: model.finderMenu)
                }
            }
            SectionBlock(title: "顶部快捷面板", detail: "点击工具箱或指标打开，右键保留文字菜单") {
                DisclosureGroup("自定义快捷入口与排序") { QuickPanelSettingsView(preferences: model.quickPanel).padding(.top, 12) }
            }
            SectionBlock(title: "功能模块") {
                Toggle("截图与录制", isOn: $model.captureEnabled).disabled(model.recorder.isActive || model.capture.busy)
                Toggle("剪贴板历史", isOn: $clipboard.enabled)
                Toggle("访达与文件工具", isOn: $model.filesEnabled)
                Toggle("系统状态监控", isOn: $monitor.enabled)
                Text("关闭剪贴板或监控会停止其采样计时器。截图和文件工具只在执行操作时工作。").font(.system(size: 11)).foregroundColor(.secondary)
            }
            SectionBlock(title: "系统权限") {
                PermissionRow(title: "屏幕录制", detail: "用于截图、屏幕文字识别和录屏；部分变更需重新打开应用", allowed: permissions.screen) { permissions.show(.screen) }
                PermissionRow(title: "辅助功能", detail: "窗口控制；状态来自当前运行的 iTools", allowed: permissions.accessibility) { permissions.show(.accessibility) }
                PermissionRow(title: "粘贴与模拟按键", detail: "等待目标应用就绪后发送按键，与辅助功能一起检查", allowed: permissions.accessibility && permissions.eventPosting) { permissions.show(.accessibility, operation: "直接粘贴") }
                PermissionRow(title: "麦克风", detail: "仅在选择录音时请求", allowed: permissions.microphone == .authorized) { permissions.show(.microphone) }
                HStack { Text("自动化").font(.system(size: 13, weight: .medium)); Text("切换外观、Dock 或 Finder 操作时分别申请").font(.system(size: 11)).foregroundColor(.secondary); Spacer(); Button("查看授权说明") { permissions.show(.automation) } }
                PermissionRow(title: "访达扩展", detail: "将 iTools 操作加入访达右键菜单", allowed: FIFinderSyncController.isExtensionEnabled) { FIFinderSyncController.showExtensionManagementInterface() }
                Button("刷新权限状态") { permissions.refresh(); permissionRefresh += 1 }
            }.id(permissionRefresh).onAppear { permissions.refresh() }
            SectionBlock(title: "剪贴板保留规则") {
                HStack {
                    Picker("最多保存", selection: $clipboard.maxCount) { Text("100 项").tag(100); Text("300 项").tag(300); Text("1000 项").tag(1000) }.frame(width: 220)
                    Picker("保留时间", selection: $clipboard.retentionDays) { Text("7 天").tag(7); Text("30 天").tag(30); Text("90 天").tag(90) }.frame(width: 220)
                }
                Text("不记录这些应用（Bundle ID，以英文逗号分隔）").font(.system(size: 12))
                TextField("排除应用", text: $clipboard.excludedApps).textFieldStyle(.roundedBorder)
                HStack {
                    Button("保存规则") { clipboard.saveSettings(); NoticeCenter.shared.success("剪贴板规则已保存") }
                    Spacer()
                    Button("打开数据文件夹") {
                        NoticeCenter.shared.perform {
                            try FileManager.default.createDirectory(at: Storage.root, withIntermediateDirectories: true)
                            NSWorkspace.shared.open(Storage.root)
                        }
                    }
                }
                Text("数据保存在 ~/Library/Application Support/ITools。历史文件为本地 JSON，未额外加密；导出备份也可能含私人内容。").font(.system(size: 11)).foregroundColor(.secondary)
            }
            SectionBlock(title: "外观") {
                Picker("主题", selection: $appearance) { Text("跟随系统").tag("system"); Text("浅色").tag("light"); Text("深色").tag("dark") }
                    .pickerStyle(.segmented).frame(width: 330)
                    .onChange(of: appearance) { value in NSApp.appearance = value == "system" ? nil : NSAppearance(named: value == "dark" ? .darkAqua : .aqua) }
            }
            SectionBlock(title: "能力与实现情况") {
                ForEach(CapabilityCatalog.all) { capability in
                    HStack(alignment: .top, spacing: 12) {
                        Text(capability.state.rawValue).font(.system(size: 10, weight: .medium))
                            .foregroundColor(capability.state == .builtIn ? .green : .secondary).frame(width: 44)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(capability.title).font(.system(size: 12, weight: .medium))
                            Text(capability.note).font(.system(size: 11)).foregroundColor(.secondary)
                        }
                        Spacer()
                    }.padding(.vertical, 4)
                }
            }
        }
    }
}
struct PermissionRow: View {
    let title: String; let detail: String; let allowed: Bool; let action: () -> Void
    var body: some View {
        HStack {
            Image(systemName: allowed ? "checkmark.circle.fill" : "circle").foregroundColor(allowed ? .green : .secondary)
            VStack(alignment: .leading, spacing: 4) { Text(title).font(.system(size: 13, weight: .medium)); Text(detail).font(.system(size: 11)).foregroundColor(.secondary) }
            Spacer()
            Button(allowed ? "管理权限" : "前往设置", action: action)
        }.padding(.vertical, 5)
    }
}
