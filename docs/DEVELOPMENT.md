# 开发与后续扩展

## 添加原生能力

1. 在 IToolsCore/Utilities.swift 的 CapabilityCatalog 中定义能力、当前状态和真实限制。
2. 在 ITools 添加独立 ObservableObject 服务；由 AppModel 持有，明确 start/stop 生命周期。
3. 为长期运行服务使用后台串行队列与可取消计时器，发布 UI 状态回主队列；关闭模块应停止采样。
4. 在相应页面添加可操作入口，并让菜单栏/快捷键与页面遵循同一开关。新功能同时加入 ShortcutManager.swift 的 AppCommands.catalog 和 AppModel.performCommand；QuickAction、FinderActions、指标与布局会自动枚举进入清单。
5. 在权限入口解释具体用途，使用前检查，不在启动阶段批量索要权限。
6. 把可确定的纯逻辑放入 IToolsCore，以失败路径、数据保护和边界情况测试为主。
7. 对系统权限、设备和 GUI 的行为补充真实硬件验收，不用单元测试成功替代实机结论。

当前服务由宿主静态编译，不从外部目录加载任意动态库或脚本。接口边界是 Swift 模块与能力描述，不是承诺已实现第三方插件 ABI。

## 推荐后续实现顺序

1. **完善截图**：统一屏幕选择器、长图重叠检测、标注选择/移动与撤销栈、二维码白边、编辑器键盘操作。
2. **录制后端**：macOS 12.3+ 条件启用 ScreenCaptureKit；macOS 13+ 的音频捕获需额外版本检查，保留 12.0 AVCapture 路径。添加输入中断和设备热插拔验收。
3. **剪贴板**：SQLite + 独立 blob 文件，图片缩略图缓存，密码保护/加密导出；0.4.0 已实现可配置快捷键与独立横竖浮层。同步功能需冲突规则与用户主动授权。
4. **访达**：App Group + XPC 的已验证请求来源，减少跨进程确认，加入可配置目录范围、模板管理和收藏菜单。
5. **监控**：不同 Intel 代际传感器键枚举、更多 GPU 驱动适配、进程监控与告警，先只读；风扇写入/充电控制必须另建受签名约束的特权 helper 与恢复策略。
6. **分发**：稳定 Bundle ID 和 Developer ID、公证、签名更新机制、启动项与崩溃恢复。

## 录制实现

AVCaptureScreenInput 在 macOS 12 上仍可用，新版本推荐 ScreenCaptureKit。当前选择前者以形成从 12.0 起的一致 Intel 基线；不是声称它代表最新推荐技术。

