# 验证记录

验证日期：2026-09-09；0.6.1 启动修复补充于 2026-09-10。开发及运行环境：**Intel x86_64、macOS 13.7.8 (22H730)、Swift 5.9.2、Xcode macOS SDK 14.2**。

## 已完成

| 检查 | 结果 |
| --- | --- |
| Swift Debug 编译 | 通过 |
| Swift Release 编译及 app 组装 | 通过 |
| 主程序 / Finder 扩展架构 | x86_64 原生可执行文件 |
| Mach-O 最低系统版本 | 12.0 |
| Info.plist / entitlement 格式 | 通过 plutil 校验 |
| 主程序与嵌入扩展 ad-hoc 签名 | 通过 codesign --verify --deep --strict |
| 核心测试 | 51 项通过，0 失败 |
| 8 个页面 + 深色总览 | 应用自身 NSView 渲染导出成功；人工查看主要页面 |
| 标注渲染 | 合成图片 640×340 导出尺寸保持不变 |
| 不透明遮盖 | 导出像素检查为黑色 |
| 裁剪 | 输出 600×220，尺寸检查通过 |
| 离线 OCR | Vision 识别出合成图片中的 Intel / Monterey |
| URL 请求保护 | 公开 itools:// 链接只进入待确认状态；0.5.0 内部 Finder 通道见下方 |
| 系统指标 | 在本机读取到实际 CPU、16 GB 内存、磁盘/网络、温度和双风扇读数 |

原始测试日志位于构建时的 .build / 临时日志目录，自检图片位于 .build/smoke-final。图中剪贴板与截图编辑内容是合成测试样例，未读取用户剪贴板，也没有截取桌面或其他应用。

程序自检首先验证像素、OCR 和裁剪，再切换页面并缓存各自的 NSView。它可以发现崩溃、缺少视图和部分布局问题，**不能代替鼠标/键盘交互或系统权限流程的端到端测试**。

## 原有核心测试覆盖

- 文本/二进制/Unicode 存储往返。
- 历史指纹、表示顺序无关性、去重时保留收藏/分组/身份。
- 收藏保留、过期淘汰、条数与容量配额、短语变量替换。
- 文件名路径逃逸拒绝、新建/复制/移动不覆盖既有数据、目录不能移动到自身之内。
- 包含 shell 特殊字符的文件名按普通字符串处理。
- 重命名交换、同名冲突预检、暂存失败回滚。
- SHA-256 标准向量与自动避让名称。
- 负坐标显示器、多种布局边界。
- URL 跟踪参数移除、业务参数保留、翻译文本转义。

## 尚需用户授权/额外设备的验收

以下功能已有源码实现，但本轮没有获得对应系统权限或设备条件来完成全部交互验收：

- **macOS 12 实机运行**：当前仅在 macOS 13.7.8 运行；12.0 兼容性来自部署目标、可用性编译检查及旧版 API 选择，尚非 12 系统上的实测结论。
- 屏幕录制授权后的真实截图选择、取消、Retina/外接屏边界、延时行为。
- 屏幕/区域/麦克风录制、暂停/继续、磁盘满、音频设备拔插后的恢复与播放。
- 实际视频的 GIF、压缩与时间段导出。
- 辅助功能授权后的全局粘贴、跨屏窗口移动和拒绝调整窗口。
- Finder 扩展在系统设置启用后的右键菜单与 URL 完整交接；已完成编译、打包、签名及所有宿主路由自检；真实 Finder 菜单点击仍待手动验收。
- 真实剪贴板类型、第三方密码应用保密标记、文件别名及粘贴目标的兼容性。
- 四款商业应用各自的安装、付费功能、文件交接和 macOS 12 兼容版本。
- 其他 Intel 代际的 SMC 键、电池健康统计，以及系统睡眠/唤醒。
- Apple Silicon / universal 构建、Developer ID、公证、公开分发。

## 手动验收步骤

1. 把 app 放到固定位置，首次启动确认窗口、菜单栏、模块启停和重启后的设置。
2. 开启剪贴板，复制测试文本/图片/多文件；搜索、收藏、分组、重启、导出/导入；关闭后再复制，确认不再新增。
3. 允许屏幕录制，截图并测试 Esc 取消、Space 选窗口、3 秒延时、裁剪、遮盖导出、OCR 与贴图。
4. 录制一段 5 秒测试视频，暂停后继续，停止保存，确认音画与时长；再测试区域与音频设备。
5. 允许辅助功能，在可丢弃文档的输入框检查粘贴；在普通窗口测试三种全局布局快捷键并还原。
6. 在临时测试文件夹内启用右键扩展，检查新建/复制/移动/重命名/隐藏/哈希/ZIP/废纸篓。验证同名文件不被覆盖。
7. 开启监控，和系统工具比较趋势；关闭后观察采样停止；温度未知时应明确显示不可用。
8. 开启 30 分钟防休眠后立即停止，确认会话释放；退出应用应释放所有采样器、快捷键和防休眠断言。

## 0.1.1 菜单栏更新验证

- 新增 6 项测试：旧用户默认值、全部关闭后的保存恢复、独立开关、未知配置兼容、数值/网速/磁盘口径、GPU 驱动字段与缺失读数。
- 真实 NSStatusItem 集成自检：同时创建七项、只保留内存/网速、全部关闭并移除、恢复七项；均通过。
- 暂停读数检查：七种指标均显示「—」，不继续显示旧数值。
- GPU 实机采样：当前 Intel 与 AMD 显卡均返回使用率（一次采样为 1% / 4%，不是固定值）。
- 已查看设置页面渲染和菜单栏两行字体渲染。自检设置修改不写入用户菜单栏偏好。
- 独立读数复用每 2 秒的既有采样计时器，无外部 ioreg 进程、无 Metal 设备创建、无额外驱动安装。


## 0.2.0 访达菜单更新验证

- 45 项核心测试全部通过。新增 17 项覆盖同名文件夹、目录解散冲突/预览变化、隐藏文件与符号链接、权限位保留、危险删除边界、乱码编码、扫描取消、文件变更快照，以及 ZIP/7z 单项/跨目录/隐藏文件往返、AES 密码正确/错误、密码字符边界、压缩失败清理。
- 新增跨目录测试发现 7-Zip 默认会去掉每个输入文件的父路径，已以明确的相对路径及保留路径选项修复；不同目录的同名文件不再冲突。
- 本机 GUI 自检通过所有 Finder 路由的待确认接收、未知路由拒绝、扩展名属性、自定义图标设置/恢复、真正 Finder 替身的写入/解析、应用内 7-Zip 加密压缩。
- 页面渲染发现文件选择按钮文字及硬编码版本号问题，已修复。自检不读取用户剪贴板或桌面图像。
- 主程序、Finder 扩展及 7-Zip 均验证为 x86_64，Mach-O minimum macOS 12.0；实际运行系统仍是 13.7.8。
- 测试日志：.build/file-tests.log、.build/finder-release-build.log、.build/finder-smoke.log；图片：docs/screenshots/finder-tools.png。
- 自动化未实际向 AirDrop 接收者发送文件，未删除用户文件，也未修改其他软件的扩展启用状态。

- Finder 扩展注册复核：pluginkit 显示「+ app.itools.mac.finder(0.2.0)」，即用户启用状态；其他原有扩展保持原状态。Finder 内最终显示和点击交互仍需要用户实际查看。


## 0.3.0 快捷面板

- 51 项核心测试通过。新增 6 项验证配置增减、恢复、排序、显式空配置、未知/重复 ID、测试模式不写用户配置，以及清洁模式 Esc 长按/松开/自动重复/一分钟超时。
- 原生 NSPopover 打开/关闭自检通过，显式限定宽度与屏幕可用高度，防止 SwiftUI 内容测量导致面板尺寸异常。
- 自己的 NSView 导出浅色、深色、编辑列表和清洁提示图；已人工检查默认 15 项操作及编辑界面的标签、排序按钮。
- System Events 深色/Dock/菜单栏脚本与 Finder 废纸篓脚本完成编译检查，没有执行；实际使用时仍受系统自动化权限控制。
- 清洁模式未在用户设备上启动全局按键拦截；测试了退出策略，实际事件拦截及特殊系统快捷键行为仍需辅助功能权限后的交互验收。
- 清洁生命周期包含超时、长按 Esc、鼠标退出、应用失焦、用户会话锁定、系统休眠、显示器变化和事件 tap 被停用。
- 防休眠时限计时器加入 common run-loop mode，防止打开文字菜单时推迟释放；退出清理 idle/display 两种断言。
- 日志 .build/quick-tests.log、.build/quick-build.log、.build/quick-smoke.log；预览 docs/screenshots/quick-panel.png、quick-panel-dark.png。

