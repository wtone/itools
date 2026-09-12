import XCTest
import AppKit
import Carbon
import ServiceManagement
@testable import IToolsCore

final class LoginItemTests: XCTestCase {
    func testFirstRegistrationIsOffButMissingHelperIsUnavailable() {
        if #available(macOS 13.0, *) {
            XCTAssertEqual(SystemLoginItem.modernState(.notFound, helperAvailable: true), .disabled)
            XCTAssertEqual(SystemLoginItem.modernState(.notFound, helperAvailable: false), .unavailable)
            XCTAssertEqual(SystemLoginItem.modernState(.notRegistered, helperAvailable: true), .disabled)
            XCTAssertEqual(SystemLoginItem.modernState(.enabled, helperAvailable: true), .enabled)
            XCTAssertEqual(SystemLoginItem.modernState(.requiresApproval, helperAvailable: true), .requiresApproval)
        }
    }
    func testLegacyStatusChecksEnabledJobAndExactIdentifier() {
        XCTAssertEqual(SystemLoginItem.legacyState(jobs: []), .disabled)
        XCTAssertEqual(SystemLoginItem.legacyState(jobs: [["Label": "other.app", "OnDemand": true]]), .disabled)
        XCTAssertEqual(SystemLoginItem.legacyState(jobs: [["Label": LoginLaunch.helperID, "OnDemand": true]]), .enabled)
        for job: [String: Any] in [["Label": LoginLaunch.helperID], ["Label": LoginLaunch.helperID, "OnDemand": false]] {
            XCTAssertEqual(SystemLoginItem.legacyState(jobs: [job]), .disabled)
        }
    }
    final class Backend: LoginItemManaging {
        var state: LoginItemState = .disabled
        var calls: [Bool] = []
        var result: LoginItemState?
        var error: Error?
        func readState() -> LoginItemState { state }
        func setEnabled(_ enabled: Bool) throws {
            calls.append(enabled)
            if let error = error { throw error }
            state = result ?? (enabled ? .enabled : .disabled)
        }
    }
    func testInitialReadAndExternalChangesNeverRegisterAutomatically() {
        let backend = Backend(), controller = LoginItemController(backend: Backend())
        XCTAssertEqual(controller.state, .disabled)
        let observed = LoginItemController(backend: backend)
        backend.state = .enabled; observed.refresh()
        XCTAssertEqual(observed.state, .enabled)
        backend.state = .requiresApproval; observed.refresh()
        XCTAssertEqual(observed.state, .requiresApproval)
        XCTAssertTrue(observed.state.isRegistered)
        XCTAssertTrue(backend.calls.isEmpty)
    }
    func testEnableDisableAndDuplicateClicks() {
        let backend = Backend(), done = expectation(description: "toggle")
        let controller = LoginItemController(backend: backend)
        controller.setEnabled(true) {
            XCTAssertEqual(controller.state, .enabled)
            XCTAssertNil(controller.errorMessage)
            controller.setEnabled(false) {
                XCTAssertEqual(controller.state, .disabled)
                XCTAssertEqual(backend.calls, [true, false])
                done.fulfill()
            }
        }
        controller.setEnabled(true) // Ignored while the request is outstanding.
        wait(for: [done], timeout: 3)
    }
    func testPermissionPendingCanBeCancelled() {
        let backend = Backend(); backend.result = .requiresApproval
        let controller = LoginItemController(backend: backend), done = expectation(description: "pending")
        controller.setEnabled(true) {
            XCTAssertEqual(controller.state, .requiresApproval)
            XCTAssertNil(controller.errorMessage)
            backend.result = nil
            controller.setEnabled(false) {
                XCTAssertEqual(controller.state, .disabled)
                XCTAssertEqual(backend.calls, [true, false])
                done.fulfill()
            }
        }
        wait(for: [done], timeout: 3)
    }
    func testFailureKeepsActualStateAndAllowsRetry() {
        let backend = Backend(); backend.state = .enabled
        backend.error = NSError(domain: "test", code: 1, userInfo: [NSLocalizedDescriptionKey: "Denied"])
        let controller = LoginItemController(backend: backend), done = expectation(description: "failure")
        controller.setEnabled(false) {
            XCTAssertEqual(controller.state, .enabled)
            XCTAssertEqual(controller.errorMessage, "Denied")
            XCTAssertFalse(controller.isUpdating)
            backend.error = nil
            controller.setEnabled(false) {
                XCTAssertEqual(controller.state, .disabled)
                XCTAssertNil(controller.errorMessage)
                done.fulfill()
            }
        }
        wait(for: [done], timeout: 3)
    }
    func testUnappliedChangeIsNotReportedAsSuccess() {
        let backend = Backend(); backend.result = .disabled
        let controller = LoginItemController(backend: backend), done = expectation(description: "unchanged")
        controller.setEnabled(true) {
            XCTAssertEqual(controller.state, .disabled)
            XCTAssertNotNil(controller.errorMessage)
            done.fulfill()
        }
        wait(for: [done], timeout: 3)
    }
    func testOnlyLoginOpenEventSuppressesWindow() {
        let configuration = LoginLaunch.configuration()
        let event = configuration.appleEvent!
        XCTAssertTrue(LoginLaunch.isLoginEvent(event))
        XCTAssertFalse(configuration.activates)
        XCTAssertFalse(configuration.allowsRunningApplicationSubstitution)
        XCTAssertFalse(LoginLaunch.isLoginEvent(nil))
        event.setParam(NSAppleEventDescriptor(typeCode: OSType(keyAELaunchedAsLogInItem)), forKeyword: AEKeyword(keyAEPropData))
        XCTAssertTrue(LoginLaunch.isLoginEvent(event))
        event.setParam(NSAppleEventDescriptor(enumCode: OSType(keyAELaunchedAsServiceItem)), forKeyword: AEKeyword(keyAEPropData))
        XCTAssertFalse(LoginLaunch.isLoginEvent(event))
        event.setParam(NSAppleEventDescriptor(string: "lgit"), forKeyword: AEKeyword(keyAEPropData))
        XCTAssertFalse(LoginLaunch.isLoginEvent(event))
        let reopen = NSAppleEventDescriptor(eventClass: AEEventClass(kCoreEventClass),
            eventID: AEEventID(kAEReopenApplication), targetDescriptor: nil,
            returnID: AEReturnID(kAutoGenerateReturnID), transactionID: AETransactionID(kAnyTransactionID))
        reopen.setParam(NSAppleEventDescriptor(enumCode: OSType(keyAELaunchedAsLogInItem)), forKeyword: AEKeyword(keyAEPropData))
        XCTAssertFalse(LoginLaunch.isLoginEvent(reopen))
    }
}
