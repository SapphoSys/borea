import AppKit

enum VolumeController {
    static func currentVolume() -> Int {
        let script = "output volume of (get volume settings)"
        guard let output = runAppleScript(script),
              let value = Int(output.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            return 50
        }
        return min(100, max(0, value))
    }

    static func setVolume(_ value: Int) {
        let clamped = min(100, max(0, value))
        _ = runAppleScript("set volume output volume \(clamped)")
    }

    private static func runAppleScript(_ script: String) -> String? {
        var error: NSDictionary?
        let appleScript = NSAppleScript(source: script)
        let result = appleScript?.executeAndReturnError(&error)

        if let error {
            Log.error("Volume AppleScript error: \(error)")
            return nil
        }

        return result?.stringValue
    }
}