- 最终包实机自检：短暂创建并释放系统/亮屏两种防休眠断言通过，5 个系统应用 bundle ID 全部解析成功，未修改持久电源配置。

## 0.4.0 全局快捷键与独立剪贴板

- 63 项核心测试通过。新增 12 项覆盖保留按键、组合冲突、清除 / 修改 / 恢复持久化、升级时用户组合优先、未知 ID 保留、测试模式不写偏好、面板布局 / 数字行为保存、搜索与输入法不误触、数字 / 小键盘 / 修饰键、筛选、选择边界及负坐标显示器。
- 最终包自检确认 149 项功能 ID 唯一，所有 FinderActions 和 QuickAction 均有设置条目；13 组默认按键无内部重复且满足验证规则。
- 真实 NSPanel 可成为 key window；NSEvent 验证方向选择、数字选择、纯文本复制路由、仅复制偏好、中文组词时回车不粘贴、搜索输入数字保留、Esc 关闭及重复呼出切换。选择动作通过注入回调记录，未向外部应用粘贴。
- 使用独立 NSPasteboard 验证文本、RTF、多表示、纯文本移除格式、PNG 原数据及文件 URL 往返；确认通用剪贴板 changeCount 未被测试改变。
- 真实 Carbon 快捷键注册、应用事件分发、更换绑定和注销均通过。修正了初版自检在主队列闭包里阻塞等待该队列的异步回调问题，最终采用异步续接检查；没有向系统发送模拟全局按键。
- 自己的视图导出并检查：横向、竖向、深色、短语、快捷键指南、设置，以及原有 8 个主页面。常用剪贴板入口优先展示，移除多余的分段控件标签。
- 最终日志：.build/shortcuts-tests.log、.build/shortcuts-build.log、.build/shortcuts-smoke.log；导出：.build/smoke-shortcuts-final；文档预览：docs/screenshots/clipboard-*.png、shortcut-*.png。
- 主程序 / Finder 扩展 / 7-Zip 的目标仍为 x86_64、minimum macOS 12.0；实际运行 macOS 13.7.8。尚未完成 macOS 12 实机、其他应用辅助功能粘贴、各种原生全屏 / 多屏及与第三方全局热键冲突的人工验收。

## 0.4.1 Finder 点击与安装位置

- 69 项核心测试通过。新增 6 项覆盖仅保留菜单 tag 时的请求恢复、旧菜单点击不会指向新文件、请求表过期、中文/空格/参数字符编码、非法/过长请求拒绝、移动/重命名后的包含应用定位、失效旧路径回退与错误应用拒绝。
- 原生 GUI 自检构造没有 representedObject 的 NSMenuItem，将其 tag 解析回原请求，再确认主程序正确保存待处理 action 与原路径；没有直接执行文件操作。既有截图、剪贴板、监控和快捷键自检全部通过。
- 启动测试用 NSWorkspace 指定实际 .app 路径，验证完全退出后的冷启动、进程运行时第二次请求、同一 PID 复用、中文及特殊字符文件路径保持完整、主窗口可见并定位访达页面，测试文件内容未变。
- 在用户已移动的 `/Applications/iTools.app` 更新至 0.4.1，替换前对原 0.4.0 应用包归档备份并检查 ZIP；签名校验后更新 LaunchServices / PlugInKit，保留扩展启用状态。开发副本的注册被移除，安装位置为唯一登记的 Finder 扩展。
- 测试日志：.build/finder-fix-tests.log、.build/finder-fix-build.log、.build/finder-fix-smoke.log、.build/finder-launch-built.log、.build/finder-launch-installed.log、.build/finder-fix-install.log。
- 测试覆盖缺失附加对象的回调、真实主程序启动和请求接收；未自动操作用户 Finder 的右键菜单。用户可重新打开右键菜单点击项目，主程序展示请求后仍需「确认并执行」。


## 0.5.0 Finder 直接执行

- 核心测试 **73 项通过，0 失败**，新增内部请求协议隔离、所有动作往返、重复 / 未知 / 过长 / 无效参数拒绝、逐次点击编号及移动后组件定位测试。
- Debug / Intel Release 构建通过。新增的后台操作组件与主程序、Finder 扩展均为 x86_64 / macOS 12.0 部署目标；完整应用通过递归严格签名校验。
- 通过真实 Launch Services 对构建包及 `/Applications/iTools.app` 各运行 **22 次直接请求**：7 种新建格式、同名编号、隐藏 / 显示、跨目录剪切粘贴、SHA-256、扫描、ZIP / 7z、错误处理及异步排队。真实临时文件的结果通过验证，原文件未被覆盖。
- 冷启动、热启动保持同一 accessory 进程；没有新建主程序进程，测试期间可见组件窗口为 0；重复投递同一个请求未重复新建。内部协议没有全局 URL handler。
- 终端测试检查选中文件的父目录与选中文件夹原样传给 Terminal 打开函数。**这一集成测试用观察钩子替代实际 Terminal 启动与 Finder reveal**，没有向用户终端输入命令或读取 / 改写用户剪贴板；结果对话框在该模式记录标题，不弹出。真实鼠标右键和专用对话框仍需日常实机交互验收。
- 原有应用 GUI 自检通过，包括 149 个快捷键动作、Carbon 注册 / 分发 / 替换 / 注销、独立剪贴板面板、主界面渲染、OCR、菜单栏、Finder 公共链接仅待确认及压缩加密。
- 已将安装位置更新到 0.5.0，原 0.4.1 应用 ZIP 备份保存在 `.build/install-backups`。只重新登记 iTools 扩展，PlugInKit 保留启用，登记路径为 `/Applications/iTools.app/Contents/PlugIns/IToolsFinder.appex`。
- 本轮日志：`.build/finder-direct-tests.log`、`finder-direct-build.log`、`finder-direct-integration.log`、`finder-direct-installed.log`、`finder-direct-smoke.log`、`finder-direct-install.log`。实际运行系统仍为 Intel / macOS 13.7.8；macOS 12 兼容性来自部署目标及可用性编译检查。


## 0.6.0 优先系统联动

- 核心测试 **76 项通过**。新增系统应用选择参数、禁止给其他动作附加应用参数、多选应用交集与系统顺序、压缩需要密码与普通损坏区分；未加密档案不先询问密码。
- GUI 自检通过：标准 NSURL 文件剪贴板读写、部分移动后保留未完成项、外部拷贝文件、用户中途复制新内容后不覆盖、旧剪切失效；测试使用独立 pasteboard，不读取或修改用户剪贴板。
- 重命名 / 批量重命名 / 编码修复在同一窗口输入、预览、应用，已导出自身 NSView 并检查布局；原有 149 个快捷键及剪贴板、菜单栏、8 个页面自检继续通过。
- 已通过 macOS NSWorkspace.recycle 将唯一合成 TXT 移到系统废纸篓，没有附加确认或主窗口。CLI 从废纸篓还原时被 macOS 隐私保护拒绝，未申请完全磁盘访问，也未修改权限；该合成「未命名.txt」保留在系统废纸篓（来源 `.build/finder-native-built-2/paste destination/未命名.txt`，内容为测试文本）。没有改动用户既有废纸篓文件。
- 因上述环境限制，完整重复测试中的回收函数使用测试目录内的替代实现，验证压缩校验 / 原件检查 / 回收回调 / 失败处理；其他文件操作仍真实执行。终端、应用打开和 Finder reveal 沿用观察钩子；真实 Finder 右键点击、接收者选择等仍需实际使用验收。
- 测试须串行运行：GUI 自检会主动启动主程序，不能与「未拉起主程序」的进程检查同时运行。
- 日志：`.build/finder-native-tests.log`、`finder-native-build.log`、`finder-native-integration.log`、`finder-native-smoke.log`；窗口渲染位于 `.build/smoke-finder-native`。

