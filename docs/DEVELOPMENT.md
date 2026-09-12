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

## 权限与粘贴（0.13.0）

使用 `PermissionCenter` 读取当前进程的真实授权，缺少权限时只打开一个独立说明窗口，不同时触发系统提示与主窗口错误弹框。打开系统设置时收起说明窗口，返回后刷新；不自动重试原操作。重新打开应用的失败原因直接显示在说明窗口中，避免二次弹框被遮挡。

所有模拟粘贴通过 `AppFocus.paste`：保留目标应用，等待实际激活与修饰键释放，超时或剪贴板变化则取消。准备内容的闭包只在发送前执行，队列成功提交后才移除。可确定的就绪判断放在 `IToolsCore/PasteReadiness.swift`；原生权限自检使用注入状态，不申请系统权限或向其他应用发送按键。焦点断言异步执行，以便主队列处理激活通知。

默认构建复用固定签名；首次开发时运行 `python3 scripts/setup-local-signing.py`，正式发行使用 `SIGN_IDENTITY`。不能再将每次改变身份的 ad-hoc 构建当作常规更新。证书存储、迁移与授权说明见 [PERMISSIONS.md](PERMISSIONS.md)。

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

## 统一快捷键面板（0.9.0）

`ShortcutDirectory` 在核心模块中把现有 `AppCommands.catalog` 按功能映射为 8 类和二级分组，同时提供跨分类、多词及已设置筛选。增加命令时应补充分类映射；未知 ID 会落到「面板与导航 / 其他功能」，不会丢失。目录只影响展示，不修改命令 ID、默认组合或 `shortcuts.v1` 存储格式。

`ShortcutGuideController` 管理唯一浮动面板和 `ShortcutWorkspaceState`。原指南及设置回调均打开该面板，设置回调可指定分类；全局指南按键支持再次按下收起。`ShortcutGuideView` 在分类卡片里同时展示说明、录入控件及执行 / 清除菜单，剪贴板交互卡片直接观察原有 `ClipboardPanelPreferences`。

`ShortcutEditor` 负责行内录入生命周期：开始后暂停注册并标记 `ShortcutManager.isEditing`；保存时先恢复注册以检测系统占用，但继续禁止命令分发，成功后才结束编辑。失败保留原绑定和编辑状态，取消 / 搜索 / 换类 / 失焦 / 关闭均恢复正常分发。AppKit `RecorderView` 接收物理按键，避免依赖文本输入内容。

原生自检 `ShortcutWorkspaceSmokeChecks` 放在既有焦点敏感检查之后：真实录入焦点、重复与系统占用、保存 / 清除 / 取消、搜索和失焦恢复、分类入口与再次呼出均通过真实控制器检查。GUI 自检的偏好模型禁用持久化，临时 Carbon 组合注销后恢复原绑定；浅色 / 深色 / 窄窗口 / 搜索 / 空结果 / 已设置 / 冲突状态通过自身 NSView 导出检查。

## 底部剪贴板浮框（0.10.0）

保留 `ClipboardLayout.horizontal` 的原存储值，展示名称改为「屏幕底部卡片」；未设置时默认横向，既有竖向选择不迁移。`ClipboardPanelRules.bottomPanelFrame` 按 AppKit 的底部原点和 `NSScreen.visibleFrame` 计算全宽、底边间距及受限高度，支持负坐标屏幕。`ClipboardPanelController` 在呼出时记录屏幕编号，显示配置变化时重算，横向模式关闭背景拖动；独立快捷键指南继续使用原浮动定位。

`ClipboardFloatingView` 为横向模式提供紧凑工具栏与滚动卡片，竖向模式保留列表。`ClipboardHistoryCard` 使用类型色、来源元数据、时间、内容与操作按钮；`ClipboardCardAssets` 缓存应用图标和通过 ImageIO 下采样的 600 像素缩略图，缓存限 80 张 / 32 MB。缩略图不替换 `ClipEntry.payload`，复制和粘贴逻辑不变。

背景使用独立 `NSVisualEffectView`，内容文字使用明确的浅深色调色板。图片由不参与 vibrancy 的 `NSView` 直接绘制 `CGImage`，预览不拦截卡片点击；原生自检对浅色与深色导出图执行 OCR，检查黑白样例中的 Monterey 文字仍存在。

