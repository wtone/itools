import XCTest
@testable import IToolsCore

final class ScrollingStitcherTests: XCTestCase {
    func sidebarFrame(offset: Int, noise: Int = 0) -> ScrollFrame {
        let width = 320, height = 240, header = 30
        var bytes = [UInt8](repeating: 255, count: width * height * 4)
        for y in 0..<height { for x in 0..<width {
            let source = y < header ? y : x < 90 ? y + 20_000 : offset + y - header
            let p = (y * width + x) * 4
            // A stationary sidebar changes every row; the right content scrolls independently.
            for channel in 0..<3 {
                let value = (source * (channel * 6 + 7) + x * (channel * 4 + 3)) % 220 + 16
                bytes[p+channel] = UInt8(max(0, min(255, value + noise)))
            }
        } }
        return ScrollFrame(width: width, height: height, rgba: bytes)
    }
    func testFixedSidebarDoesNotPreventAppendingScrolledContent() {
        let stitcher = ScrollingStitcher()
        XCTAssertEqual(stitcher.append(sidebarFrame(offset: 0)), .added(240))
        XCTAssertEqual(stitcher.append(sidebarFrame(offset: 65)), .added(65))
        XCTAssertEqual(stitcher.append(sidebarFrame(offset: 130)), .added(65))
        XCTAssertEqual(stitcher.height, 370)
        XCTAssertEqual(stitcher.count, 3)
        guard stitcher.height == 370 else { return }
        // The new content's final rows must actually be in the output.
        let expected = sidebarFrame(offset: 130)
        for y in 0..<50 {
            let output = ((stitcher.height - 50 + y) * expected.width + 210) * 4
            let input = ((expected.height - 50 + y) * expected.width + 210) * 4
            XCTAssertEqual(Array(stitcher.output!.rgba[output..<output+4]), Array(expected.rgba[input..<input+4]))
        }
    }
    func testSmallRenderingDifferencesDoNotRejectTheSameContent() {
        let stitcher = ScrollingStitcher()
        XCTAssertEqual(stitcher.append(sidebarFrame(offset: 0)), .added(240))
        XCTAssertEqual(stitcher.append(sidebarFrame(offset: 65, noise: 1)), .added(65))
        XCTAssertEqual(stitcher.append(sidebarFrame(offset: 130, noise: -1)), .added(65))
        XCTAssertEqual(stitcher.height, 370)
    }
    func testUnmatchedFrameCanRecoverWithoutReplacingTheLastBaseline() {
        let stitcher = ScrollingStitcher()
        let first = sidebarFrame(offset: 0)
        _ = stitcher.append(first)
        var changed = first.rgba
        for index in stride(from: 0, to: changed.count, by: 4) { changed[index] = 20; changed[index+1] = 20; changed[index+2] = 20 }
        XCTAssertEqual(stitcher.append(ScrollFrame(width: first.width, height: first.height, rgba: changed)), .unmatched)
        XCTAssertEqual(stitcher.append(sidebarFrame(offset: 65)), .added(65))
        XCTAssertEqual(stitcher.count, 2)
    }
    func frame(offset: Int, header: Int = 0, footer: Int = 0, edges: Bool = false) -> ScrollFrame {
        let width = 96, height = 200
        var bytes = [UInt8](repeating: 255, count: width * height * 4)
        for y in 0..<height { for x in 0..<width {
            let source = y < header ? y : y >= height-footer ? 50_000+y : offset+y-header
            let p = (y * width + x) * 4
            bytes[p] = UInt8(truncatingIfNeeded: source * 29 + x * 11)
            bytes[p+1] = UInt8(truncatingIfNeeded: source * 7 + x * 3)
            bytes[p+2] = UInt8(truncatingIfNeeded: source / 3 + x * 13)
            if edges && x >= width - 4 { bytes[p] = UInt8(truncatingIfNeeded: offset) }
        } }
        return ScrollFrame(width: width, height: height, rgba: bytes)
    }
    func testIncrementalOverlapAndPixels() {
        let stitcher = ScrollingStitcher()
        XCTAssertEqual(stitcher.append(frame(offset: 0)), .added(200))
        XCTAssertEqual(stitcher.append(frame(offset: 70)), .added(70))
        XCTAssertEqual(stitcher.append(frame(offset: 140)), .added(70))
        XCTAssertEqual(stitcher.height, 340)
        let tail = frame(offset: 140).rgba.suffix(70 * 96 * 4)
        XCTAssertEqual(Array(stitcher.output!.rgba.suffix(tail.count)), Array(tail))
        XCTAssertEqual(stitcher.append(frame(offset: 140)), .unchanged)
        XCTAssertEqual(stitcher.append(frame(offset: 70)), .reversed)
        XCTAssertEqual(stitcher.count, 3)
    }
    func testFixedHeaderFooterAndScrollbar() {
        let stitcher = ScrollingStitcher()
        XCTAssertEqual(stitcher.append(frame(offset: 0, header: 24, footer: 12, edges: true)), .added(200))
        XCTAssertEqual(stitcher.append(frame(offset: 65, header: 24, footer: 12, edges: true)), .added(65))
        XCTAssertEqual(stitcher.height, 265)
        // Header and footer appear once; suffix is the current footer.
        XCTAssertEqual(Array(stitcher.output!.rgba.prefix(24*96*4)), Array(frame(offset: 0, header: 24, footer: 12, edges: true).rgba.prefix(24*96*4)))
        XCTAssertEqual(Array(stitcher.output!.rgba.suffix(12*96*4)), Array(frame(offset: 65, header: 24, footer: 12, edges: true).rgba.suffix(12*96*4)))
    }
    func testUnmatchedAndLimitsPreserveLastGoodImage() {
        let stitcher = ScrollingStitcher(pixelLimit: 96 * 230)
        _ = stitcher.append(frame(offset: 0))
        XCTAssertEqual(stitcher.append(frame(offset: 70)), .limit)
        XCTAssertEqual(stitcher.append(frame(offset: 500)), .unmatched)
        XCTAssertEqual(stitcher.height, 200)
        XCTAssertEqual(stitcher.output!.rgba, frame(offset: 0).rgba)
        XCTAssertEqual(stitcher.append(ScrollFrame(width: 2, height: 2, rgba: [])), .unmatched)
    }
}
