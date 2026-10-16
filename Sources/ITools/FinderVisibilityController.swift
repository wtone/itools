import AppKit
import Carbon
import IToolsCore

enum FinderVisibilityController {
    private static var busy = false

    /// Finder owns the live refresh, selection and scroll position. Its native
    /// shortcut must enter the normal foreground keyboard event stream.
    static func toggle(completion: @escaping (Error?) -> Void) {
        guard !busy else { completion(UserFacingError("正在切换隐藏文件显示，请稍候。")); return }
        guard Permissions.requireEventPosting(operation: "显示/不显示隐藏文件") else {
            completion(UserFacingError("需要允许 iTools 使用辅助功能后，才能切换访达的隐藏文件显示。")); return
        }
        guard let finder = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.finder").first,
              !finder.isTerminated else {
            completion(UserFacingError("请先打开一个访达文件夹窗口，再切换隐藏文件显示。")); return
        }
        busy = true
        func finish(_ error: Error? = nil) { busy = false; completion(error) }
        // Activation's return value is not an acknowledgement of foreground
        // ownership. Check the actual frontmost application before posting.
        if #available(macOS 14.0, *) {
            NSApp.yieldActivation(to: finder)
            finder.activate(from: .current, options: [])
        } else {
            finder.activate(options: [.activateIgnoringOtherApps])
        }
        let deadline = Date().addingTimeInterval(1)
        // Let the context menu finish dismissing before Finder receives a key.
        func sendWhenReady() {
            guard !finder.isTerminated else { finish(UserFacingError("访达已退出，本次切换已取消。")); return }
            guard NSWorkspace.shared.frontmostApplication?.processIdentifier == finder.processIdentifier else {
                if Date() < deadline {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.05, execute: sendWhenReady)
                } else {
                    finish(UserFacingError("请先将访达窗口置于前台后再试，或在访达中按 ⌘⇧.。"))
                }
                return
            }
            guard Permissions.requireEventPosting(operation: "显示/不显示隐藏文件"),
                  let source = CGEventSource(stateID: .privateState),
                  let down = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(kVK_ANSI_Period), keyDown: true),
                  let up = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(kVK_ANSI_Period), keyDown: false) else {
                finish(UserFacingError("无法发送访达切换快捷键，请检查 iTools 的辅助功能权限。")); return
            }
            down.flags = [.maskCommand, .maskShift]; up.flags = down.flags
            // PID-only events can reach Finder without invoking its shortcuts.
            // Post only after verifying Finder owns the keyboard; never retry
            // a posted, non-idempotent toggle.
            down.post(tap: .cghidEventTap); up.post(tap: .cghidEventTap)
            // Finder's live window state is independent of AppleShowAllFiles.
            // A saved preference cannot acknowledge this native command.
            finish()
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15, execute: sendWhenReady)
    }
}
