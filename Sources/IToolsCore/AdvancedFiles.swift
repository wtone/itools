import Foundation
import CoreFoundation
import Darwin

public enum AdvancedFiles {
    public static func exists(_ url: URL) -> Bool {
        var info = stat()
        return lstat(url.path, &info) == 0
    }
    public static func validateSelection(_ files: [URL]) throws {
        let paths = files.map { $0.standardizedFileURL.path }
        guard !paths.isEmpty, Set(paths).count == paths.count else { throw FileOperationError.invalidSelection }
        for path in paths {
            guard path != "/", exists(URL(fileURLWithPath: path)),
                  !paths.contains(where: { $0 != path && path.hasPrefix($0 + "/") }) else { throw FileOperationError.invalidSelection }
        }
    }
    /// Creates empty sibling folders; selected files remain in place.
    public static func namedFolderPlan(_ files: [URL]) throws -> [URL] {
        try validateSelection(files)
        let plan = try files.map { file -> URL in
            let name = file.deletingPathExtension().lastPathComponent
            try FileOperations.validateName(name)
            let target = file.deletingLastPathComponent().appendingPathComponent(name)
            guard !exists(target) else { throw FileOperationError.conflict(name) }
            return target
        }
        guard Set(plan).count == plan.count else { throw FileOperationError.invalidSelection }
        return plan
    }
    public static func createFolders(_ plan: [URL]) throws {
        var created: [URL] = []
        do {
            for url in plan {
                guard mkdir(url.path, 0o755) == 0 else { throw FileTaskError("无法创建文件夹：" + url.path + "（" + String(cString: strerror(errno)) + "）") }
                created.append(url)
            }
        } catch {
            // rmdir never deletes newly added contents, including concurrent writes.
            for url in created.reversed() { _ = rmdir(url.path) }
            throw error
        }
    }
    public static func dissolvePlan(_ folders: [URL]) throws -> [(URL, URL)] {
        try validateSelection(folders)
        var plan: [(URL, URL)] = []
        for folder in folders {
            let info = try folder.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
            guard info.isDirectory == true, info.isSymbolicLink != true else { throw FileOperationError.notDirectory }
            let children = try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)
            for child in children {
                let target = folder.deletingLastPathComponent().appendingPathComponent(child.lastPathComponent)
                guard !exists(target) else { throw FileOperationError.conflict(target.lastPathComponent) }
                plan.append((child, target))
            }
        }
        guard Set(plan.map { $0.1 }).count == plan.count else { throw FileOperationError.invalidSelection }
        return plan
    }
    /// Moves children with rollback; leaves any nonempty parent (concurrent writes) intact.
    public static func dissolve(_ folders: [URL], expected: [(URL, URL)]) throws -> [URL] {
        let current = try dissolvePlan(folders)
        guard Set(current.map { $0.0 }) == Set(expected.map { $0.0 }),
              current.allSatisfy({ pair in expected.contains { $0.0 == pair.0 && $0.1 == pair.1 } })
        else { throw FileOperationError.invalidSelection }
        var moved: [(URL, URL)] = []
        do {
            for pair in current { try FileManager.default.moveItem(at: pair.0, to: pair.1); moved.append(pair) }
        } catch {
            var failed: [String] = []
            for pair in moved.reversed() {
                do { try FileManager.default.moveItem(at: pair.1, to: pair.0) }
                catch { failed.append(pair.1.path) }
            }
            if !failed.isEmpty { throw FileTaskError("部分项目未能移回，文件仍保留在：\n" + failed.joined(separator: "\n")) }
            throw error
        }
        return folders.filter { rmdir($0.path) != 0 }
    }
    public static func grantOwnerWrite(_ url: URL) throws {
        // Refuse links and do not follow a changed path between inspection and chmod.
        let fd = open(url.path, O_RDONLY | O_NOFOLLOW | O_NONBLOCK)
        guard fd >= 0 else { throw FileTaskError("无法打开 \(url.lastPathComponent)，不修改符号链接或受保护文件。") }
        defer { close(fd) }
        var info = stat()
        guard fstat(fd, &info) == 0, info.st_uid == getuid(),
              (info.st_mode & S_IFMT == S_IFREG || info.st_mode & S_IFMT == S_IFDIR),
              fchmod(fd, info.st_mode | S_IWUSR) == 0 else {
            throw FileTaskError("无法修改 \(url.lastPathComponent)：仅为自己拥有的文件增加写入权限。")
        }
    }
    public static func validateDeletion(_ files: [URL]) throws {
        try validateSelection(files)
        let home = FileManager.default.homeDirectoryForCurrentUser.resolvingSymlinksInPath().path
        let protected = ["/", "/Users", "/Volumes", "/Applications", "/Library", "/System", "/private", "/usr", "/bin", "/sbin", home]
        for file in files {
            let parent = file.deletingLastPathComponent().resolvingSymlinksInPath()
            let path = parent.appendingPathComponent(file.lastPathComponent).standardizedFileURL.path
            guard !protected.contains(path), !home.hasPrefix(path + "/") else { throw FileTaskError("不能彻底删除系统根目录或用户主目录。") }
        }
    }
}
public struct FileTaskError: LocalizedError {
    public let message: String
    public init(_ message: String) { self.message = message }
    public var errorDescription: String? { message }
}
public enum FilenameRepair: String, CaseIterable {
    case latin1UTF8, windowsUTF8, gbUTF8, latin1GB, dosGB
    public var title: String {
        switch self {
        case .latin1UTF8: return "Latin-1 → UTF-8"
        case .windowsUTF8: return "Windows-1252 → UTF-8"
        case .gbUTF8: return "GB18030 → UTF-8"
        case .latin1GB: return "Latin-1 → GB18030"
        case .dosGB: return "DOS CP437 → GB18030"
        }
    }
    public func repair(_ name: String) -> String? {
        let gb = String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(CFStringEncoding(CFStringEncodings.GB_18030_2000.rawValue)))
        let dos = String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(CFStringEncoding(CFStringEncodings.dosLatinUS.rawValue)))
        let source: String.Encoding = self == .windowsUTF8 ? .windowsCP1252 : self == .gbUTF8 ? gb : self == .dosGB ? dos : .isoLatin1
        let target: String.Encoding = self == .latin1GB || self == .dosGB ? gb : .utf8
        guard let data = name.data(using: source, allowLossyConversion: false),
              let repaired = String(data: data, encoding: target), repaired != name,
              (try? FileOperations.validateName(repaired)) != nil else { return nil }
        return repaired
    }
}
public final class ScanCancellation {
    private let lock = NSLock()
    private var value = false
    public init() {}
    public func cancel() { lock.lock(); value = true; lock.unlock() }
    public var cancelled: Bool { lock.lock(); defer { lock.unlock() }; return value }
}
public struct DiskEntry: Identifiable {
    public var id: URL { url }
    public let url: URL
    public let bytes: UInt64
    public let files: Int
    public let unreadable: Int
}
public enum DiskScanner {
    /// Logical sizes, including hidden files. Does not follow symlinks.
    public static func scan(_ root: URL, cancellation: ScanCancellation) throws -> [DiskEntry] {
        let fm = FileManager.default
        let info = try root.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
        guard info.isDirectory == true, info.isSymbolicLink != true else { throw FileOperationError.notDirectory }
        let keys: Set<URLResourceKey> = [.isDirectoryKey, .isSymbolicLinkKey, .isRegularFileKey, .fileSizeKey]
        let children = try fm.contentsOfDirectory(at: root, includingPropertiesForKeys: Array(keys))
        var rows: [DiskEntry] = []
        for child in children {
            if cancellation.cancelled { break }
            var size: UInt64 = 0; var files = 0; var unreadable = 0
            func count(_ url: URL) {
                do {
                    let v = try url.resourceValues(forKeys: keys)
                    if v.isRegularFile == true, v.isSymbolicLink != true { size += UInt64(max(0, v.fileSize ?? 0)); files += 1 }
                } catch { unreadable += 1 }
            }
            count(child)
            if (try? child.resourceValues(forKeys: keys)).map({ $0.isDirectory == true && $0.isSymbolicLink != true }) == true {
                if let enumerator = fm.enumerator(at: child, includingPropertiesForKeys: Array(keys), options: [], errorHandler: { _, _ in unreadable += 1; return true }) {
                    while let file = enumerator.nextObject() as? URL {
                        if cancellation.cancelled { break }
                        count(file)
                    }
                } else { unreadable += 1 }
            }
            rows.append(DiskEntry(url: child, bytes: size, files: files, unreadable: unreadable))
        }
        return rows.sorted { $0.bytes > $1.bytes }
    }
}

public enum FileSnapshot {
    /// Detects content/identity/tree changes while an archive is created. Symlinks are not followed.
    public static func capture(_ roots: [URL]) throws -> [String: String] {
        var snapshot: [String: String] = [:]
        func inspect(_ url: URL) throws -> Bool {
            var info = stat()
            guard lstat(url.path, &info) == 0 else { throw FileTaskError("原件无法读取，已保留：" + url.path) }
            snapshot[url.path] = "\(info.st_dev):\(info.st_ino):\(info.st_size):\(info.st_mode):\(info.st_mtimespec.tv_sec):\(info.st_mtimespec.tv_nsec):\(info.st_ctimespec.tv_sec):\(info.st_ctimespec.tv_nsec)"
            return info.st_mode & S_IFMT == S_IFDIR
        }
        for root in roots {
            if try inspect(root) {
                var failure: Error?
                guard let enumerator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil, options: [], errorHandler: { _, error in failure = error; return false }) else { throw FileOperationError.notDirectory }
                while let url = enumerator.nextObject() as? URL { _ = try inspect(url) }
                if let error = failure { throw error }
            }
        }
        return snapshot
    }
}
