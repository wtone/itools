import XCTest
@testable import IToolsCore

final class MenuBarTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suite: String!
    override func setUp() {
        suite = "itools.tests.menubar." + UUID().uuidString
        defaults = UserDefaults(suiteName: suite)!
    }
    override func tearDown() { defaults.removePersistentDomain(forName: suite) }
    func testOldUserStartsWithCPUOnlyAndAllOffSurvivesRelaunch() {
        let settings = MenuBarPreferences(defaults: defaults)
        XCTAssertEqual(settings.enabledMetrics, [.cpu])
        settings.set(.cpu, enabled: false)
        XCTAssertTrue(MenuBarPreferences(defaults: defaults).enabledMetrics.isEmpty)
    }
    func testSwitchesPersistIndependentlyWithoutChangingMonitorSetting() {
        defaults.set(false, forKey: "monitor.enabled")
        let settings = MenuBarPreferences(defaults: defaults)
        settings.set(.memory, enabled: true)
        settings.set(.gpu, enabled: true)
        settings.set(.network, enabled: true)
        settings.set(.gpu, enabled: false)
        XCTAssertEqual(MenuBarPreferences(defaults: defaults).enabledMetrics, [.cpu, .memory, .network])
        XCTAssertFalse(defaults.bool(forKey: "monitor.enabled"))
    }
    func testUnknownFutureMetricIsIgnoredWithoutResettingSelection() {
        defaults.set(["memory", "futureMetric"], forKey: MenuBarPreferences.key)
        XCTAssertEqual(MenuBarPreferences(defaults: defaults).enabledMetrics, [.memory])
    }
    func testMissingReadingDiffersFromValidZero() {
        XCTAssertEqual(MetricFormatting.percent(nil), "—")
        XCTAssertEqual(MetricFormatting.percent(.nan), "—")
        XCTAssertEqual(MetricFormatting.percent(0), "0%")
        XCTAssertEqual(MetricFormatting.rate(nil), "—")
        XCTAssertEqual(MetricFormatting.rate(0), "0 B/s")
        XCTAssertEqual(MetricFormatting.rate(.infinity), "—")
        XCTAssertEqual(MetricFormatting.rate(-1), "—")
    }
    func testRatesScaleAndDiskShowsUsedRatherThanFreeSpace() {
        XCTAssertEqual(MetricFormatting.rate(1_500), "1.5 KB/s")
        XCTAssertEqual(MetricFormatting.rate(18_000), "18 KB/s")
        XCTAssertEqual(MetricFormatting.rate(15_000_000), "15 MB/s")
        XCTAssertEqual(MetricFormatting.diskPercent(free: 25, total: 100), 75)
        XCTAssertNil(MetricFormatting.diskPercent(free: 1, total: 0))
        XCTAssertNil(MetricFormatting.diskPercent(free: 101, total: 100))
    }
    func testGPUReadsDriverPercentageWithoutInventingMissingData() {
        XCTAssertEqual(GPUStatistics.utilization(["Device Utilization %": 7, "GPU Activity(%)": 0]), 7)
        XCTAssertEqual(GPUStatistics.utilization(["GPU Activity(%)": 0]), 0)
        XCTAssertEqual(GPUStatistics.utilization(["Device Utilization % at cur p-state": 12]), 12)
        XCTAssertNil(GPUStatistics.utilization(["bufferSwapCount": 8]))
        XCTAssertNil(GPUStatistics.utilization(["Device Utilization %": .nan]))
        XCTAssertNil(GPUStatistics.utilization(["Device Utilization %": 101]))
    }
}