- 最终构建包及 `/Applications/iTools.app` 各通过 **29 项直接请求回归**，没有新主程序进程或可见主窗口。安装版 0.6.0 与构建产物四个可执行文件逐项一致，均为 x86_64 / minos 12.0；递归严格签名及 ZIP 完整性校验通过。原 0.5.0 应用已归档备份，Finder 扩展保持启用、只登记安装位置。

## 0.6.1：Finder 沙盒首次启动修复（2026-09-10）

- 用户重启后的系统日志明确记录 `NSOSStatusErrorDomain -10820 / kLSAppDoesNotClaimTypeErr`，新建 TXT 和进入终端均在 Launch Services 转交阶段失败。安装签名正常。使用相同沙盒 entitlement 的独立探针成功复现旧的「打开未注册内部 URL」失败；此前普通进程的启动测试不足以覆盖这个边界。
- 新通道由 `FinderLaunchEvent` 共用：显式 `openApplication` + `aevt/oapp` 的私有请求列表参数，不注册公开 URL，不新增自动化授权。接收器在 `applicationWillFinishLaunching` 注册。普通启动没有操作参数时不执行文件动作；异常列表整体拒绝。
- **81 项核心测试通过**，包含新增的启动参数往返、公共链接/错误事件/非文本内容拒绝、列表数量限制、不激活窗口、错误提示及安装路径替换设置。
- 构建包与 `/Applications/iTools.app` **分别通过真实沙盒冷、热启动及 29 项操作回归**。每次先移除仅被测后台组件的旧 Launch Services 注册，并确认组件未运行；沙盒发送器无法写测试目录（实际验证拒绝写入），后台首次创建 TXT、第二次创建重名编号文件，原文件内容保留，Finder 实际选中文件，主程序进程集合不变。
- 批量测试会话由普通控制器启用隔离钩子，再由同一个沙盒发送器投递全部请求，覆盖新建多格式、终端文件父目录/文件夹、隐藏显示、剪切粘贴、哈希扫描、ZIP/7z、校验、回收回调、解散、写权限、打开方式、错误路径、队列和重复 UUID。29 份回执均保持同一 accessory PID、没有 iTools 可见窗口，也没有启动主程序。终端/外部应用打开和回收在批量回归中使用钩子；用户剪贴板和废纸篓未被本轮测试改写。
- 测试方式调整：NSWorkspace 实测过滤了沙盒调用方的 launch arguments 和环境变量，因此没有用测试钩子的启动成功冒充实际冷启动。首次两条 TXT 请求使用未经修改的真实组件；它们会显示测试目录的 Finder 窗口。旧的环境变量测试尝试已移除。
- 已安装 **0.6.1 / build 9**，旧 0.6.0 保存于 `.build/install-backups/iTools-0.6.0-8e50e830-2878-43ec-823b-f132ec2ec9c9.zip`。扩展保持启用并仅登记 `/Applications/iTools.app`。主程序、扩展、操作组件、7zz 均为 x86_64 / minos 12.0，安装与构建产物 SHA256 逐项一致；严格递归签名和 `iTools-0.6.1-intel.zip` 完整性校验通过。
- 本轮没有重启用户电脑，也未自动点击真实 Finder 菜单；验证的是与扩展一致的沙盒发送路径、清除该组件旧注册后的进程冷启动和实际文件结果。macOS 12 实机及真正注销/重启后菜单点击仍需手动验收，不能以本机 macOS 13 测试替代。

可复查日志：`.build/finder-reboot-tests.log`、`.build/finder-reboot-sandbox-built.log`、`.build/finder-reboot-sandbox-installed.log`、`.build/finder-reboot-install.log`、`.build/finder-reboot-binaries.log`；汇总在 `dist/verification.txt`。测试目录为 `.build/finder-reboot-sandbox-built-2` 和 `.build/finder-reboot-sandbox-installed-1`。

## 0.7.0：自定义 Finder 一级菜单（2026-09-10）

- **86 项核心测试通过**。新增菜单默认布局、跨分组提升、无重复/遗漏、隐藏空分组与空总菜单、未知未来 ID 保留但不渲染、损坏配置安全回退。
- 原生 NSMenu 验证通过：未选择、常用组合、单独提升打开方式、全部提升，共 47 项操作完整保留；原分组中不重复显示已提升项；tag 回调仍携带正确文件/目录，打开方式保留默认应用与其他应用选择。无选择上下文时叶子菜单禁用。
- 专用配置域使用扩展只读授权。`scripts/test-finder-menu-preferences.py` 实际验证沙盒进程不能写工作区，但可读菜单配置；同一 PID 连续读到主程序更新、清空选择和新配置，另一个新进程仍能读到持久化结果。只使用随机测试键，测试后清除，没有修改用户真实菜单选择。
- 原生界面完整自检最终通过：新面板浅色/深色、8 个主页面、剪贴板焦点与数字/方向键/IME/Escape、149 项快捷命令、Carbon 注册和释放、状态栏与快捷面板。早期新增设置快照影响了后续焦点自检；快照渲染改至焦点检查之后，未修改剪贴板运行逻辑。浅色按钮文字对比度已修正，导出图像已逐项查看。
- `/Applications/iTools.app` 已更新到 **0.7.0 / build 10**。安装版通过真实沙盒冷/热启动新建 TXT 和 **29 项直接操作回归**；批量测试中的终端/外部应用打开、回收和剪贴板使用原有隔离钩子。新菜单位置不改变执行通道，不启动主程序。
- 已验证安装包内实际 Finder 扩展 entitlement：沙盒开启，仅对 `app.itools.mac.finder-menu` 偏好域增加只读访问。主程序、扩展、操作组件、7zz 均为 x86_64 / minos 12.0，构建与安装的 SHA256 一致。严格签名、ZIP 完整性校验通过；扩展保持启用且仅登记安装位置。
- 旧版备份：`.build/install-backups/iTools-0.6.1-8d954bec-5d99-44f0-8505-4c6ff5fb36c4.zip`。本轮没有重启电脑或自动点击真实 Finder 菜单；验证覆盖共用 NSMenu 构建器、真实沙盒配置读取及后台执行。macOS 12 实机仍待验收。

日志：`.build/finder-menu-tests.log`、`.build/finder-menu-preferences.log`、`.build/finder-menu-smoke.log`、`.build/finder-menu-installed.log`、`.build/finder-menu-binaries.log`；汇总：`dist/verification.txt`。设置预览：`docs/screenshots/finder-menu-settings.png`、`docs/screenshots/finder-menu-settings-dark.png`。


## 0.8.0 自启动开关 · 2026-09-10

- 已安装到 `/Applications/iTools.app`，版本 0.8.0 / build 11，Intel x86_64 / macOS 12.0 部署目标。主程序、Finder 扩展、文件操作组件、自启动组件、7zz 共 5 个可执行文件完成架构、部署目标、签名与构建/安装哈希核对。
- 94 项核心测试全部通过，新增自启动状态、首次注册 notFound、兼容作业状态、异步开关失败与重试，以及登录事件识别测试。日志：`.build/login-item-tests.log`。
- macOS 13.7.8 的真实 ServiceManagement 注册成功：disabled → enabled → disabled，开启和关闭均无错误；新进程读取恢复后的关闭状态。未保留启用状态。日志：`.build/login-item-installed.log`；系统回执：`.build/login-item-installed-final/registration.json`。
- 显式登录事件的冷启动只出现菜单栏、无主窗口、无 Dock 图标；再次投递登录事件不激活窗口；手动重新打开显示主窗口。实际内置自启动组件正确定位安装目录，主程序已运行时退出且不重复启动。
- 已安装版完整 GUI 自检通过：149 项快捷键、剪贴板面板焦点与数字键、菜单栏读数、Finder 一级布局、8 页面和深色总览。自启动设置的浅色关闭/深色待允许预览已导出并目视检查，主设置页实际显示「未开启」。日志：`.build/login-item-smoke.log`，图像：`docs/screenshots/login-settings.png` 和 `login-settings-approval.png`。
- Finder 沙盒回归通过：生产模式冷/热新建 TXT，以及 29 项直接操作回归，未打开主程序；Terminal、应用交接及废纸篓使用隔离观察钩子。日志：`.build/login-item-finder.log`。
- 包：`dist/iTools-0.8.0-intel.zip`，ZIP 完整性、签名和 SHA256 已核验。初始 0.7.0 安装备份保存在 `.build/install-backups/iTools-0.7.0-da5d98be-9cf5-4948-8ca9-931182878b74.zip`。

