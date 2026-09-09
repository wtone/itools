import Foundation
import CryptoKit

public enum FileOperationError: LocalizedError {
    case invalidName, notDirectory, conflict(String), invalidSelection
    public var errorDescription: String? {
        switch self {
        case .invalidName: return "文件名不能为空、不能是 . 或 ..，也不能包含斜杠、冒号或控制字符。"
        case .notDirectory: return "请选择一个有效文件夹。"
        case .conflict(let name): return "目标已存在：\(name)。未覆盖任何文件。"
        case .invalidSelection: return "请选择有效文件；目标不能是文件本身或其子目录。"
        }
    }
}
public enum FileOperations {
    public static func validateName(_ name: String) throws {
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              name != ".", name != "..", name.utf8.count <= 255,
              name.rangeOfCharacter(from: CharacterSet(charactersIn: "/\\:").union(.controlCharacters)) == nil
        else { throw FileOperationError.invalidName }
    }
    public static func uniqueURL(in directory: URL, name: String) throws -> URL {
        try validateName(name)
        let candidate = directory.appendingPathComponent(name)
        let ext = candidate.pathExtension
        let stem = ext.isEmpty ? name : candidate.deletingPathExtension().lastPathComponent
        var url = candidate; var i = 2
        while FileManager.default.fileExists(atPath: url.path) {
            url = directory.appendingPathComponent("\(stem) \(i)" + (ext.isEmpty ? "" : ".\(ext)")); i += 1
        }
        return url
    }
    @discardableResult public static func create(in directory: URL, name: String, data: Data = Data()) throws -> URL {
        try validateName(name)
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: directory.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            throw FileOperationError.notDirectory
        }
        let url = directory.appendingPathComponent(name)
        try data.write(to: url, options: .withoutOverwriting)
        return url
    }
    @discardableResult public static func transfer(_ source: URL, to directory: URL, move: Bool) throws -> URL {
        let resolvedSource = source.resolvingSymlinksInPath().standardizedFileURL
        let resolvedDirectory = directory.resolvingSymlinksInPath().standardizedFileURL
        guard resolvedDirectory != resolvedSource,
              !resolvedDirectory.path.hasPrefix(resolvedSource.path + "/") else { throw FileOperationError.invalidSelection }
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: directory.path, isDirectory: &isDir), isDir.boolValue else { throw FileOperationError.notDirectory }
        let destination = directory.appendingPathComponent(source.lastPathComponent)
        guard !FileManager.default.fileExists(atPath: destination.path) else { throw FileOperationError.conflict(destination.lastPathComponent) }
        if move { try FileManager.default.moveItem(at: source, to: destination) }
        else { try FileManager.default.copyItem(at: source, to: destination) }
        return destination
    }
    public static func sha256(_ url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url); defer { try? handle.close() }
        var hash = SHA256()
        while let data = try handle.read(upToCount: 1024 * 1024), !data.isEmpty { hash.update(data: data) }
        return hash.finalize().map { String(format: "%02x", $0) }.joined()
    }
    public static func renamePlan(_ files: [URL], prefix: String, start: Int) throws -> [(URL, URL)] {
        try validateName(prefix + String(start))
        guard start >= 0, start <= Int.max - files.count, Set(files).count == files.count else { throw FileOperationError.invalidSelection }
        return try files.enumerated().map { index, file in
            let ext = file.pathExtension
            let name = prefix + String(start + index) + (ext.isEmpty ? "" : "." + ext)
            try validateName(name)
            return (file, file.deletingLastPathComponent().appendingPathComponent(name))
        }
    }
    public static func executeRename(_ plan: [(URL, URL)]) throws {
        let fm = FileManager.default
        let changes = plan.filter { $0.0 != $0.1 }
        let sources = Set(changes.map { $0.0.standardizedFileURL })
        guard Set(changes.map { $0.1.standardizedFileURL }).count == changes.count else { throw FileOperationError.invalidSelection }
        for (_, destination) in changes {
            if fm.fileExists(atPath: destination.path) && !sources.contains(destination.standardizedFileURL) {
                throw FileOperationError.conflict(destination.lastPathComponent)
            }
        }
        var staged: [(original: URL, temporary: URL, destination: URL)] = []
        var completed: [(original: URL, temporary: URL, destination: URL)] = []
        do {
            for (source, destination) in changes {
                let temp = source.deletingLastPathComponent().appendingPathComponent(".itools-rename-" + UUID().uuidString)
                try fm.moveItem(at: source, to: temp)
                staged.append((source, temp, destination))
            }
            for item in staged {
                try fm.moveItem(at: item.temporary, to: item.destination)
                completed.append(item)
            }
        } catch {
            for item in completed.reversed() { try? fm.moveItem(at: item.destination, to: item.temporary) }
            for item in staged.reversed() { try? fm.moveItem(at: item.temporary, to: item.original) }
            throw error
        }
    }
}
