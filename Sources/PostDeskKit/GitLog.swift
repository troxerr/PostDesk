import Foundation

public enum GitLogError: LocalizedError {
    case failed(String)
    public var errorDescription: String? {
        switch self {
        case .failed(let path): "Couldn't read the commits in \(path). Is it a git repository?"
        }
    }
}

/// Reads recent commit subjects from a local repository with /usr/bin/git.
public enum GitLog {
    static let separator = "\u{1F}"

    public static func recentCommits(in path: String, days: Int = 7) async throws -> [Commit] {
        let output = try await Task.detached {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
            process.arguments = ["-C", path, "log", "--since=\(days) days ago", "--no-merges", "--date=short",
                                 "--pretty=format:%h\(separator)%ad\(separator)%s"]
            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = FileHandle.nullDevice
            try process.run()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            guard process.terminationStatus == 0 else { throw GitLogError.failed(path) }
            return String(decoding: data, as: UTF8.self)
        }.value
        return parse(output, repo: URL(fileURLWithPath: path).lastPathComponent)
    }

    public static func parse(_ output: String, repo: String) -> [Commit] {
        output.split(whereSeparator: \.isNewline).compactMap { line in
            let parts = line.components(separatedBy: separator)
            guard parts.count >= 3 else { return nil }
            return Commit(repo: repo, hash: parts[0], date: parts[1], subject: parts[2...].joined(separator: " "))
        }
    }
}
