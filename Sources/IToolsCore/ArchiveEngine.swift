import Foundation

public struct ArchivePasswordRequired: LocalizedError {
    public var errorDescription: String? { "压缩包需要正确的密码。" }
}

public struct ArchiveOptions {
    public var format: String
    public var level: Int
    public var password: String?
    public init(format: String = "zip", level: Int = 5, password: String? = nil) {
        self.format = format; self.level = level; self.password = password
    }
}
public enum ArchiveEngine {
    public static func run(executable: URL, arguments: [String], directory: URL?, password: String?) throws {
        let task = Process(); task.executableURL = executable; task.arguments = arguments
        task.currentDirectoryURL = directory
        var environment = ProcessInfo.processInfo.environment; environment["LC_ALL"] = "en_US.UTF-8"; task.environment = environment
        task.standardOutput = FileHandle.nullDevice
        let diagnostics = Pipe(); task.standardError = diagnostics
        let input = Pipe(); task.standardInput = input
        try task.run()
        // A bare -p asks 7-Zip to read creation passwords from stdin. For test/extract,
        // omit -p so the encrypted-archive callback prompts on stdin when necessary.
        if let password = password { try? input.fileHandleForWriting.write(contentsOf: Data((password + "\n").utf8)) }
        try? input.fileHandleForWriting.close()
        // Drain errors while the child runs; keep only a bounded tail for password classification.
        var errorData = Data()
        while let chunk = try diagnostics.fileHandleForReading.read(upToCount: 4096), !chunk.isEmpty {
            errorData.append(chunk)
            if errorData.count > 16384 { errorData.removeFirst(errorData.count - 16384) }
        }
        task.waitUntilExit()
        guard task.terminationStatus == 0 else {
            let detail = String(decoding: errorData, as: UTF8.self).lowercased()
            if detail.contains("wrong password") || detail.contains("can not open encrypted archive") {
                throw ArchivePasswordRequired()
            }
            throw FileTaskError("压缩引擎未成功完成（\(task.terminationStatus)）。请检查密码、文件读写权限和可用空间；原件未删除。")
        }
    }
    public static func validate(_ archive: URL, executable: URL, password: String?) throws {
        // A blank answer produces a specific wrong-password error when encryption
        // is present. EOF instead reports only "Break signaled", indistinguishable
        // from interruption. Plain archives ignore the answer and need no dialog.
        try run(executable: executable, arguments: ["t", "-bd", "-y", "--", archive.path], directory: nil, password: password ?? "")
    }
    public static func create(_ sources: [URL], at destination: URL, executable: URL, options: ArchiveOptions) throws {
        try AdvancedFiles.validateSelection(sources)
        guard ["zip", "7z"].contains(options.format), (0...9).contains(options.level) else { throw FileOperationError.invalidSelection }
        if let p = options.password {
            guard !p.isEmpty, p.utf8.count <= 1024, p.rangeOfCharacter(from: .controlCharacters) == nil else { throw FileTaskError("密码不能为空或包含换行、控制字符，最长 1024 字节。") }
            guard options.format != "zip" || p.unicodeScalars.allSatisfy({ $0.value >= 32 && $0.value < 127 }) else {
                throw FileTaskError("ZIP 加密密码请使用英文、数字或半角符号；需要中文密码时请选择 7z。")
            }
        }
        let output = destination.resolvingSymlinksInPath().standardizedFileURL
        for source in sources {
            let resolved = source.resolvingSymlinksInPath().standardizedFileURL
            guard output != resolved, !output.path.hasPrefix(resolved.path + "/") else { throw FileTaskError("压缩包必须保存到原文件夹之外。") }
        }
        guard !AdvancedFiles.exists(destination) else { throw FileOperationError.conflict(destination.lastPathComponent) }
        var parent = sources[0].deletingLastPathComponent().standardizedFileURL
        while !sources.allSatisfy({ $0.standardizedFileURL.path.hasPrefix(parent.path == "/" ? "/" : parent.path + "/") }) { parent.deleteLastPathComponent() }
        let prefix = parent.path == "/" ? "/" : parent.path + "/"
        // -spf preserves these explicitly relative paths instead of stripping each parent.
        // Never pass an absolute source operand with this switch.
        let relative = sources.map { "./" + $0.standardizedFileURL.path.dropFirst(prefix.count) }
        let temporaryFolder = destination.deletingLastPathComponent().appendingPathComponent(".itools-archive-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: temporaryFolder, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        defer { try? FileManager.default.removeItem(at: temporaryFolder) }
        let temporary = temporaryFolder.appendingPathComponent("archive." + options.format)
        var arguments = ["a", "-t" + options.format, "-mx=\(options.level)", "-mmt=2", "-snl", "-spd", "-spf", "-bd", "-y"]
        if options.password != nil {
            arguments += ["-p"]
            arguments += options.format == "7z" ? ["-mhe=on"] : ["-mem=AES256"]
        }
        arguments += ["--", temporary.path] + relative
        try run(executable: executable, arguments: arguments, directory: parent, password: options.password)
        try validate(temporary, executable: executable, password: options.password)
        // moveItem refuses collisions, including an output created while compression ran.
        try FileManager.default.moveItem(at: temporary, to: destination)
    }
}