验证范围：本轮没有注销用户或物理重启，macOS 12 分支仍需 Monterey 真机登录验收。第一次集成运行因系统首次状态 notFound 跳过注册测试，随后按 Apple DTS 说明修正状态映射并通过最终真实注册/注销验证；没有把跳过记录作为注册通过依据。


## 0.8.1 侧边栏整行点击 · 2026-09-10

主窗口的统一导航按钮在 label 内填满可用宽度，并在内边距、背景之后使用矩形 contentShape，将图标、文字及行内空白纳入点击范围。全部 8 个页面复用同一处修改，保留原布局、选中样式及原生 Button 语义。

- Release 构建与完整签名通过；已安装到 `/Applications/iTools.app`，版本 0.8.1 / build 12。
- 现有原生 GUI 自检通过：8 页面与深色总览、快捷键和剪贴板面板、菜单栏、Finder 布局、自启动状态预览；已查看窗口与效率页渲染，侧边栏布局保持原样。本轮未通过桌面鼠标自动化点选侧边栏。日志：`.build/sidebar-smoke.log`。
- 5 个可执行文件均为 x86_64 / macOS 12.0 部署目标，构建与安装版本哈希一致。日志：`.build/sidebar-binaries.log`。
- ZIP 完整性与 SHA256 已验证：`dist/iTools-0.8.1-intel.zip`。

本轮仅修改导航按钮命中区域，未新增或重复运行核心单元测试，未重新注册自启动项目。

## 0.9.0 统一快捷键面板 · 2026-09-10

- 核心测试 **98 项通过，0 失败**。新增目录覆盖全部动作且不重复、未知动作回退、按功能归类、跨分类多词 / 按键搜索以及已设置过滤。日志：`.build/shortcut-center-tests-final.log`。
- 指南与编辑共用一个浮动窗口，包含 8 个整行可点击分类、用途卡片及行内录入。生产清单全部 149 个动作各出现一次，保留原命令 ID 和存储格式。剪贴板数字键、使用行为和横竖布局使用同一份原有偏好。
- 原生自检验证实际 `RecorderView` 成为窗口第一响应者，并向该响应者发送应用内按键事件；普通文字和重复组合被拒绝。真实 Carbon 临时注册造成的系统占用在保存时报告错误，原绑定保留；释放占用后保存 / 清除正常，Esc 只取消编辑，搜索、分类入口、失焦和关闭均恢复全局按键。
- 自检模型禁用持久化，测试结束恢复原绑定，并核对 `shortcuts.v1` 原始数据未被改写。没有向其他应用发送模拟全局按键，没有切换系统自启动状态。
- 导出并目视检查了浅色 / 深色剪贴板分类、常用入口、访达分组、窄窗口单列、跨分类搜索、空结果、已设置过滤和行内冲突。禁用的保存按钮已采用明确文字颜色，避免浅色外观下文字不可见。

本轮验证使用 Intel / macOS 13.7.8；macOS 12 兼容性通过部署目标与编译可用性检查，仍需 Monterey 真机交互验收。界面验证使用自身 NSView 和真实控制器，没有自动点击桌面上的其他应用。

最终构建日志：`.build/shortcut-center-build-final.log`。一次完整自检在旧剪贴板检查中未取得键盘焦点而停止（保留 `.build/shortcut-center-smoke-final.log`）；同一构建重新运行后，包括该焦点检查及新增编辑检查在内的全部自检通过，日志：`.build/shortcut-center-smoke-verified.log`。没有通过跳过或放宽焦点断言来获得通过结果。预览位于 `.build/smoke-shortcut-center-verified`，文档使用其中的最终图像。

已更新 `/Applications/iTools.app` 至 **0.9.0 / build 13**，Finder 扩展保持启用且只登记安装位置。主程序、扩展、文件操作组件、自启动组件及 7zz 共 5 个可执行文件均为 x86_64 / minos 12.0，安装与构建 SHA256 一致，完整签名校验通过。ZIP 完整性及 SHA256 已验证：`dist/iTools-0.9.0-intel.zip`。日志：`.build/shortcut-center-install.log`、`shortcut-center-binaries.log`、`shortcut-center-package.log`；汇总：`dist/verification.txt`。

旧 0.8.1 备份：`.build/install-backups/iTools-0.8.1-92976a2c-fbd2-41c6-867a-8da4349767c4.zip`。本轮未重新注册或修改自启动开关，也未改写已有快捷键、剪贴板布局或 Finder 菜单偏好。

## 0.9.1 更多操作图标修正 · 2026-09-10

快捷键面板的共用 `ShortcutActionRow` 明确隐藏原生菜单下拉指示器，只显示三点图标；菜单及 label 使用 30 × 30 pt 区域并保留原生 Menu 和辅助功能名称。全部 149 项功能共用此修改，不影响执行或清除逻辑。所用 `menuIndicator` 经本地 SDK 确认为 macOS 12.0 可用。

- Release 构建、签名和现有完整原生 GUI 自检通过；已目视检查浅色、深色及窄窗口单列预览，三点旁不再出现下拉箭头。未新增或重复运行核心单元测试，未用桌面鼠标自动化点击菜单。
- 已安装 **0.9.1 / build 14** 到 `/Applications/iTools.app`。5 个可执行文件均为 x86_64 / minos 12.0，构建与安装哈希一致。Finder 扩展保持启用，既有偏好未修改。
- 安装包 `dist/iTools-0.9.1-intel.zip` 的完整性和 SHA256 已验证。旧版备份：`.build/install-backups/iTools-0.9.0-79cafcf0-cd9d-4d96-b096-aa484d9cbb2c.zip`。

日志：`.build/shortcut-menu-build.log`、`shortcut-menu-smoke.log`、`shortcut-menu-install.log`、`shortcut-menu-binaries.log`、`shortcut-menu-package.log`。预览：`.build/smoke-shortcut-menu`；文档截图已更新。实机系统为 Intel / macOS 13.7.8。

## 0.10.0 屏幕底部剪贴板 · 2026-09-10

- 核心测试 **101 项通过，0 失败**。新增屏幕可用区域与 Dock 间距、负坐标 / 小屏边界、首次默认横向且保留明确竖向偏好的测试。旧布局存储值未改变。
- 真实面板控制器验证横向窗口取得焦点、实际 frame 与 `NSScreen.visibleFrame` 计算结果一致；方向键、类型筛选后的数字选择、空结果不使用旧记录、关闭和再次呼出均通过。原有搜索 / IME / Esc、文本 / 富文本 / 图片 / 文件私有剪贴板回归通过。
- 已导出并目视检查底部卡片的浅色、深色、窄屏和空结果，以及保留的竖向样式。黑白图片的浅深色预览均经 OCR 验证保留 Monterey 文字；缩略图不改变复制时使用的原始内容。检查原始分辨率 PNG，避免预览工具缩放带来的显示差异。
- 最终完整原生 GUI 自检通过，包括全部 149 项快捷键目录、真实行内录入响应者与系统快捷键冲突、Finder 一级菜单、状态栏及自启动设置预览。未向其他应用发送全局按键；测试使用禁用持久化的偏好模型、私有剪贴板及合成样例。
- 之前两次运行在原有快捷键编辑检查中遇到首次布局焦点竞争（日志 `clipboard-bottom-smoke.log`、`clipboard-bottom-smoke-verified.log`）。测试现先等待指南首帧布局，再模拟用户进入编辑；保留全部焦点与冲突断言，最终 `clipboard-bottom-smoke-release.log` 全部通过。
- 已安装 **0.10.0 / build 15** 到 `/Applications/iTools.app`。主程序、Finder 扩展、文件操作组件、自启动组件、7zz 共 5 个可执行文件均为 x86_64 / minos 12.0，构建与安装 SHA256 一致，完整签名校验通过。Finder 扩展保持启用且只登记安装位置；没有更改自启动开关或用户已有快捷键。
- 安装包 `dist/iTools-0.10.0-intel.zip` 的 ZIP 完整性与 SHA256 已核验。旧版备份：`.build/install-backups/iTools-0.9.1-3b2ff942-2c55-46d0-b53a-a339e9b12029.zip`。