## 工作台与仪表面板外观（0.12.0）

`InterfaceStyle` 集中浅深色调色板，`InstrumentSurface` 提供半透明圆角卡片，`InstrumentIcon`、`ActivityBadge` 和 `UsageTrack` 统一图标、状态与使用率。`workspaceSections` 环境值只在主窗口内容区启用，使 `SectionBlock` 的彩色分组标题位于卡片外，不改变快捷键中心和底部剪贴板的布局。炭灰透明侧栏覆盖在同一块背景玻璃上，主工作区继续跟随用户的外观设置。

`FrostedBackground` 使用 `.hudWindow` / `.behindWindow` / `.active` 的 `NSVisualEffectView`，上方只叠加低透明度淡色渐变。主窗口配置 `.fullSizeContentView`、透明隐藏标题栏、无分隔线、`isOpaque = false` 和透明背景；根视图忽略安全区，内容延伸到顶边。`WindowDragStrip` 只覆盖顶部 30 点空白，使用原生 `performDrag`；系统关闭、最小化和全屏按钮保留。`accessibilityReduceTransparency` 启用时改用实色背景及卡片，不持续执行自定义模糊计算。

`HistoryChart` 仍使用现有最多 60 个样本，按两分钟时间窗口靠右绘制真实数据，曲线下方增加透明面积；没有补齐假数据或新增采样计时器。菜单栏的指标卡片使用原生 Button 进入详情；网络 IP 继续独立复制。快捷操作保持原事件路由，以悬停、选中边框和状态点区分交互状态。

