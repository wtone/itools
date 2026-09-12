# 开机自启动

在 **iTools → 设置 → 启动设置** 中开启「开机自启动」。此处的自启动指当前用户登录 Mac 后启动，不是在登录前运行系统服务。首次安装默认关闭。

登录时只显示菜单栏入口，不弹出主窗口、不显示 Dock 图标；按当前模块设置启动剪贴板历史、监控和全局快捷键。点击「打开 iTools」或手动再次打开应用后正常显示主窗口及 Dock 图标。

关闭开关取消未来登录时的启动，当前进程继续运行。手动退出 iTools 后不会被启动组件反复拉起；如果开关仍开启，下次登录时仍会启动。

## 系统状态

| 显示 | 含义 |
| --- | --- |
| 未开启 | 系统未注册自启动 |
| 已开启 | 系统已允许登录时运行 |
| 等待系统允许 | 已注册，但仍需在系统设置中允许 iTools 后台运行；可关闭开关取消注册 |
| 暂时无法读取状态 | 组件不可用或系统查询失败；可刷新或重新安装完整应用 |

开关直接读取系统状态，不用本地布尔偏好假装注册成功。失败时显示原因并恢复真实状态；写入期间禁用重复操作。打开设置页或从系统设置返回 iTools 时刷新，也可手动刷新。

首次注册前，macOS 13 可能返回 `notFound`；先检查内置组件确实存在且完整，再将这种情况显示为「未开启」，避免把首次使用误报成组件故障。依据：[Apple DTS 对首次注册状态的说明](https://developer.apple.com/forums/thread/719862)。

macOS 13 及以上可点「管理系统登录项…」前往系统登录项设置。macOS 12 的 Service Management 登录组件由 iTools 内的开关管理，不在旧版「用户与群组」登录项列表中显示。

## 实现与维护

- 主应用和登录组件均为 Intel `x86_64`，部署目标为 macOS 12.0；构建脚本亦保留 arm64 / universal 选项。
- 内置组件位于 `iTools.app/Contents/Library/LoginItems/iTools Login.app`，标识符为 `app.itools.mac.login`。先签组件、再签完整应用。
- macOS 13+ 使用 `SMAppService.loginItem(identifier:)` 注册、注销及查询；macOS 12 使用 `SMLoginItemSetEnabled` 和 `SMCopyAllJobDictionaries`，只接受对应标识符且 `OnDemand` 为真的作业。
- 没有安装额外 LaunchAgent 文件，也不使用 shell 或 System Events 自动化修改登录项。
- 组件依据自身路径查找外层 `iTools.app` 并检查标识符、可执行文件。不要单独移动或删除内置组件。
- 主程序已经运行时，组件直接成功退出；否则用系统应用启动事件携带 `keyAELaunchedAsLogInItem`，指定当前安装路径并禁止替代为其他安装的进程。主程序识别该事件后后台启动。
- Finder 独立操作组件仍使用原入口，右键操作不需要主程序或自启动开关开启。

建议只保留一个正式安装路径。移动或替换应用时移动完整 `.app`；如系统显示旧组件状态，打开当前安装版并关闭、重新开启自启动。

## 验证方式

`scripts/test.sh` 包含初始化只读、外部状态刷新、启用/关闭、重复点击、待允许状态取消、失败回退与重试、系统未应用更改、macOS 12 作业判定及登录事件辨别。

常规 `--smoke-test` 仅渲染设置页的关闭和待允许状态，不更改任何系统自启动注册。

显式集成验证：

```sh
bash scripts/test-login-item.sh /Applications/iTools.app "$PWD/.build/login-item-installed"
```

先正常退出 iTools，再使用新的输出目录。该脚本检查登录事件的冷/热启动、菜单栏存在但主窗口隐藏、手动重新打开，以及真实内置组件不重复拉起应用。只在原始自启动状态关闭时短暂注册并立即注销，最后用新进程确认原始状态恢复；已有注册会保留。测试进程不启动剪贴板采样。

当前开发机可验证 macOS 13 的实际系统注册及启动事件。macOS 12 分支有编译、作业判定测试，但仍需在 Monterey 真机登录后验收；自动测试不会注销当前用户或重启电脑。

## 系统接口依据

- [Apple：SMAppService](https://developer.apple.com/documentation/servicemanagement/smappservice)
- [Apple：兼容版本的登录组件](https://developer.apple.com/library/archive/documentation/MacOSX/Conceptual/BPSystemStartup/Chapters/CreatingLoginItems.html)
- [Apple：登录启动事件标记](https://developer.apple.com/documentation/coreservices/keyaelaunchedasloginitem)
- [Apple：旧版登录项状态查询](https://developer.apple.com/documentation/servicemanagement/smcopyalljobdictionaries(_:))
