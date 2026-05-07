import Foundation

enum Log {
    private static let debugEnabled = ProcessInfo.processInfo.environment["BOREA_DEBUG"] == "1"

    static func info(_ message: String) {
        write(message)
    }

    static func debug(_ message: String) {
        guard debugEnabled else { return }
        write("debug: \(message)")
    }

    static func error(_ message: String) {
        write("error: \(message)")
    }

    private static func write(_ message: String) {
        let line = "[Borea] \(message)\n"
        FileHandle.standardError.write(Data(line.utf8))
        fflush(stderr)
    }
}
