import Foundation

public enum VideoTrimRange {
    public struct InvalidRange: LocalizedError {
        public var errorDescription: String? { "请输入有效的秒数：开始时间不能小于 0，结束时间须大于开始时间，且不能超过视频时长。" }
    }
    public static func validate(start: String, end: String, duration: Double) throws -> Range<Double> {
        guard let start = Double(start.trimmingCharacters(in: .whitespacesAndNewlines)),
              let end = Double(end.trimmingCharacters(in: .whitespacesAndNewlines)),
              duration.isFinite, duration > 0, start.isFinite, end.isFinite,
              start >= 0, end > start, end <= duration else { throw InvalidRange() }
        return start..<end
    }
}
