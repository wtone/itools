# 菜单栏指标显示范围

目标是在系统状态页选择全部菜单栏显示，或只在指定屏幕显示，并随扩展屏变化恢复可见入口。本期完整交付设置、持久化、原生菜单栏与屏幕变化处理，不增加多套指标数据或每屏独立指标配置。

## 行为与验收

- 现有用户默认仍是「仅一个屏幕 → 跟随系统主显示器」，保留指标选择、内部排序、原生位置。
- 「所有屏幕」复用已验证的原生单屏 NSStatusItem，在每块屏幕呈现同一组指标，覆盖具有系统菜单栏的显示器；镜像显示或系统未在副屏提供菜单栏时，不额外绘制覆盖窗口。
- 「仅一个屏幕」可以跟随主屏，或选当前接入的具体显示器。保存 Core Graphics 显示器 UUID，不以显示器列表序号或当前焦点为身份。
- 指定屏幕断开时临时回退到当前系统主屏；保留原 UUID。重新接入后恢复到指定屏幕。合盖仅剩外屏也使用当前可用屏幕。完全没有屏幕时等待下一次配置变化。
- 设置页监听 NSApplication.didChangeScreenParametersNotification 更新选项。执行层每次从 NSScreen.screens 读取当前拓扑，沿用现有通知、工作区观察与刷新定时器，不依赖 UI 是否打开。
- 范围切换即时生效；所有指标全关时出现的工具箱入口使用同一显示范围。普通单屏、监控暂停、指标开关与内部排序不改变。

## 实现与兼容

偏好的唯一来源是 MenuBarPreferences.displaySelection；UserDefaults 新增 menuBar.displayMode / displayID / displayName。displayName 仅为断开时的提示标签，不参与身份匹配。热插拔解析不改写保存值，不引入数据库或迁移脚本。

单屏沿用已检查 ABI 的限定屏幕实现。所有屏幕由根 MenuBarMonitor 按当前显示器 UUID 增删副屏原生项，每项复用 MenuBarMonitor 和同一 MonitorService / MenuBarPreferences，不重新采样、不独立保存指标与排序。根状态项始终复用，范围切换只增删副屏呈现，指定单屏变化仅重新限定根项；移除副屏时停止观察器、计时器与鼠标处理器，保留该屏原生插入位置。没有新建自绘覆盖菜单栏或修改其他应用。

选择这条实现是因为本机原生验证发现：已限定状态项的解除限制及其后的普通副本恢复不可靠，普通公开工厂产生的副屏窗口也可能不在 WindowServer 可见列表中。复用逐屏限定路径，实际验证每个可见原生窗口的位置和数量。普通数值刷新与开关指标不重建根项。

macOS 版本不支持现有单屏限定兼容层时，多屏单屏模式沿用隐藏入口的保护行为，并在设置页说明可改用「所有屏幕」或从 Dock / 快捷键进入；所有屏幕模式则保留一个标准 AppKit 状态项，不再创建逐屏副本。这一旧系统回退不视为已实测。菜单栏显示仍受 macOS 菜单栏和 Spaces 配置约束，不修改用户的系统设置。

## 验证

```bash
cd /Users/wtone/www/itools
./scripts/test.sh
swift build --disable-sandbox --cache-path .build/cache --scratch-path .build --configuration debug --arch arm64
ITOOLS_SMOKE_OUTPUT="$PWD/.build/menu-display-native" \
  .build/arm64-apple-macosx/debug/ITools --smoke-test --menu-bar-display-check --menu-bar-display-mode-check
```

核心测试覆盖默认兼容、所有屏幕增减、指定屏幕断开与重接、主屏变更、合盖拓扑、重启和模式切换保留目标、配置不污染指标与原生位置、测试不保存真实设置、损坏值回退。

原生自检使用本进程的实际 WindowServer 窗口，验证 all / 每块单屏 / 未连接目标回退的反复切换、入口数量和位置，以及原有固定宽度、内部排序、相邻项与正常采样回归。它不改变系统主屏、Spaces 或物理设备；模拟断开 UUID 与配置通知不等同于真实拔线验收。实测结果与未覆盖条件记录在 VALIDATION.md。

## 交付和回退

仅涉及 itools 仓库，无跨仓依赖或数据库执行。正常构建使用 scripts/build.sh 及已有签名方式。回退为上一版应用时，新增 UserDefaults 键被旧版忽略，旧版恢复仅主屏显示；指标开关、排序和原生位置格式兼容。需要恢复默认显示策略时在设置页选择「仅一个屏幕 → 跟随系统主显示器」，不删除用户其他设置。

参考：[Apple NSScreen.screens](https://developer.apple.com/documentation/appkit/nsscreen/screens)、[显示配置变化通知](https://developer.apple.com/documentation/appkit/nsapplication/didchangescreenparametersnotification)。
