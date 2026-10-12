import Foundation

/// Native-resolution, top-to-bottom RGBA rows, independent of AppKit and screen capture.
public struct ScrollFrame {
    public let width: Int
    public let height: Int
    public let rgba: [UInt8]
    public init(width: Int, height: Int, rgba: [UInt8]) {
        self.width = width; self.height = height; self.rgba = rgba
    }
    public var valid: Bool { width >= 16 && height >= 32 && width <= 16_384 && height <= 16_384 && rgba.count == width * height * 4 }
}

public final class ScrollingStitcher {
    public enum Result: Equatable { case added(Int), unchanged, unmatched, reversed, limit }
    public private(set) var height = 0
    public private(set) var count = 0
    public private(set) var last: ScrollFrame?
    private var rows: [UInt8] = []
    private let pixelLimit: Int
    public init(pixelLimit: Int = 80_000_000) { self.pixelLimit = pixelLimit }
    public var width: Int { last?.width ?? 0 }
    public var output: ScrollFrame? { last.map { ScrollFrame(width: $0.width, height: height, rgba: rows) } }

    public func append(_ frame: ScrollFrame) -> Result {
        guard frame.valid else { return .unmatched }
        guard let previous = last else {
            guard frame.width * frame.height <= pixelLimit else { return .limit }
            rows = frame.rgba; last = frame; height = frame.height; count = 1
            return .added(frame.height)
        }
        guard previous.width == frame.width, previous.height == frame.height else { return .unmatched }
        if previous.rgba == frame.rgba { return .unchanged }
        let old = bands(previous), new = bands(frame)
        var votes: [Int: Int] = [:]
        var moving: [Int] = []
        let maxShift = frame.height * 9 / 10
        for index in old.indices {
            let a = old[index].rows, b = new[index].rows
            // A fixed sidebar must neither vote for zero displacement nor invalidate moving content.
            if zip(a, b).filter({ $0 == $1 }).count >= frame.height * 98 / 100 { continue }
            moving.append(index)
            var locations: [UInt64: [Int]] = [:]
            for (y, signature) in a.enumerated() where signature != 0 { locations[signature, default: []].append(y) }
            for (y, signature) in b.enumerated() where signature != 0 {
                guard let matches = locations[signature], matches.count <= max(4, frame.height / 24) else { continue }
                for position in matches {
                    let shift = position - y
                    if shift != 0 && abs(shift) <= maxShift { votes[shift, default: 0] += 1 }
                }
            }
        }
        if moving.isEmpty { return .unchanged }
        var alignments: [(shift: Int, score: Double, bottom: Int)] = []
        let candidates = votes.sorted { $0.value == $1.value ? abs($0.key) < abs($1.key) : $0.value > $1.value }.prefix(16)
        for candidate in candidates where candidate.value >= 6 {
            let shift = candidate.key
            var score = 0.0, bottom = frame.height / 4, supported = 0
            for index in moving {
                let a = old[index].rows, b = new[index].rows
                let top = stableEdge(a, b, reversed: false), footer = stableEdge(a, b, reversed: true)
                let start = max(top, top - shift), end = min(frame.height - footer, frame.height - footer - shift)
                guard end - start >= 24 else { continue }
                var matching = 0, informative = 0, error = 0, samples = 0
                let step = max(1, (end - start) / 100)
                for y in start..<end where b[y] != 0 {
                    informative += 1
                    if a[y + shift] != 0 && (a[y + shift] ^ b[y]).nonzeroBitCount <= 3 { matching += 1 }
                    if (y - start) % step == 0 {
                        for x in stride(from: new[index].range.lowerBound, to: new[index].range.upperBound,
                                        by: max(1, new[index].range.count / 16)) {
                            let p = ((y + shift) * frame.width + x) * 4, q = (y * frame.width + x) * 4
                            for channel in 0..<3 { error += abs(Int(previous.rgba[p + channel]) - Int(frame.rgba[q + channel])); samples += 1 }
                        }
                    }
                }
                guard informative >= 6, matching * 100 >= informative * 80, samples > 0 else { continue }
                let meanError = Double(error) / Double(samples)
                guard meanError <= 12 else { continue }
                // Each moving column contributes independently: repeated text in a long
                // overlap must not outweigh a disagreeing column with unique numbers/text.
                let confidence = min(1, Double(informative) / 24)
                score += confidence * Double(matching) / Double(informative) / (1 + meanError) * log1p(Double(matching))
                bottom = min(bottom, footer); supported += 1
            }
            if supported > 0 { alignments.append((shift, score, bottom)) }
        }
        alignments.sort { $0.score > $1.score }
        guard let best = alignments.first, alignments.count < 2 || best.score > alignments[1].score * 1.04 else { return .unmatched }
        guard best.shift > 0 else { return .reversed }
        let shift = best.shift, bottom = best.bottom
        guard frame.width * (height + shift) <= pixelLimit else { return .limit }
        let rowSize = frame.width * 4
        if bottom > 0 { rows.removeLast(bottom * rowSize) }
        let from = frame.height - shift - bottom
        rows.append(contentsOf: frame.rgba[(from * rowSize)...])
        height += shift; last = frame; count += 1
        return .added(shift)
    }
    private func stableEdge(_ a: [UInt64], _ b: [UInt64], reversed: Bool) -> Int {
        var count = 0
        for offset in 0..<a.count / 4 {
            let y = reversed ? a.count - 1 - offset : offset
            guard (a[y] ^ b[y]).nonzeroBitCount <= 3 else { break }
            count += 1
        }
        return count
    }
    private struct Band { let range: Range<Int>; let rows: [UInt64] }
    private func bands(_ frame: ScrollFrame) -> [Band] {
        let margin = max(2, frame.width / 50), available = frame.width - margin * 2
        let count = min(8, max(1, available / 12))
        return (0..<count).map { index in
            let range = (margin + available * index / count)..<(margin + available * (index + 1) / count)
            let sampleCount = min(32, range.count)
            let rows = (0..<frame.height).map { y -> UInt64 in
                var signature: UInt64 = 0, minimum = 255, maximum = 0
                for sample in 0..<sampleCount {
                    let x = range.lowerBound + (range.count - 1) * sample / max(1, sampleCount - 1)
                    let p = (y * frame.width + x) * 4
                    let luminance = (Int(frame.rgba[p]) * 77 + Int(frame.rgba[p+1]) * 150 + Int(frame.rgba[p+2]) * 29) >> 8
                    signature |= UInt64(luminance >> 6) << (sample * 2)
                    minimum = min(minimum, luminance); maximum = max(maximum, luminance)
                }
                return maximum - minimum < 8 ? 0 : signature
            }
            return Band(range: range, rows: rows)
        }
    }
}