原生 GUI 自检包含深色设置 / 监控、最低宽度总览 / 设置，以及短高度菜单栏面板的渲染。`WindowGlassChecks` 检查内容覆盖整个窗口框、系统按钮仍可命中、玻璃材质存在，并导出完整窗口框。`NSView.cacheDisplay` 预览用于检查布局，不能单独证明窗口后方的实际透色。本机受控背景实验中，按窗口捕获的裸 `NSVisualEffectView` 和 iTools 均输出固定玻璃底色，故该导出方式不作为实时模糊的像素断言。未请求额外录屏权限或捕获其他应用。材质语义遵循 Apple 的 [NSVisualEffectView 说明](https://developer.apple.com/documentation/AppKit/NSVisualEffectView)。

0.12.1 的 `GlassScrollView` 保留 SwiftUI ScrollView 与 ScrollViewReader 行为，通过内容内的透明标记找到最近的 NSScrollView，关闭滚动视图及 clip view 的底色。`GlassScroller` 仅重写公开的 `drawKnobSlot`，声明兼容 overlay scroller；滑块绘制、淡入淡出、命中及拖动仍由 AppKit 处理。没有强制 overlay 样式或修改系统滚动条偏好，也不会遍历修改嵌套文本编辑器。主页面、快捷面板、快捷键分类、剪贴板、Finder 菜单设置及截图缩略图区共用该包装。

0.12.2 的顶部面板通过 `softIndicators` 启用浅色细滑块：只在公开的 `drawKnob` 中收窄绘制矩形，不改变 `rect(for: .knob)`、命中区域或跟踪事件；高对比度模式加深滑块。其他页面使用默认原生滑块。快捷操作根据用途使用彩色字形与浅色透明底座，开启时改为填色并增加勾选角标；悬停避免整块不透明白底。

## 登录自启动（0.8.0）

`LoginItemController` 使用可替换的 `LoginItemManaging` 后端管理异步注册与真实状态；`SystemLoginItem` 在 macOS 13+ 使用 SMAppService，在 12 使用兼容接口。`LoginItemSettingsView` 位于设置页顶部，默认只读查询，不在启动时自动注册。登录组件单独编译到 `Contents/Library/LoginItems/iTools Login.app`，只负责定位、启动外层应用并退出；主程序通过共享的 `LoginLaunch` 识别登录事件，保留后台运行及正常手动重新打开的区别。

完整行为、系统 API 依据与显式集成验证见 [LOGIN_ITEMS.md](LOGIN_ITEMS.md)。常规 GUI 自检只渲染预览；系统注册测试会短暂启用后注销，保留已有状态，不执行注销用户或重启电脑。

## Finder Sync

0.7.0 菜单布局由 `FinderMenuLayout` 按动作 ID 分为一级操作与剩余分组，`FinderMenuBuilder` 是扩展和原生验证共用的 NSMenu 构建器。选择只改变位置，仍通过 `FinderMenuRequests` 的整数 tag 发送相同直接请求；打开方式保留原生应用列表。无项目可处理时禁用叶子操作，空分组及空的总子菜单不生成。

布局存放于专用偏好域 `app.itools.mac.finder-menu` 的 `topLevelActionIDs`，不混入其他主程序设置。主程序写入并同步，扩展每次 `menu(for:)` 刷新后读取；扩展只声明这个域的 `com.apple.security.temporary-exception.shared-preference.read-only` 权限，不使用偏好文件的目录访问例外。依据：[Apple 共享偏好域只读 entitlement](https://developer.apple.com/library/archive/documentation/Miscellaneous/Reference/EntitlementKeyReference/Chapters/AppSandboxTemporaryExceptionEntitlements.html)。迁移至正式 App Group 之前，发行审核需核对所用 entitlement。

`python3 scripts/test-finder-menu-preferences.py` 编译带相同 entitlement 的测试读取器，实际验证其不能写工作区，然后在同一进程中检查初始读取、实时修改、清空选择以及新进程读取。只写入 UUID 测试键并在 finally 清理，不修改真实布局键。原生 GUI 自检复用菜单构建器，检查全部/混合/不选择、打开方式、tag 路由及目录参数，并导出设置面板浅色/深色图像；自检中的偏好模型禁用保存。

主应用不采用 App Sandbox，Finder 扩展有独立沙盒。0.5.0 的实际文件操作在嵌入的 `Contents/Helpers/iTools Finder Actions.app` 中执行：与主程序共享可执行代码，但使用独立 bundle ID 和 `FinderActionDelegate` 入口，不实例化 AppModel / 主窗口 / 系统监控 / 剪贴板 / 快捷键。后台组件使用 LSUIElement 和 accessory activation policy，仅在需要参数或结果时显示专用窗口。

0.6.1 起，Finder 扩展使用 `NSWorkspace.openApplication(at:configuration:)` 显式启动组件，通过标准 `aevt/oapp` 的私有 `iTrq` 参数携带内部请求列表。`itools-finder-action://finder` 仅作为数据编码，不注册 URL handler，也不能传给 `NSWorkspace.open(urls:withApplicationAt:)`：沙盒调用方会检查目标应用的 URL 类型声明，0.6.0 的做法会触发 `kLSAppDoesNotClaimTypeErr (-10820)`。`FinderLaunchEvent` 由扩展、组件和沙盒测试发送器共用。配置不激活窗口、不登记最近项目、不显示系统重复错误框，也不允许替换为其他安装路径的进程。

接收器必须在 `applicationWillFinishLaunching` 注册，过早注册会被 AppKit 的标准处理器覆盖。冷启动先缓存事件，初始化后执行；热启动复用会话；队列在模态面板或异步文件任务期间不会重入 FileService。请求 UUID 防止重复投递。公开 `itools://finder` 仍进入主程序待确认状态。内部入口不面向网页，但并非本机调用方身份认证；同一用户的其他本机进程可以显式调用组件。删除、权限和复杂整理仍走各自的确认及校验。

0.4.1 的跨进程菜单以 `FinderMenuRequests` 保存 payload、NSMenuItem.tag 作为回调键，不依赖 representedObject。`FinderHostLocation` 按扩展所在包解析主程序，NSWorkspace 显式指定应用并处理完成回调。菜单重建使用递增编号和有限历史，防止旧点击错用新文件。

回归验证包含核心测试、GUI 中没有 representedObject 的菜单项转发，以及 `xcrun swift -module-cache-path "$PWD/.build/module-cache" scripts/test-finder-launch.swift /path/iTools.app /path/output`。启动测试要求先正常退出 iTools，只对合成文件发起待确认请求，验证冷启动、热启动、同进程复用与界面可见，不执行文件操作。该模式不启动剪贴板采样或全局快捷键。

直接操作集成测试：`xcrun swift -module-cache-path "$PWD/.build/module-cache" scripts/test-finder-direct.swift /path/iTools.app /path/new-output`。输出目录必须不存在，操作组件需未运行。测试通过真实 Launch Services 投递并实际新建、隐藏、移动、哈希、扫描和压缩临时文件，检查冷 / 热 / 排队请求、重名保留与未打开主程序。仅 Finder reveal 和 Terminal 调用用观察钩子替代，检查传入的准确目录，不读取或改写用户剪贴板。测试与正常数据目录隔离。后台组件闲置 30 分钟退出，剪切及密码仅存在该会话中。

沙盒回归：先执行 `bash scripts/build-finder-sandbox-sender.sh`，再在上述命令末尾增加 `"$PWD/.build/FinderSandboxSender.app/Contents/MacOS/FinderSandboxSender"`。发送器使用 Finder 扩展的同一份沙盒 entitlement，并实际验证自己不能写测试目录；数据变更由后台组件完成。先从沙盒启动真实组件，验证第一次新建 TXT 及第二次重名操作，不启用钩子，Finder 会实际显示这两个合成文件。组件正常退出后，普通测试控制器启动隔离测试会话，再由沙盒发送器投递全部 29 项回归，保护用户剪贴板和废纸篓。NSWorkspace 会忽略沙盒调用方的 launch arguments，实测环境变量也未传入，不能通过它们启用首次启动测试钩子。新输出目录、后台组件完全退出后再跑一次，可验证不同进程的首次请求。普通进程通过不再代替沙盒验证。

接口依据：Xcode SDK `NSWorkspace.h` 的 OpenConfiguration.appleEvent、arguments、promptsUserIfNeeded、allowsRunningApplicationSubstitution；[Apple 的 URL 接收声明要求](https://developer.apple.com/documentation/appkit/nsapplicationdelegate/application(_:open:))。

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

## 记录鼠标操作（0.13.1）

`clipboardRecordActions` 以双击优先的互斥手势实现单击复制、双击粘贴，并提供系统悬停提示与命名辅助功能操作。主窗口历史和短语共用同一手势；可点击内容与复制 / 粘贴 / 删除 / 菜单控件分开，避免父级手势同时触发。主窗口记录预览不再启用文字选择，防止双击被选词截获。

浮动面板的 `clickRecord` 同步选中项、退出搜索焦点；鼠标单击通过 `keepOpen` 保持面板和目标应用记录，成功后显示已复制。双击继续使用既有权限检测和目标应用粘贴流程。数字、回车和显式按钮保持原有偏好及关闭行为；不修改旧用户偏好值。

## 剪贴板毛玻璃与按需搜索（0.13.5）

- ClipboardFloatingView 的横竖布局共用 ClipboardPanelBackdrop / FrostedBackground(tinted: false)，浮层窗口和原生滚动视图保持透明；GlassScrollView 两方向开启 softIndicators。系统减少透明度设置仍由共用材质组件处理。
- ClipboardPanelPalette 统一分类按钮和记录标题颜色；亮色标题使用深色文字，卡片正文独立适配浅深色。图片继续由禁用 vibrancy 的原生视图绘制，避免颜色随背景变化。
- ClipboardPanelController 打开时重置为记录选择状态并清除初始编辑焦点；仅点击搜索框或 Command-F 才进入搜索。ClipboardSearchField 通过原生 NSTextField 明确取得 first responder，避免非激活浮层中仅改变 SwiftUI FocusState 而实际未进入编辑的问题；更新绑定时保护 marked text。上 / 下键离开搜索进入记录选择，Esc 的返回层级和组合键保留。
- ShortcutSmokeChecks.verifyClipboardSearch 异步验证打开后数字直接复制对应记录、Command-F 使实际搜索框成为 first responder，在该编辑器中投递数字键、验证筛选和不误选记录；覆盖横向、竖向和短语、输入法确认保护、离开搜索后数字选择，并检查原生材质与淡色滚动条。
- 使用 `--smoke-test --clipboard-focus-test` 可单独运行这组真实窗口检查，待启动事务结束后开始；完整 `--smoke-test` 仍包含同一组检查。仅使用模拟记录和选择回调，不发送跨应用粘贴。

### 滚轮与悬停筛选（0.13.6）

- 仅快捷剪贴板横向列表启用 `GlassScrollView(horizontalWheel: true)`。局部事件监听限制到同一可见窗口、同一滚动区域；退出视图后移除监听。竖向页面保持默认滚动，原生横向手势及 Shift 滚轮不转换。
- `HorizontalScrollWheel` 使用系统已处理方向和加速的 scrollingDeltaY，普通滚轮按原生 horizontalLineScroll 换算，精确滚动按像素处理；通过 NSClipView 的 constrainBoundsRect 限制左右边缘，更新并显示原生淡色滑块。不修改全局滚轮偏好或安装全局事件监听。
- 类型按钮的点击与 onHover 进入回调共用 `ClipboardPanelState.selectFilter`；保留查询文字和自定义分组，切换类型 / 收藏后选中首条结果。同一分类不重复重置；按钮固定尺寸，防止选中字体变化移动悬停区域。
- 原生剪贴板专项检查同时覆盖横向移动、反向、边缘限制、精确滚动距离、横向手势不改写，以及三种面板的数字键与搜索焦点。

## 多显示器浮框定位（0.13.3）

- QuickPanelController 使用非激活 StatusQuickPanel，点击时从全局鼠标位置解析 MenuPanelScreen，保存 MenuPanelPlacement；不再把浮框持续附着到 NSStatusBarButton，也不调用 NSApp.activate。按钮窗口可能只描述主屏的菜单栏副本，只在它包含实际点击位置时使用其锚点。
- 面板尺寸和位置只在打开时写入；Combine 的实时指标刷新只更新内容。显示配置 / Space 改变时收起，避免逐帧重新定位。MenuBarMonitor 为普通指标和网速预留固定宽度，异常长读数在槽位内缩放。
- 原生 NSPanel 保留焦点、菜单交互、外部点击关闭与 Esc 关闭；StatusPanelChrome 绘制玻璃圆角和指向箭头。菜单跟踪期间不因临时焦点变化关闭。
- MenuPanelPlacementTests 覆盖镜像按钮位于主屏、副屏负坐标 / 上下布局、边缘约束、小屏及键盘入口。通过 `--smoke-test --quick-panel-screen-test` 可在所有实际连接的显示器上打开本应用面板并反复更新内容，检查屏幕、frame、key 状态与主窗口位置，再运行完整 GUI 回归。

## 深色卡片、布局图形与菜单栏管理（0.13.2）

深色 `InterfaceStyle.surface` 和 `raised` 改为较亮的中灰紫色，分区卡片叠加轻微上缘高光，提高边缘和文字层次；浅色值及原生毛玻璃保持原样，减少透明度时仍提供实色卡片。菜单栏预览复用半透明控件底色，避免出现一块不协调的深色实底。

`WindowLayoutButton` 统一 12 个等宽图文按钮。`WindowLayoutGlyph` 将已有 `WindowLayout.frame(in:gap:)` 在小窗格中缩放显示，使用与实际窗口一致的左上原点；还原操作使用返回箭头。图形不参与辅助功能朗读，按钮保留明确名称。未改动窗口控制坐标、授权或快捷键。

`MenuBarSettingsView` 整体移入 `MonitorPage` 的首个区块，继续绑定 `AppModel.menuBar`，与原来的状态栏开关使用同一偏好对象；不迁移或重置任何配置。设置页不再重复展示该区块。GUI 预览追加深色窗口布局及窄屏系统状态/窗口布局页面。


## 深色分区描边与指南入口（0.13.7）

`InstrumentSurface` 读取 `workspaceSections` 环境值；主窗口深色页面统一省略装饰描边，沿用此前提亮的半透明填充。浅色与其他浮层样式不变，输入控件、选中状态和图形标识继续使用各自的样式。

`QuickPanelView` 将指南按钮放在滚动区域外的固定底栏，使用完整文字与键盘图标，并沿用 `showShortcutSettings` 回调；关闭信息框后打开统一指南。

通过 `--smoke-test --interface-preview` 可独立导出主窗口及信息框预览，无需运行剪贴板焦点、快捷键录入等完整回归。记录为内存中的合成样例，不启动剪贴板记录服务；预览新增深色剪贴板、文件和截图页面。
