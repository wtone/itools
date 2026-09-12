import AppKit
import Combine
import ServiceManagement

public enum LoginItemState: Equatable {
    case disabled, enabled, requiresApproval, unavailable
    // Pending approval is registered, so the user must also be able to turn it off.
    public var isRegistered: Bool { self == .enabled || self == .requiresApproval }
}

public protocol LoginItemManaging {
    func readState() -> LoginItemState
    func setEnabled(_ enabled: Bool) throws
}

public struct SystemLoginItem: LoginItemManaging {
    public init() {}
    public func readState() -> LoginItemState {
        if #available(macOS 13.0, *) {
            return Self.modernState(SMAppService.loginItem(identifier: LoginLaunch.helperID).status,
                                    helperAvailable: Self.helperAvailable)
        }
        // Apple's documented compatibility query for SMLoginItemSetEnabled on macOS 12.
        guard let jobs = SMCopyAllJobDictionaries(kSMDomainUserLaunchd)?.takeRetainedValue() as? [[String: Any]] else {
            return .unavailable
        }
        return Self.legacyState(jobs: jobs)
    }

    @available(macOS 13.0, *)
    public static func modernState(_ status: SMAppService.Status, helperAvailable: Bool) -> LoginItemState {
        switch status {
        case .enabled: return .enabled
        case .requiresApproval: return .requiresApproval
        case .notRegistered: return .disabled
        // Ventura also returns notFound before the first registration. A missing embedded helper is different.
        // Apple DTS: https://developer.apple.com/forums/thread/719862
        case .notFound: return helperAvailable ? .disabled : .unavailable
        @unknown default: return .unavailable
        }
    }
    private static var helperAvailable: Bool {
        let helperURL = Bundle.main.bundleURL.appendingPathComponent(LoginLaunch.helperPath)
        guard let helper = Bundle(url: helperURL), helper.bundleIdentifier == LoginLaunch.helperID,
              let executable = helper.executableURL, FileManager.default.isExecutableFile(atPath: executable.path) else { return false }
        return LoginLaunch.hostURL(for: helperURL) == Bundle.main.bundleURL.resolvingSymlinksInPath().standardizedFileURL
    }

    public static func legacyState(jobs: [[String: Any]]) -> LoginItemState {
        let job = jobs.first { $0["Label"] as? String == LoginLaunch.helperID }
        return job?["OnDemand"] as? Bool == true ? .enabled : .disabled
    }

    public func setEnabled(_ enabled: Bool) throws {
        if enabled {
            guard Self.helperAvailable else {
                throw NSError(domain: "iTools.LoginItem", code: 1, userInfo: [NSLocalizedDescriptionKey:
                    "找不到自启动组件，请将完整的 iTools.app 放到应用程序文件夹后重试。"])
            }
        }
        if #available(macOS 13.0, *) {
            let service = SMAppService.loginItem(identifier: LoginLaunch.helperID)
            if enabled { try service.register() } else { try service.unregister() }
        } else if !SMLoginItemSetEnabled(LoginLaunch.helperID as CFString, enabled) {
            throw NSError(domain: "iTools.LoginItem", code: 2, userInfo: [NSLocalizedDescriptionKey:
                "系统未能更改自启动设置，请确认应用位于应用程序文件夹后重试。"])
        }
    }

    @available(macOS 13.0, *)
    public static func openSettings() { SMAppService.openSystemSettingsLoginItems() }
}

/// The checkbox always reflects the OS; no UserDefaults flag can silently disagree with it.
public final class LoginItemController: ObservableObject {
    @Published public private(set) var state: LoginItemState
    @Published public private(set) var isUpdating = false
    @Published public private(set) var errorMessage: String?
    private let backend: LoginItemManaging

    public init(backend: LoginItemManaging = SystemLoginItem()) {
        self.backend = backend
        state = backend.readState()
        errorMessage = nil
    }
    public func refresh() {
        guard !isUpdating else { return }
        state = backend.readState()
        errorMessage = nil
    }
    public func setEnabled(_ enabled: Bool, completion: (() -> Void)? = nil) {
        guard !isUpdating else { return }
        state = backend.readState()
        errorMessage = nil
        guard enabled != state.isRegistered else { completion?(); return }
        isUpdating = true
        DispatchQueue.global(qos: .userInitiated).async { [self] in
            var failure: String?
            do { try backend.setEnabled(enabled) }
            catch { failure = error.localizedDescription }
            let actual = backend.readState()
            DispatchQueue.main.async { [self] in
                state = actual; isUpdating = false
                errorMessage = failure
                if failure == nil && actual.isRegistered != enabled {
                    errorMessage = "系统尚未应用此更改，请刷新状态后重试。"
                }
                completion?()
            }
        }
    }
}