日志：`.build/clipboard-bottom-tests.log`、`clipboard-bottom-build-release.log`、`clipboard-bottom-smoke-release.log`、`clipboard-bottom-install.log`、`clipboard-bottom-binaries.log`、`clipboard-bottom-package.log`。最终图片位于 `.build/smoke-clipboard-bottom-release`，文档截图已同步。

实机系统为 Intel / macOS 13.7.8；macOS 12 实机、物理多显示器和原生全屏空间中的交互仍需实际验收。本轮没有自动化点击桌面上的其他应用或改变用户剪贴板记录。

## 0.11.0 主窗口与指标面板材质 · 2026-09-10

- 主窗口采用统一石墨侧栏和浅深色工作区；设置等功能分区、剪贴板记录、截图编辑区和应用集成卡片共用边界与材质。主窗口内容区通过环境值启用分区卡片，独立快捷键工作台和底部剪贴板保持原布局。
- 指标弹框使用原有实时数据，增加曲线面积、使用率轨道及类型色图标；系统应用独立排列，快捷操作区分悬停、开启和禁用状态。标准 540 × 760 pt 预览完整显示默认 15 项操作；540 × 500 pt 保持滚动内容和固定底栏。更多自定义项目仍可滚动访问。
- Release 编译、应用组装与签名通过。初次编译已成功，但沙盒内 `iconutil` 返回 Invalid Iconset；同一图标集经获准的沙盒外转换通过，随后完整构建通过。最终日志：`.build/interface-build-release.log`。
- 完整原生 GUI 自检通过：149 项快捷键、真实 Carbon 注册与录入焦点 / 冲突恢复、底部剪贴板和图片预览 OCR、Finder 47 项菜单分布、菜单栏指标及自启动设置预览。日志：`.build/interface-smoke-release.log`。本轮没有改动核心业务模型，未新增或重复执行核心单元测试。
- 导出全部 8 个主页面，并增加深色设置 / 系统状态、最低内容宽度总览 / 设置，以及紧凑指标弹框。已目视检查重点页面的文字对比度、菜单图标、控件边界、图表填充和操作可见性；第一轮过高的指标卡片已收紧。最终导出位于 `.build/smoke-interface-release`，17 张主界面与面板预览已同步到 `docs/screenshots`。
- 已安装 **0.11.0 / build 16** 到 `/Applications/iTools.app`；5 个可执行文件均为 x86_64 / minos 12.0，构建与安装 SHA256 一致，4 个 bundle 的版本与最低系统要求一致，严格签名验证通过。Finder 扩展保留启用状态，既有快捷键、外观选择、自启动与其他偏好不迁移。
- 包：`dist/iTools-0.11.0-intel.zip`，ZIP 完整性及 SHA256 通过。备份：`.build/install-backups/iTools-0.10.0-7b5247e5-3117-44fb-9cdf-442b2bb7d735.zip`。安装、二进制与包校验日志分别为 `.build/interface-install.log`、`interface-binaries.log`、`interface-package.log`。

验证使用 Intel / macOS 13.7.8。macOS 12 仍是编译部署目标，尚未完成 Monterey 实机验收。界面检查使用本应用 NSView 渲染与自身控制器，不是对桌面其他应用的鼠标操作测试。自检使用合成剪贴板 / 截图样例和原有只读系统采样，没有替换用户数据或修改系统外观偏好。

## 0.12.0 iCopy 布局与原生毛玻璃 · 2026-09-10

- 按用户提供的 iCopy 图片重新布局：炭灰透明侧栏、居中品牌、彩色分类图标、卡片外分组标题、半透明圆角内容面板。移除总览深蓝横幅；设置短内容双列显示，最低宽度改为单列。
- 主窗口与顶部指标面板使用同一原生 `NSVisualEffectView` 背景和轻微淡色染色，浅深色分别适配；遵守「减少透明度」系统设置。
- 新增完整窗口检查：内容高度覆盖整个 NSThemeFrame，标题栏透明、标题隐藏且无分隔线，窗口本身非不透明；三个系统按钮均位于侧栏背景内，真实 hitTest 仍命中原生按钮，没有被顶部拖动区遮挡。导出包括按钮的完整窗口，避免仅检查内容区而遗漏顶栏色差。
- 受控背景实验曾在 `.build/glass-smoke-release.log` 中触发透色像素断言失败。进一步用不含 SwiftUI 的原生 NSVisualEffectView 对照：后方橙 / 蓝测试窗口本身确实改变颜色，但 `.hudWindow` 与 `.underWindowBackground` 的单窗口及指定双窗口捕获均返回固定玻璃底色。日志：`.build/glass-capture-materials.log`。因此移除这一不适用本机捕获方式的断言，保留全部窗口配置、材质及按钮命中检查；不将导出图片宣称为实时桌面模糊的像素验收。实验只涉及本次创建的窗口，没有请求额外录屏权限或捕获其他应用。
- 最终构建 `.build/glass-build-final.log` 成功。直接执行二进制的两次回归在剪贴板浮窗键盘焦点处中断（`glass-smoke-final.log`、`glass-smoke-verified.log`）；同一构建通过 macOS LaunchServices 正常打开后，完整回归全部通过：`.build/glass-smoke-launch.log`。没有改动或跳过剪贴板焦点断言。
- 最终回归覆盖 149 项快捷命令及真实 Carbon 注册、剪贴板横竖面板与图片 OCR、47 项 Finder 菜单、自启动设置预览、菜单栏指标、8 个主页面，以及浅深色和最低宽度的完整窗口框检查。导出位于 `.build/smoke-glass-launch`，文档预览已同步。核心业务模型未修改，本轮未重复执行核心单元测试。
- 已更新 `/Applications/iTools.app` 为最终 **0.12.0 / build 17**。安装前该位置已有本轮较早的 0.12.0 构建；按确切 SHA256 确认并备份后替换，备份为 `.build/install-backups/iTools-0.12.0-preview-e6ed837d-9c45-4475-b00e-c814e16eea1d.zip`。安装日志 `.build/glass-install-final.log`。
- 5 个二进制均为 x86_64 / minos 12.0，安装与构建 SHA256 一致；4 个 bundle 版本一致，严格签名验证通过。Finder 扩展保持启用。分发包 `dist/iTools-0.12.0-intel.zip` 完整性及 SHA256 已校验；日志 `.build/glass-binaries-final.log`、`.build/glass-package.log`。

实机验证系统为 Intel / macOS 13.7.8；macOS 12 仍为编译部署目标。完整窗口图片用于布局、按钮位置与对比度检查，不能替代在用户桌面上移动窗口时的实时毛玻璃观感验收。

## 0.12.1 透明滚动条轨道 · 2026-09-10

- 主窗口、顶部指标面板、快捷键中心、剪贴板、Finder 菜单设置及截图缩略图区改用 GlassScrollView。清除滚动视图与 clip view 的底色，GlassScroller 只覆盖轨道绘制；原生滑块、拖动处理、常驻 / 自动隐藏样式和系统偏好保留。
- 独立原生组件对照验证浅色 / 深色 legacy 滑块：实色轨道消失；发往测试窗口自身的鼠标拖动事件将内容从 y=0 滚至 y=408，target/action 仍为原 NSScrollView。日志 `.build/scroll-probe/result.log`；没有向桌面其他应用发送输入。
- 最终构建及完整原生 GUI 回归一次通过，使用 LaunchServices 正常启动。覆盖 149 项快捷命令、剪贴板焦点与横向滚动选择、47 项 Finder 菜单、菜单栏读数、8 个主页面、浅深色及最低宽度窗口框。已目视检查总览、深色设置和快捷面板的透明轨道。日志 `.build/scrollbar-build.log`、`.build/scrollbar-smoke.log`；图片 `.build/smoke-scrollbar`，文档预览已同步。核心业务模型未改，本轮未重复核心单元测试。
- 已安装 0.12.1 / build 18；5 个二进制均为 x86_64 / minos 12.0，构建与安装 SHA256 相同，4 个 bundle 版本一致，签名及分发 ZIP 校验通过。Finder 扩展保持启用，系统滚动条偏好未改。旧版备份 `.build/install-backups/iTools-0.12.0-462f784d-65c3-4dcd-a13b-36c1ee68e662.zip`；安装、二进制与打包日志为 `.build/scrollbar-install.log`、`scrollbar-binaries.log`、`scrollbar-package.log`。

