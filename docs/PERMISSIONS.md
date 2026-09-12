# 权限与固定签名

0.13.0 将授权检测、说明窗口和粘贴流程统一处理。截图/录制、辅助功能、模拟按键、麦克风与自动化各自检测，不用一个系统开关推断全部能力。

## 旧版授权为何看似开启却不能用

0.12.x 默认 `codesign --sign -`。已安装的 0.12.3 designated requirement 仅含 `cdhash`，重编译后会变化。系统中旧的授权条目不一定认可新二进制；同名、不同位置的 iTools 也容易混淆。0.13.0 默认使用持久的本地开发证书，身份要求绑定 `app.itools.mac` 与证书哈希。构建脚本不会在找不到证书时静默退回临时签名。

Apple 将 designated requirement 用于识别同一程序的不同版本，详见 [TN3127](https://developer.apple.com/documentation/technotes/tn3127-inside-code-signing-requirements) 与 [代码签名说明](https://developer.apple.com/library/archive/technotes/tn2206/)。本地自签身份不等于 Developer ID，不提供公证或公共发行信誉。

## 升级后首次恢复授权

1. 退出旧版，使用 `/Applications/iTools.app` 中的 0.13.0。
2. 系统设置 → 隐私与安全性 → 辅助功能：移除旧 iTools 条目，点击 `+`，重新添加 `/Applications/iTools.app` 并开启。
3. 回到 iTools 的授权窗口重新检测。若尚未生效，用「重新打开 iTools」重启；正在录制/处理文件时会拒绝重启。
4. 屏幕录制、麦克风按实际需要授权。屏幕录制变更可能需要重启。切换外观等操作涉及的 System Events/Finder 控制属于单独的「自动化」权限。
5. 点击目标输入框后再呼出剪贴板执行粘贴；窗口布局同样先点选目标窗口。授权返回不自动重复粘贴、录制或系统操作。

不自动重置 TCC、改写权限数据库或勾选系统授权，不建议批量清空其他应用的权限。

## 本机签名

- `python3 scripts/setup-local-signing.py` 显式创建独立本地身份。证书和私钥放在当前用户 `~/Library/Application Support/iTools Development/Signing` 的专用加密钥匙串，目录与密码文件限制访问，不进入仓库/安装包。证书仅在当前用户域用于代码签名信任，不添加系统根信任或授予隐私权限。
- `scripts/sign.py` 复用这份身份；签名期间将专用钥匙串临时追加到搜索列表，结束后移除该临时项，保留已有顺序和其他进程新增项。
- 正式发行指定 `SIGN_IDENTITY`，可指定 `SIGN_KEYCHAIN`。更换签名身份需要重新评估授权迁移。
- 只有明确设置 `ALLOW_ADHOC_SIGNING=1` 或 `SIGN_IDENTITY=-` 才使用临时签名，适合一次性测试，不用于持续安装更新。
- 持久保存这份私钥；丢失或重新生成将成为新身份。初次自签迁移仍需用户重新授权，不能继承旧 `cdhash` 的许可。

## 检测和执行

`AXIsProcessTrusted` 检查当前进程的窗口控制，`CGPreflightPostEventAccess` 检查事件发送，`CGPreflightScreenCaptureAccess` 检查屏幕，`AVCaptureDevice.authorizationStatus` 检查录音。首次系统请求只在用户操作时发生。独立授权窗口使用 modalPanel 层级、复用一个实例；打开系统设置时隐藏，不反向激活主窗口。

粘贴事务检查目标存活、前台 PID、修饰键释放和剪贴板 changeCount。两秒内等待目标就绪；只有成功构造并提交按键后才移除队列首项。按键提交不等于目标应用已插入内容，目标输入框仍需支持粘贴。窗口控制使用前台/先前目标，focused window 缺失时尝试 main window，系统全屏或不支持标准 AX 尺寸的窗口会单独说明。

`--permission-check` 从实际启动的应用只读输出授权 JSON 并退出，不申请权限，不读取系统剪贴板或控制其他应用；需先正常退出已运行实例，再经 LaunchServices 打开以核对正确安装路径。
