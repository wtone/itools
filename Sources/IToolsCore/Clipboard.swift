import Foundation
import CryptoKit

public enum ClipKind: String, Codable, CaseIterable { case text, image, files }
public struct ClipRepresentation: Codable, Equatable {
    public var type: String
    public var data: Data
    public init(type: String, data: Data) { self.type = type; self.data = data }
}
public struct ClipEntry: Codable, Identifiable, Equatable {
    public var id: UUID
    public var date: Date
    public var kind: ClipKind
    public var text: String
    public var source: String
    public var pinned: Bool
    public var group: String
    public var payload: [ClipRepresentation]
    public init(kind: ClipKind, text: String, source: String, payload: [ClipRepresentation], date: Date = Date()) {
        id = UUID(); self.date = date; self.kind = kind; self.text = text
        self.source = source; self.payload = payload; pinned = false; group = ""
    }
    public var byteCount: Int { payload.reduce(0) { $0 + $1.data.count } + text.utf8.count }
    public var fingerprint: String {
        var hash = SHA256()
        for part in payload.sorted(by: { $0.type < $1.type }) {
            // Length-prefix the fields so different type/data boundaries cannot collide.
            for field in [Data(part.type.utf8), part.data] {
                var length = UInt64(field.count).bigEndian
                withUnsafeBytes(of: &length) { hash.update(data: Data($0)) }
                hash.update(data: field)
            }
        }
        return hash.finalize().map { String(format: "%02x", $0) }.joined()
    }
}
public struct HistoryPolicy {
    public var maxCount: Int
    public var maxBytes: Int
    public var retentionDays: Int
    public init(maxCount: Int = 300, maxBytes: Int = 100 * 1024 * 1024, retentionDays: Int = 30) {
        self.maxCount = maxCount; self.maxBytes = maxBytes; self.retentionDays = retentionDays
    }
    public func prune(_ entries: [ClipEntry], now: Date = Date()) -> [ClipEntry] {
        // Pins survive automatic expiration. Quotas for new history include pinned storage.
        let pins = entries.filter(\.pinned)
        let cutoff = now.addingTimeInterval(-Double(retentionDays) * 86400)
        var output = pins
        var size = pins.reduce(0) { $0 + $1.byteCount }
        for entry in entries.filter({ !$0.pinned && (retentionDays == 0 || $0.date >= cutoff) }).sorted(by: { $0.date > $1.date }) {
            guard output.count < maxCount, size + entry.byteCount <= maxBytes else { continue }
            output.append(entry); size += entry.byteCount
        }
        return output.sorted { $0.date > $1.date }
    }
    public func adding(_ entry: ClipEntry, to existing: [ClipEntry], now: Date = Date()) -> [ClipEntry] {
        var next = entry
        let fingerprint = entry.fingerprint
        if let old = existing.first(where: { $0.fingerprint == fingerprint }) {
            next.id = old.id; next.pinned = old.pinned; next.group = old.group
        }
        return prune([next] + existing.filter { $0.fingerprint != fingerprint }, now: now)
    }
}
public struct Snippet: Codable, Identifiable {
    public var id: UUID
    public var title: String
    public var body: String
    public var group: String
    public init(title: String, body: String, group: String = "常用") {
        id = UUID(); self.title = title; self.body = body; self.group = group
    }
    public func expanded(clipboard: String, date: Date = Date()) -> String {
        let formatter = DateFormatter(); formatter.dateFormat = "yyyy-MM-dd"
        let day = formatter.string(from: date); formatter.dateFormat = "HH:mm"
        return body.replacingOccurrences(of: "{{date}}", with: day)
            .replacingOccurrences(of: "{{time}}", with: formatter.string(from: date))
            .replacingOccurrences(of: "{{clipboard}}", with: clipboard)
    }
}
