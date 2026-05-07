import Foundation

struct BatteryReport: Equatable {
    let percentage: Int
    let state: String?

    var title: String {
        if let state, !state.isEmpty {
            return "\(percentage)% \(state)"
        }
        return "\(percentage)%"
    }
}

enum BatteryReader {
    static func readHeadsetBattery(named deviceName: String = "WH-1000XM4") -> BatteryReport? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/pmset")
        process.arguments = ["-g", "accps"]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()

        do {
            try process.run()
        } catch {
            Log.error("Battery read failed to run pmset: \(error.localizedDescription)")
            return nil
        }

        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            Log.error("Battery read pmset exited with status \(process.terminationStatus)")
            return nil
        }

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        guard let output = String(data: data, encoding: .utf8) else { return nil }
        return parse(output: output, deviceName: deviceName)
    }

    static func parse(output: String, deviceName: String) -> BatteryReport? {
        output
            .split(separator: "\n")
            .compactMap { line -> BatteryReport? in
                guard line.localizedCaseInsensitiveContains(deviceName) else { return nil }
                return parseBatteryLine(String(line))
            }
            .first
    }

    private static func parseBatteryLine(_ line: String) -> BatteryReport? {
        let pattern = #"(\d{1,3})%;\s*([^;]+)"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)),
              let percentageRange = Range(match.range(at: 1), in: line) else {
            return nil
        }

        let percentage = Int(line[percentageRange]).map { min(100, max(0, $0)) }
        let state: String?
        if let stateRange = Range(match.range(at: 2), in: line) {
            state = String(line[stateRange]).trimmingCharacters(in: .whitespacesAndNewlines)
        } else {
            state = nil
        }

        guard let percentage else { return nil }
        return BatteryReport(percentage: percentage, state: state)
    }
}