实机系统 Intel / macOS 13.7.8；macOS 12 兼容性仍由部署目标和可用性编译检查覆盖。

## 0.12.2 顶部面板柔和彩色图标 · 2026-09-10

- 快捷操作使用浅色半透明底座和按用途分类的彩色字形；启用时增加填色和勾选角标，悬停使用透明高亮。已查看浅色、深色和紧凑高度面板预览，常用 15 项入口仍可见。
- 仅顶部面板启用 softIndicators：滑块绘制宽度缩至 5 点，降低浅色外观下的填充浓度，透明轨道保持不变；保留原生命中区域和事件跟踪，高对比度模式增加填充浓度。独立组件浅深色拖动检查均将内容从 y=0 移至 y=408，日志 `.build/soft-panel-scroll-probe.log`。
- 最终构建及完整原生 GUI 回归通过，包含主窗口、顶部面板、149 个快捷命令、剪贴板焦点和图片预览、47 项 Finder 菜单及登录设置预览。日志 `.build/soft-panel-build.log`、`.build/soft-panel-smoke.log`；面板导出 `.build/smoke-soft-panel`，文档四张快捷面板图片已同步。未改动核心业务模型，未重复运行核心单元测试。
- 已安装 0.12.2 / build 19。5 个二进制 x86_64 / minos 12.0，安装与构建 SHA256 一致，4 个 bundle 版本一致，签名及 ZIP 完整性检查通过。原 0.12.1 备份 `.build/install-backups/iTools-0.12.1-61188085-76a5-449c-a227-514318c99b40.zip`。安装、二进制与打包日志：`.build/soft-panel-install.log`、`soft-panel-binaries.log`、`soft-panel-package.log`。

实机验证仍为 Intel / macOS 13.7.8；macOS 12 为编译部署目标。


## 0.12.3 — 主窗口浅色滑块与移除应用集成（2026-09-10）

- 主窗口共用的 `GlassScrollView` 启用 `softIndicators`，七个页面的外侧滚动条复用顶部弹框的 5 pt 浅色滑块、透明轨道和浅深色适配。原生滚动、拖动范围及系统滚动条偏好保留。
- 移除应用集成页面、模型和检测服务、原应用启动/图片交接、页面快捷键及四个原应用快捷键，清理总览和设置能力说明。快捷键工作台变为七类、144 项命令；系统应用快捷入口及 Finder 文件工具保留。
- 20 项快捷键及分类测试全部通过，包括用旧版五项集成绑定模拟升级：旧动作不再注册或占用组合键，其余自定义绑定、手动清除状态和重启后的新分配保留。仅使用隔离的 UserDefaults 测试域。日志 `.build/main-cleanup-tests.log`。
- 构建及完整原生 GUI 自检通过：144 项动作各归类一次、Carbon 注册/冲突/注销、剪贴板面板、47 项 Finder 菜单、菜单栏与登录设置、七个主页面。完整窗口检查确认原生毛玻璃、标题栏按钮和透明浅色滑块。目视检查系统状态、深色设置与七类快捷键工作台，导出位于 `.build/smoke-main-cleanup`，当前文档截图已更新。日志 `.build/main-cleanup-build.log`、`.build/main-cleanup-smoke.log`。
- 安装至 `/Applications/iTools.app`，原 0.12.2 已备份；四个 bundle 均为 0.12.3 / build 20，五个可执行文件均为 x86_64、最低 macOS 12，构建/安装 SHA256 相同且完整签名有效，Finder 扩展已注册。包 `dist/iTools-0.12.3-intel.zip` 的 ZIP 完整性已验证，SHA256 为 `7aaa890d9d5c4837e9bd57ab715595f97a50f2b9a59c4edf265aa5f6b03d956f`。

## 0.13.0 权限状态、提示层级与粘贴（2026-09-10）

- 23 项粘贴就绪 / 快捷键 / 分类测试通过；随后收紧超时判断后，3 项粘贴边界测试再次通过。覆盖目标关闭、剪贴板变化、修饰键未释放、目标未激活，以及已到截止时间但目标刚激活时拒绝发送。
- 授权窗口自检注入未授权 / AX 已授权但事件发送未授权 / 均已授权状态，检查单实例、层级与焦点、回到系统设置时可隐藏、刷新不重试、拒绝粘贴不改剪贴板和不消耗队列。没有实际申请隐私权限或向其他应用发送按键。
- 初次原生检查发现普通 NSPanel 无法可靠取得焦点，已显式允许成为 key window；移除快捷键面板执行动作时多余的目标应用激活。后续检查又发现同步嵌套 RunLoop 无法及时处理主队列激活通知，验证流程改为异步等待；保留失败日志，未降低 key-window 断言。
- 重新打开应用时的忙碌/启动错误在授权窗口内显示，避免再次产生被覆盖的主窗口错误框。
- 固定本地证书签名的实际 designated requirement 绑定 app.itools.mac 与证书哈希，已确认不再仅依赖二进制 cdhash。首次由临时签名迁移仍需用户重新授权；本地签名不是 Developer ID 公证。
- 本轮没有以单元测试或模拟授权代替真实跨应用粘贴、窗口调整的端到端验收，macOS 12 实机及其他 Intel 设备仍需对应环境。
- 最终完整 GUI 回归通过：授权窗口 visible/key/appActive 均为 true，层级为 8、主窗口为 0；7 个主页面及浅深色/窄窗口、144 条快捷命令、47 项 Finder 动作均通过既有原生自检。
- 0.13.0 / build 21 已安装到 `/Applications/iTools.app`，旧 0.12.3 已备份。四份 bundle 清单一致；五个可执行文件均为 x86_64、minos 12.0，构建与安装版本逐一 SHA-256 相同；严格递归签名校验、ZIP 完整性校验通过。
- 安装后只读诊断：辅助功能 false、事件发送 false、屏幕录制 false、麦克风 notDetermined。已向用户展示重新授权步骤；这些状态不能由程序代替用户开启，尚未据此声称真实跨应用粘贴/窗口布局验收通过。
- 日志：`.build/permissions-tests.log`、`permissions-timeout-tests.log`、`permissions-final-build.log`、`permissions-final-smoke.log`、`permissions-install.log`、`permissions-binaries.log`、`permissions-installed-status.json`、`permissions-package.log`。图片：`docs/screenshots/permission-guide.png`（模拟未授权的开发路径说明）。
- 默认沙盒内的 codesign 校验无法读取当前用户本地代码签名信任，返回 CSSMERR_TP_NOT_TRUSTED；在正常用户信任环境重跑后通过。未修改隐私授权来使验证通过。

## 0.13.1 单击复制、双击粘贴（2026-09-10）

- 主窗口历史与短语、横向卡片及竖向列表统一鼠标语义，系统悬停提示与面板底栏/设置/指南一致。鼠标单击复制保持浮层，双击通过原有权限与目标应用流程粘贴；数字/回车仍按原偏好执行。
- 独立原生测试窗口复用实际 `clipboardRecordActions`，向该窗口事件队列投递带递增 eventNumber 的鼠标按下/抬起：单击仅复制一次、双击仅粘贴一次、独立按钮执行且不触发记录复制均通过。初检发现父级手势与按钮联动，已将按钮从记录手势区域分离；测试事件未写系统剪贴板、未发全局输入。原始检查脚本和日志在 `.build/clipboard-click-probe/`、`.build/clipboard-click-pointer.log`。
- 完整原生 GUI 回归通过：7 个主页面、浅深色/窄布局、横竖剪贴板、快捷短语、144 个命令、47 个 Finder 动作、授权窗口层级和拒绝粘贴队列保护。人工查看主窗口与横向卡片导出，提示文字未截断。
- 已安装 `/Applications/iTools.app` 0.13.1 / build 22，旧 0.13.0 备份位于 `.build/install-backups/`。严格签名、四份清单版本、五个 Intel 可执行文件的 macOS 12.0 目标及构建/安装哈希一致性、ZIP 完整性校验均通过。沿用上一版的本地签名身份，没有重置隐私权限或覆盖用户偏好。
- 日志：`.build/clipboard-click-build.log`、`clipboard-click-smoke.log`、`clipboard-click-install.log`、`clipboard-click-binaries.log`、`clipboard-click-package.log`。本轮未实际向其他应用粘贴内容，实际插入仍取决于用户授权及目标输入框。

