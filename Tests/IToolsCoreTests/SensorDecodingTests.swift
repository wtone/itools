import XCTest
import SystemBridge

final class SensorDecodingTests: XCTestCase {
    private func decode(_ type: String, _ bytes: [UInt8]) -> Double {
        let code = type.utf8.reduce(UInt32(0)) { ($0 << 8) | UInt32($1) }
        return bytes.withUnsafeBufferPointer { it_sensor_decode(code, $0.baseAddress, UInt32(bytes.count)) }
    }
    func testIntelFixedPointTemperatureAndFan() {
        XCTAssertEqual(decode("sp78", [0x30, 0x80]), 48.5)
        XCTAssertEqual(decode("sp78", [0xff, 0x80]), -0.5)
        XCTAssertEqual(decode("fpe2", [0x1f, 0x40]), 2000)
    }
    func testAppleSiliconFloatAndStoppedFanAreRealValues() {
        let temperature: Float = 48.75
        let bytes = withUnsafeBytes(of: temperature) { Array($0) }
        XCTAssertEqual(decode("flt ", bytes), 48.75)
        XCTAssertEqual(decode("flt ", [0, 0, 0, 0]), 0)
        XCTAssertEqual(decode("fpe2", [0, 0]), 0)
    }
    func testMissingMalformedAndNonFiniteDataStayUnavailable() {
        for (type, bytes) in [("flt ", [UInt8(0)]), ("flt ", [0, 0]), ("sp78", [0]), ("fpe2", [0, 0, 0]), ("ui32", [0, 0, 0, 0])] {
            XCTAssertTrue(decode(type, bytes).isNaN)
        }
        for value in [Float.nan, Float.infinity, -Float.infinity] {
            XCTAssertTrue(decode("flt ", withUnsafeBytes(of: value) { Array($0) }).isNaN)
        }
        XCTAssertTrue(it_sensor_decode(0, nil, 0).isNaN)
    }
}