参考：[Apple AVCaptureScreenInput](https://developer.apple.com/documentation/avfoundation/avcapturescreeninput)。

录制先写目标同目录的唯一临时文件，成功后再替换目标；失败保留部分产物便于找回。退出时如果录制尚未完成，会要求先停止保存。GIF、视频导出与录制互不共用输出文件。

## Finder Sync

主应用不采用 App Sandbox，Finder 扩展有独立沙盒。0.5.0 的实际文件操作在嵌入的 `Contents/Helpers/iTools Finder Actions.app` 中执行：与主程序共享可执行代码，但使用独立 bundle ID 和 `FinderActionDelegate` 入口，不实例化 AppModel / 主窗口 / 系统监控 / 剪贴板 / 快捷键。后台组件使用 LSUIElement 和 accessory activation policy，仅在需要参数或结果时显示专用窗口。

Finder 扩展通过 NSWorkspace 显式打开该组件并发送 `itools-finder-action://finder` 请求，此协议不注册到 Launch Services。冷启动先缓存事件，初始化后执行；热启动复用会话；队列在模态面板或异步文件任务期间不会重入 FileService。请求 UUID 防止重复投递。公开 `itools://finder` 仍进入主程序待确认状态。内部入口不面向网页，但并非本机调用方身份认证；同一用户的其他本机进程可以显式调用组件。删除、权限和复杂整理仍走各自的确认及校验。

0.4.1 的跨进程菜单以 `FinderMenuRequests` 保存 payload、NSMenuItem.tag 作为回调键，不依赖 representedObject。`FinderHostLocation` 按扩展所在包解析主程序，NSWorkspace 显式指定应用并处理完成回调。菜单重建使用递增编号和有限历史，防止旧点击错用新文件。

回归验证包含核心测试、GUI 中没有 representedObject 的菜单项转发，以及 `xcrun swift -module-cache-path "$PWD/.build/module-cache" scripts/test-finder-launch.swift /path/iTools.app /path/output`。启动测试要求先正常退出 iTools，只对合成文件发起待确认请求，验证冷启动、热启动、同进程复用与界面可见，不执行文件操作。该模式不启动剪贴板采样或全局快捷键。

直接操作集成测试：`xcrun swift -module-cache-path "$PWD/.build/module-cache" scripts/test-finder-direct.swift /path/iTools.app /path/new-output`。输出目录必须不存在，操作组件需未运行。测试通过真实 Launch Services 投递并实际新建、隐藏、移动、哈希、扫描和压缩临时文件，检查冷 / 热 / 排队请求、重名保留与未打开主程序。仅 Finder reveal 和 Terminal 调用用观察钩子替代，检查传入的准确目录，不读取或改写用户剪贴板。测试与正常数据目录隔离。后台组件闲置 30 分钟退出，剪切及密码仅存在该会话中。

主程序关闭文件模块后拒绝该入口。扩展是否显示由系统扩展开关管理；在主程序关闭模块不会替用户改动系统扩展开关。

参考：[Apple Finder Sync](https://developer.apple.com/documentation/FinderSync)。

## 只读 SMC

Intel AppleSMC user-client 的传感器协议不是稳定公开 API；SystemBridge 只执行 key-info/read 操作，不包含写方法。温度/风扇在某些机型、系统或权限条件下不可用。Apple Silicon 构建不尝试套用 Intel SMC 实现。

## 正式签名

设置 SIGN_IDENTITY 为开发者自己的 Developer ID Application 证书名称后运行构建脚本。脚本会先签扩展再签主应用，并启用 hardened runtime 与 timestamp。

~~~sh
SIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)" ./scripts/build.sh
ditto -c -k --keepParent dist/iTools.app dist/iTools.zip
xcrun notarytool submit dist/iTools.zip --keychain-profile YOUR_PROFILE --wait
xcrun stapler staple dist/iTools.app
~~~

这些命令只作为发布说明，项目并未持有证书、提交公证或上传产物。不要为让未签名应用运行而要求用户关闭 Gatekeeper/SIP。


## 0.6.0 系统联动

Finder 打开方式子菜单调用 macOS 12+ NSWorkspace.urlsForApplications(toOpen:)，多选通过 FinderApplications.common 取交集，按系统返回顺序展示。选定应用路径只允许随 open-with 动作传入内部协议；路径必须是 .app，后台再次校验 bundle 和可执行文件。system-default 表示按每个文件的默认应用分组交接，不修改系统文件关联。

NativeFileClipboard 写入标准 NSURL pasteboard objects，Finder 可消费；粘贴时读取当前 pasteboard，绝不回退旧 cutFiles。异步移动结束仅在 changeCount 未变时更新剩余项目，防止覆盖用户中途复制的新内容。GUI 自检使用独立 NSPasteboard，不读写用户剪贴板。主窗口的粘贴菜单不再被过期会话列表禁用。

NSWorkspace.recycle 负责废纸篓操作，后台组件不叠加自己的进度。直接压缩并移到废纸篓仍先完成校验和两次原件快照检查；原主窗口流程保留确认，Finder 明确动作直接继续。已用独立合成文件验证真实 NSWorkspace.recycle；因命令行无系统废纸篓读取权限，完整回归中的回收使用测试目录内的替代实现并按回调映射还原，不触碰用户既有废纸篓内容。

FileRenamePanel 合并名称 / 编码输入、实时预览及应用，FileDeletionConfirmation 合并不可逆操作说明及输入确认。系统无公开对应交互入口时才使用这些小窗口；不调用 Finder UI 自动化或请求辅助功能授权。