## 0.13.2 深色分块、窗口布局图标与菜单栏管理（2026-09-10）

- 提亮共用深色卡片、按钮底色、辅助文字与边框，使用轻微高光保持毛玻璃层次；浅色配色及「减少透明度」适配保留。顶部指标面板也使用新的卡片色值。
- 窗口布局的 11 种排列与还原操作均增加图形标识。位置示意复用实际布局几何，左 / 右半屏、四角、三分屏、最大化、居中与还原均已目视检查；操作仍调用原来的窗口服务。
- 「菜单栏显示」完整区块从设置移到系统状态页面首位，沿用同一 MenuBarPreferences 对象及原有持久化；七个指标开关、实时预览和监控提示保持完整，不重置用户配置。
- 构建及完整原生 GUI 回归通过，覆盖 7 个主页面和 8 个补充外观 / 窄窗口预览、144 个快捷命令、47 个 Finder 动作、剪贴板面板与授权窗口检查。重点查看深色窗口布局、深色系统状态、顶部面板，以及最低窗口宽度下的系统状态和窗口布局，未发现标签截断或控件重叠。文档图片已同步。
- 已安装并重新打开 `/Applications/iTools.app` 0.13.2 / build 23。四份清单版本一致，五个可执行文件均为 x86_64、minos 12.0，构建与安装 SHA256 逐一相同，严格签名验证通过。保留此前的固定本地签名身份。旧版备份：`.build/install-backups/iTools-0.13.1-59c239bf-d3c8-40e4-9d30-0a97f0840d28.zip`。
- 安装包 `dist/iTools-0.13.2-intel.zip` 完整性通过，SHA256 为 `f701167d51b36f8c3408b178528970adcb21d5f68ab77f86c13438206c646c74`。首次打包的自动审核超时，重试成功；安装和签名检查均已完成。
- 日志：`.build/interface-refinement-build.log`、`interface-refinement-smoke.log`、`interface-refinement-install.log`、`interface-refinement-binaries.log`、`interface-refinement-package.log`。本轮调整表现层与设置入口，没有修改业务模型，未重复运行核心单元测试，也未向其他应用执行窗口调整或申请隐私权限。实机为 Intel / macOS 13.7.8；macOS 12 为编译部署目标。

## 0.13.3 多显示器指标浮框稳定性（2026-09-11）

- 去掉 NSPopover 对动态 NSStatusBarButton 的持续附着和打开时的 NSApp.activate，改为非激活 NSPanel。点击时根据全局鼠标位置确定屏幕，保存位置与尺寸；菜单栏按钮位于另一屏的副本坐标不参与定位。指标刷新只更新内容，各菜单栏指标使用固定宽度。
- 12 项相关单元测试通过（6 项定位、6 项指标 / 设置）：副屏在左 / 右 / 上 / 下、主屏按钮副本与真实点击屏不同、边缘和小尺寸可用区、快捷键定位、空屏幕列表、设置持久化与指标格式。初次测试因沙盒外默认模块缓存不可写而中止；指定项目内模块缓存后通过。
- 本机实际连接两块显示器：主屏逻辑尺寸 1680×1050，扩展屏逻辑尺寸 1920×1080，扩展屏原点为 (-1920, -30)。在两屏分别显示真实原生面板，每屏执行 36 次间隔 0.1 秒的检查，同时持续改变 CPU / 网络内容并保留正常系统采样；面板位置、屏幕 ID、key 状态、主窗口 frame、前台应用 ID 均保持稳定。只展示 / 检查本应用窗口，没有模拟对其他应用的输入。
- 完整原生 GUI 回归通过：菜单栏创建 / 删除及宽度稳定性、浮框开关与浅深色、144 个快捷命令、47 个 Finder 动作、剪贴板面板、权限提示层级、7 个主页面和浅深色 / 窄布局。已查看扩展屏面板导出，箭头、圆角、毛玻璃及快捷入口布局正常。
- 已安装并打开 `/Applications/iTools.app` 0.13.3 / build 24。4 份 bundle 清单一致，5 个二进制均为 x86_64 / minos 12.0，构建与安装 SHA256 相同，严格递归签名校验通过并沿用同一本地签名身份。旧版备份 `.build/install-backups/iTools-0.13.2-b880f2d1-059b-431e-8eea-4fbef220047b.zip`。
- 分发包 `dist/iTools-0.13.3-intel.zip` 完整性通过，SHA256：`3f87ca92f0bd9b848dab58b3091527d0b36def827f839f8d4a013355670ca8ce`。日志 `.build/multiscreen-tests.log`、`multiscreen-build.log`、`multiscreen-smoke.log`、`multiscreen-install.log`、`multiscreen-binaries.log`、`multiscreen-package.log`。
- 实际原生回归覆盖当前左右双屏环境；上下排列与小屏场景由几何单元测试覆盖。没有更改用户的显示器排列、桌面 / Space 或隐私权限；macOS 12 及其他全屏应用组合仍需对应环境验收。

## 0.13.4 快捷剪贴板毛玻璃、分类颜色与自动搜索（2026-09-11）

- 横向与竖向面板统一原生 behind-window 毛玻璃背景；分类按钮使用粉、绿、金、蓝、紫背景，历史卡片标题区使用明亮类型色，选中边框跟随类型色。浅深色分别适配文字和正文底色，图片预览保持原图颜色。两种排列均使用透明轨道和 5 pt 淡色滑块。
- 打开面板前设置搜索状态，原生 NSTextField 在真实 key window 中取得 field editor 焦点，直接键入即可过滤。↓ / Esc 返回记录选择，数字键仍可按原偏好使用内容；输入搜索数字和中文组词不会误触发选择或粘贴。单击复制、双击粘贴保持原有流程。
- 初次验证发现 SwiftUI 焦点状态与实际第一响应者不一致；改用原生输入框后定位到旧的 makeFirstResponder(nil) 清除了刚获得的焦点。移除这处冲突，并检查实际 field editor 身份后通过。保留失败日志 `.build/clipboard-glass-smoke.log`、`clipboard-glass-smoke-final.log`、`clipboard-glass-smoke-verified.log`，没有降低焦点断言。
- Debug 和最终 Release 原生 GUI 回归均通过。新增异步检查覆盖竖向、横向、快捷短语三种模式：窗口 visible/key/focused 均为 true，实际第一响应者为 NSTextView；向该编辑器输入 42 后正确过滤一条结果且未触发选择，中文 marked text 期间回车和方向键交给输入法。测试使用合成记录与选择回调，没有向其他应用粘贴或修改用户历史。
- 原有回归继续通过：144 个快捷命令、47 项 Finder 动作、图片预览 OCR、剪贴板导航和私有粘贴板类型、权限提示层级、7 个主页面及浅深色 / 窄窗口。已查看浅色、深色、窄屏横向面板和深色竖向面板；文档预览同步最终 Release 导出。原生毛玻璃配置已验证；单窗口导出用于布局与对比度检查，不代表桌面实时模糊的像素验收。
- 已安装并打开 `/Applications/iTools.app` **0.13.4 / build 25**。4 份 bundle 清单一致，5 个可执行文件均为 x86_64 / minos 12.0，构建与安装 SHA256 相同，严格递归签名通过，沿用原固定签名身份。旧版备份：`.build/install-backups/iTools-0.13.3-f6cded49-cadc-45d2-8415-b80c9d936e4b.zip`。
- 分发包 `dist/iTools-0.13.4-intel.zip` 完整性通过，SHA256：`e107eeff7fe3c5c6aabf8516108ea083f8499067493fb072f964b57054b32c6f`。最终日志：`.build/clipboard-glass-release-build.log`、`clipboard-glass-release-smoke.log`、`clipboard-glass-install.log`、`clipboard-glass-binaries.log`、`clipboard-glass-package.log`；图片位于 `.build/smoke-clipboard-glass-release`。
- 实机系统 Intel / macOS 13.7.8；macOS 12 为编译部署目标。本轮未修改核心业务模型，未重复核心单元测试，也未改变隐私权限、系统外观或滚动条偏好。

