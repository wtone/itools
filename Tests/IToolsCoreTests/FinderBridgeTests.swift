import XCTest
@testable import IToolsCore

final class FinderBridgeTests: XCTestCase {
    func testChosenApplicationSurvivesMenuAndDirectDelivery() {
        let file = URL(fileURLWithPath: "/tmp/中文 & name.txt")
        for app in ["system-default", "/Applications/文本 编辑.app"] {
            let menu = FinderMenuRequests.makeURL(action: "open-with", paths: [file], application: app)!
            let direct = FinderDirectRequest(FinderDirectRequest.makeURL(from: menu)!)!
            XCTAssertEqual(direct.application, app); XCTAssertEqual(direct.paths, [file])
        }
        XCTAssertNil(FinderMenuRequests.makeURL(action: "delete", paths: [file], application: "system-default"))
        for invalid in ["/bin/sh", "../App.app", "https://example.com/X.app", "/tmp/a\0.app"] {
            XCTAssertNil(FinderMenuRequests.makeURL(action: "open-with", paths: [file], application: invalid))
        }
        let base = FinderMenuRequests.makeURL(action: "open-with", paths: [file], application: "system-default")!
        let direct = FinderDirectRequest.makeURL(from: base)!
        XCTAssertNil(FinderDirectRequest(URL(string: direct.absoluteString + "&application=/Applications/Other.app")!))
    }
    func testApplicationListRequiresSupportForEverySelectionAndKeepsSystemOrder() {
        let paths = [URL(fileURLWithPath: "/tmp/a.txt"), URL(fileURLWithPath: "/tmp/b.png")]
        let apps = ["A", "B", "C"].map { URL(fileURLWithPath: "/Applications/\($0).app") }
        let common = FinderApplications.common(for: paths) { $0 == paths[0] ? [apps[1], apps[0], apps[1], apps[2]] : [apps[2], apps[1]] }
        XCTAssertEqual(common, [apps[1], apps[2]])
        XCTAssertTrue(FinderApplications.common(for: paths) { $0 == paths[0] ? [apps[0]] : [apps[1]] }.isEmpty)
        XCTAssertTrue(FinderApplications.common(for: []) { _ in apps }.isEmpty)
    }
    func testDirectRequestsRoundTripEveryActionWithoutPublicScheme() {
        let paths = [URL(fileURLWithPath: "/tmp/中文 空格 &action=delete #?.txt")]
        for action in FinderActions.all {
            let menu = FinderMenuRequests.makeURL(action: action.id, paths: paths)!
            let token = UUID()
            let direct = FinderDirectRequest.makeURL(from: menu, id: token)!
            let decoded = FinderDirectRequest(direct)!
            XCTAssertEqual(decoded.id, token); XCTAssertEqual(decoded.action, action.id)
            XCTAssertEqual(decoded.paths, paths); XCTAssertNotEqual(direct.scheme, menu.scheme)
            XCTAssertNil(FinderDirectRequest(menu))
        }
    }
    func testDirectRequestRejectsAmbiguousAndUnboundedInput() {
        let token = UUID().uuidString
        let base = "itools-finder-action://finder?action=new-txt&request=\(token)"
        for value in [base, base + "&path=relative", base + "&path=/tmp/%00evil",
                      base + "&path=/tmp/x&action=delete", base + "&path=/tmp/x&extra=1",
                      base + "&path=/tmp/x#fragment", base + "&path=/tmp/x&request=\(token)",
                      base + String(repeating: "&path=/tmp/x", count: 201),
                      base + "&path=/tmp/" + String(repeating: "x", count: 33000)] {
            XCTAssertNil(FinderDirectRequest(URL(string: value)!))
        }
        XCTAssertNil(FinderDirectRequest(URL(string: base.replacingOccurrences(of: "new-txt", with: "run-shell") + "&path=/tmp")!))
    }
    func testEachClickGetsItsOwnIdentity() {
        let menu = FinderMenuRequests.makeURL(action: "new-txt", paths: [URL(fileURLWithPath: "/tmp")])!
        let first = FinderDirectRequest(FinderDirectRequest.makeURL(from: menu)!)!
        let second = FinderDirectRequest(FinderDirectRequest.makeURL(from: menu)!)!
        XCTAssertNotEqual(first.id, second.id)
    }
    func testWorkerFollowsContainingApplicationWhenMoved() {
        let app = URL(fileURLWithPath: "/Applications/移动后的工具.app", isDirectory: true)
        XCTAssertEqual(FinderHostLocation.worker(in: app).path, app.path + "/Contents/Helpers/iTools Finder Actions.app")
    }
    func testRoutingNeedsOnlyTagNotRepresentedObject() {
        let store = FinderMenuRequests(); store.beginMenu()
        let url = FinderMenuRequests.makeURL(action: "copy-path", paths: [URL(fileURLWithPath: "/tmp/中文 & name.txt")])!
        let tag = store.insert(url)
        // Only the integer tag needs to survive Finder's cross-process menu copy.
        XCTAssertEqual(store.request(tag: tag), url)
        XCTAssertNil(store.request(tag: 0)); XCTAssertNil(store.request(tag: -1))
    }
    func testNewMenuCannotRetargetOldClick() {
        let store = FinderMenuRequests(); store.beginMenu()
        let old = URL(string: "itools://finder?action=copy-path&path=/tmp/one")!
        let current = URL(string: "itools://finder?action=delete&path=/tmp/two")!
        let oldTag = store.insert(old); store.beginMenu(); let currentTag = store.insert(current)
        XCTAssertNotEqual(oldTag, currentTag)
        XCTAssertEqual(store.request(tag: oldTag), old); XCTAssertEqual(store.request(tag: currentTag), current)
        for _ in 0..<4 { store.beginMenu() }
        XCTAssertNil(store.request(tag: oldTag)); XCTAssertNil(store.request(tag: currentTag))
    }
    func testRoutesEncodePathsWithoutTreatingThemAsParameters() {
        let paths = ["/tmp/空 格 &action=delete #?.txt", "/tmp/百分号%文件.txt"]
        for action in FinderActions.all {
            let url = FinderMenuRequests.makeURL(action: action.id, paths: paths.map { URL(fileURLWithPath: $0) })!
            let items = URLComponents(url: url, resolvingAgainstBaseURL: false)!.queryItems!
            XCTAssertEqual(items.filter { $0.name == "action" }.compactMap(\.value), [action.id])
            XCTAssertEqual(items.filter { $0.name == "path" }.compactMap(\.value), paths)
        }
    }
    func testRejectUnknownEmptyOversizedAndNonFileRequests() {
        XCTAssertNil(FinderMenuRequests.makeURL(action: "execute-shell", paths: [URL(fileURLWithPath: "/tmp/a")]))
        XCTAssertNil(FinderMenuRequests.makeURL(action: "copy", paths: []))
        XCTAssertNil(FinderMenuRequests.makeURL(action: "copy", paths: [URL(string: "https://example.com")!]))
        XCTAssertNil(FinderMenuRequests.makeURL(action: "copy", paths: Array(repeating: URL(fileURLWithPath: "/tmp/a"), count: 201)))
        XCTAssertNil(FinderMenuRequests.makeURL(action: "copy", paths: [URL(fileURLWithPath: "/tmp/" + String(repeating: "字", count: 5000))]))
    }
    func testMovedOrRenamedBundleUsesItsEnclosingApp() {
        for path in ["/Applications/iTools.app", "/Applications/iTools 测试.app", "/Users/test/Applications/My Utilities/iTools.app"] {
            let app = URL(fileURLWithPath: path, isDirectory: true)
            let ext = app.appendingPathComponent("Contents/PlugIns/IToolsFinder.appex")
            XCTAssertEqual(FinderHostLocation.containingApplication(extensionURL: ext), app)
            XCTAssertEqual(FinderHostLocation.resolve(extensionURL: ext, fallbacks: [URL(fileURLWithPath: "/old/iTools.app")], valid: { $0 == app }), app)
        }
    }
    func testMissingOldPathFallsBackButNeverChoosesInvalidApp() {
        let stale = URL(fileURLWithPath: "/old/iTools.app/Contents/PlugIns/IToolsFinder.appex")
        let installed = URL(fileURLWithPath: "/Applications/iTools.app")
        XCTAssertEqual(FinderHostLocation.resolve(extensionURL: stale, fallbacks: [installed], valid: { $0 == installed }), installed)
        XCTAssertNil(FinderHostLocation.resolve(extensionURL: stale, fallbacks: [installed], valid: { _ in false }))
        XCTAssertNil(FinderHostLocation.containingApplication(extensionURL: URL(fileURLWithPath: "/tmp/not-an-app/IToolsFinder.appex")))
    }
    func testSandboxLaunchDoesNotRequireReadingHostOrWorker() {
        let app = URL(fileURLWithPath: "/Users/test/projects/中文 工具/dist/iTools.app", isDirectory: true)
        let ext = app.appendingPathComponent("Contents/PlugIns/IToolsFinder.appex")
        // A denied filesystem preflight is not evidence that the host is missing.
        XCTAssertNil(FinderHostLocation.resolve(extensionURL: ext, fallbacks: [], valid: { _ in false }))
        XCTAssertEqual(FinderHostLocation.launchCandidates(extensionURL: ext, registeredHost: nil), [app])
        XCTAssertEqual(FinderHostLocation.launchCandidates(extensionURL: ext, registeredHost: app), [app])
        let installed = URL(fileURLWithPath: "/Applications/iTools.app", isDirectory: true)
        XCTAssertEqual(FinderHostLocation.launchCandidates(extensionURL: ext, registeredHost: installed), [app, installed])
        XCTAssertEqual(FinderHostLocation.launchCandidates(extensionURL: URL(fileURLWithPath: "/tmp/invalid.appex"), registeredHost: installed), [installed])
        XCTAssertTrue(FinderHostLocation.launchCandidates(extensionURL: URL(fileURLWithPath: "/tmp/invalid.appex"), registeredHost: URL(string: "https://example.com/iTools.app")!).isEmpty)
    }
    func testLaunchFailureIsDisplayOnlyAndStrictlyParsed() {
        let message = "无法启动：中文 空格 &action=delete #?"
        let url = FinderLaunchFailure.makeURL(message)!
        XCTAssertEqual(FinderLaunchFailure.message(in: url), message)
        XCTAssertNil(FinderDirectRequest(url))
        XCTAssertNil(FinderLaunchFailure.makeURL(""))
        XCTAssertNil(FinderLaunchFailure.makeURL(String(repeating: "字", count: 1400)))
        for value in [url.absoluteString + "&action=delete", url.absoluteString + "&message=extra",
                      url.absoluteString + "#fragment", "itools://finder-error?message=",
                      "itools://finder-error/extra?message=error", "itools://finder?action=copy-path&path=/tmp"] {
            XCTAssertNil(FinderLaunchFailure.message(in: URL(string: value)!))
        }
    }
}