## 0.13.5 剪贴板恢复数字操作优先（2026-09-11）

- 打开历史或短语面板时恢复记录选择状态，移除自动请求搜索焦点的任务；搜索改由点击输入框或 ⌘F 进入。数字 / 回车的复制或粘贴行为继续遵循用户原有偏好，单击复制、双击粘贴以及 0.13.4 毛玻璃和彩色卡片保留。设置、指南及搜索占位提示同步更新。
- 更新已有异步原生焦点检查：横向、竖向、短语面板打开时无编辑器抢占，裸数字直接路由对应记录的复制；⌘F 使实际 NSTextView field editor 获得焦点，输入 42 正确过滤且不执行内容；输入法组词受保护，↓ / Esc 后数字选择恢复。测试使用合成记录和复制回调，不写用户剪贴板或向其他应用粘贴。
- Debug 完整原生 GUI 回归通过。首轮 Release 的本次剪贴板流程通过，后续快捷键工作台出现一次录入焦点断言失败；另两次完整流程分别在浮层失焦关闭、搜索结果断言处中止。相关日志完整保留，不能据此宣称完整 Release 回归全部通过。未降低原检查标准；增加仅运行剪贴板流程的诊断入口，在启动事务结束后执行，以便独立复核真实焦点和按键行为。
- 上述日志：`.build/clipboard-record-focus-debug-smoke.log`、`clipboard-record-focus-release-smoke.log`、`clipboard-record-focus-release-smoke-verified.log`、`clipboard-record-focus-release-smoke-final.log`。一次测试启动遭遇自动审批超时，重试后启动成功。
- 最终 Release 构建的独立原生验证通过：三种面板的初始焦点均为 FloatingToolPanel，进入搜索后实际 field editor 保持当前响应者、查询为 42、结果一条且额外执行次数为零；数字复制、输入法保护及退出搜索恢复数字选择全部通过。日志 `.build/clipboard-record-focus-isolated.log`，构建 `.build/clipboard-record-focus-final-build.log`。布局和提示预览来自本轮通过的 Debug 完整回归，已同步文档。
- 已安装并打开 `/Applications/iTools.app` **0.13.5 / build 26**。4 份清单与 5 个 Intel 二进制的 macOS 12 部署目标一致，构建与安装哈希相同；严格签名及固定本地签名身份校验通过。备份：`/Users/wtone/www/itools/.build/install-backups/iTools-0.13.4-ee1c4412-e07b-4199-9dcf-2e6e9e891143.zip`。
- `dist/iTools-0.13.5-intel.zip` 完整性通过，SHA256：`455b06deb1e88d4f3e0662547832761d35d9a7ee4a86e148902281de3fa7f274`。日志 `.build/clipboard-record-focus-install.log`、`clipboard-record-focus-binaries.log`、`clipboard-record-focus-package.log`。实机 Intel / macOS 13.7.8；未改动隐私权限、用户偏好或实际剪贴板内容。

## 0.13.6 快捷剪贴板滚轮与悬停分类（2026-09-11）

- 横向历史 / 短语列表将记录区域内的普通竖向滚轮输入映射为左右移动，保持系统方向和滚动增量；局部监听仅处理所属可见窗口和滚动区域。原生横向手势、Shift 滚轮、其他页面和窗口保持原行为。
- 搜索右侧五种类型按钮在 onHover 进入时立即筛选，点击保留；按钮使用固定尺寸。分类切换共用状态方法，保留查询和自定义分组，选中首条匹配记录，并滚回分类开头；悬停已选类型不会重复重置。
- 首次检查发现直接转发重建的横向 NSEvent 后真实 NSScrollView 未移动，已改为依据原始滚动增量移动 NSClipView，使用原生边界约束、滑块刷新与显示。保留失败日志 `.build/clipboard-pointer-debug-smoke.log`；修正后的 Debug 专项检查通过，真实横向原点从 (0, 0) 移至 (30, 0)，反向 / 左边缘、精确像素距离及不改写横向事件均通过。
- 同一专项检查覆盖竖向、横向、短语面板打开后的数字复制、⌘F 实际编辑焦点、搜索数字和输入法保护、↓ / Esc 返回数字选择。日志 `.build/clipboard-pointer-debug-smoke-final.log`。这些是本应用合成记录和原生窗口检查，未操控其他应用或系统剪贴板；悬停入口通过 SwiftUI 标准 onHover 连接，没有将状态方法调用宣称为真实鼠标移动验收。
- 最终 Release 构建及同一剪贴板专项检查通过，日志 `.build/clipboard-pointer-release-build.log`、`clipboard-pointer-release-smoke.log`。本轮未更改核心业务模型，未重复完整界面回归或核心单元测试。
- 已安装并打开 `/Applications/iTools.app` **0.13.6 / build 27**。4 份清单、5 个 x86_64 可执行文件的 macOS 12 部署目标及构建 / 安装哈希一致；严格签名、原固定签名身份、ZIP 完整性校验通过。旧版备份 `.build/install-backups/iTools-0.13.5-168cd7c2-eb15-4de0-abaa-6e031abaeaf6.zip`。
- 分发包 `dist/iTools-0.13.6-intel.zip`，SHA256：`211b406d92cc278dfd1b9ae2b87c42db804865aedd62d35f1425bd05d8160f68`。安装 / 校验日志 `.build/clipboard-pointer-install.log`、`clipboard-pointer-binaries.log`、`clipboard-pointer-package.log`。实机 Intel / macOS 13.7.8；macOS 12 为编译部署目标。


## 0.13.7 深色卡片去描边与指南入口（2026-09-11）

- 主窗口深色页面通过共享 `InstrumentSurface` 移除分区与卡片的装饰描边，保留半透明底色和原有亮度。浅色页面、输入控件与功能图形保持各自样式。
- 顶部信息框的固定底栏增加键盘图标与完整「快捷键与操作指南」按钮，复用已有指南查看 / 编辑回调，并先关闭信息框；原顶部无文字的键盘按钮移除。
- Release 构建、严格签名与专项原生界面导出通过，包含 7 个页面的浅 / 深色、4 个窄窗口页面，以及信息框浅 / 深色和紧凑尺寸。已目视检查深色剪贴板、总览、设置、窗口布局，以及深色 / 紧凑信息框：卡片无亮色描边，指南按钮未截断或重叠。
- 保留原有透明标题栏、窗口按钮命中、behind-window glass 和淡色透明滚动条检查，全部通过。单窗口图像用于布局验收，不能代替桌面实时模糊效果的像素验收。
- 日志：`.build/dark-border-guide-build.log`、`dark-border-guide-preview.log`；预览位于 `.build/preview-dark-border-guide`。本轮为样式和入口调整，未重复完整功能 / 核心测试，未执行真实粘贴或修改用户权限与剪贴板历史；样例记录仅在内存中生成。
- 已安装并打开 `/Applications/iTools.app` **0.13.7 / build 28**，四份清单与五个 x86_64 二进制的 macOS 12 部署目标、构建 / 安装哈希均一致，沿用原固定本地签名身份。旧版备份：`.build/install-backups/iTools-0.13.6-94a7fabf-84b0-4681-8292-e2f4dd5564a8.zip`。
- ZIP 完整性通过：`dist/iTools-0.13.7-intel.zip`，SHA256 `71dc07540c31bac7ebf2e8a34493488f21c7891218affa87b75d343716bf12b5`。安装、二进制和打包日志：`.build/dark-border-guide-install.log`、`dark-border-guide-binaries.log`、`dark-border-guide-package.log`。实机 Intel / macOS 13.7.8，macOS 12 为编译部署目标。
