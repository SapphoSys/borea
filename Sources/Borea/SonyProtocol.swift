import Foundation

enum SonyMode: Equatable {
    case noiseCancelling
    case ambient(level: Int, focusOnVoice: Bool)
    case off

    var title: String {
        switch self {
        case .noiseCancelling:
            return "Noise Cancelling"
        case .ambient:
            return "Ambient Sound"
        case .off:
            return "Sound Control Off"
        }
    }

    var isAmbient: Bool {
        if case .ambient = self { return true }
        return false
    }
}

enum SonyProtocol {
    private static let startMarker: UInt8 = 62
    private static let endMarker: UInt8 = 60
    private static let escapeMarker: UInt8 = 61
    private static let escaped60: UInt8 = 44
    private static let escaped61: UInt8 = 45
    private static let escaped62: UInt8 = 46

    private static let ack: UInt8 = 1
    private static let dataMDR: UInt8 = 12
    private static let ncasmGetParam: UInt8 = 102
    private static let ncasmRetParam: UInt8 = 103
    private static let ncasmSetParam: UInt8 = 104
    private static let ncasmNotifyParam: UInt8 = 105
    private static let noiseCancellingAndAmbientSoundMode: UInt8 = 2
    private static let effectOff: UInt8 = 0
    private static let effectOn: UInt8 = 1
    private static let effectAdjustmentCompletion: UInt8 = 17
    private static let levelAdjustment: UInt8 = 1
    private static let dual: UInt8 = 2
    private static let single: UInt8 = 1
    private static let soundOff: UInt8 = 0
    private static let ambientNormal: UInt8 = 0
    private static let ambientVoice: UInt8 = 1

    static func command(for mode: SonyMode, sequence: UInt8) -> Data {
        package(payload: ncasmPayload(for: mode), dataType: dataMDR, sequence: sequence)
    }

    static func stateQuery(sequence: UInt8) -> Data {
        package(payload: [ncasmGetParam, noiseCancellingAndAmbientSoundMode], dataType: dataMDR, sequence: sequence)
    }

    static func acknowledgement(for frame: SonyFrame) -> Data {
        package(payload: [], dataType: ack, sequence: frame.sequence ^ 1)
    }

    static func parseFrame(_ data: Data) -> SonyFrame? {
        guard data.count >= 7 else { return nil }
        let bytes = [UInt8](data)
        guard bytes.first == startMarker, bytes.last == endMarker else { return nil }
        let inner = unescape(Array(bytes.dropFirst().dropLast()))
        guard inner.count >= 6 else { return nil }
        let expected = checksum(Array(inner.dropLast()))
        guard inner.last == expected else { return nil }

        let dataSize = (Int(inner[2]) << 24) | (Int(inner[3]) << 16) | (Int(inner[4]) << 8) | Int(inner[5])
        let payloadStart = 6
        let payloadEnd = min(payloadStart + dataSize, inner.count - 1)
        let payload = payloadEnd >= payloadStart ? Data(inner[payloadStart..<payloadEnd]) : Data()
        return SonyFrame(dataType: inner[0], sequence: inner[1], payload: payload)
    }

    static func mode(from frame: SonyFrame) -> SonyMode? {
        let payload = [UInt8](frame.payload)
        guard payload.count >= 8 else { return nil }

        for start in 0...(payload.count - 8) {
            let chunk = payload[start..<(start + 8)]
            guard [ncasmSetParam, ncasmNotifyParam, ncasmRetParam].contains(chunk[chunk.startIndex]),
                  chunk[chunk.startIndex + 1] == noiseCancellingAndAmbientSoundMode else {
                continue
            }

            let effect = chunk[chunk.startIndex + 2]
            let dualSingle = chunk[chunk.startIndex + 4]
            let ambientId = chunk[chunk.startIndex + 6]
            let level = Int(chunk[chunk.startIndex + 7])

            if effect == effectOff {
                return .off
            }

            if effect == effectOn || effect == effectAdjustmentCompletion {
                if dualSingle == dual && level == 0 {
                    return .noiseCancelling
                }

                if level > 0 {
                    return .ambient(level: min(level, 20), focusOnVoice: ambientId == ambientVoice)
                }
            }
        }

        return nil
    }

    private static func ncasmPayload(for mode: SonyMode) -> [UInt8] {
        let effect: UInt8
        let dualSingle: UInt8
        let ambientId: UInt8
        let level: UInt8

        switch mode {
        case .noiseCancelling:
            effect = effectAdjustmentCompletion
            dualSingle = dual
            ambientId = ambientNormal
            level = 0
        case let .ambient(requestedLevel, focusOnVoice):
            let clampedLevel = UInt8(max(1, min(20, requestedLevel)))
            effect = effectAdjustmentCompletion
            dualSingle = clampedLevel == 1 ? single : soundOff
            ambientId = focusOnVoice ? ambientVoice : ambientNormal
            level = clampedLevel
        case .off:
            effect = effectOff
            dualSingle = soundOff
            ambientId = ambientNormal
            level = 255
        }

        return [
            ncasmSetParam,
            noiseCancellingAndAmbientSoundMode,
            effect,
            levelAdjustment,
            dualSingle,
            levelAdjustment,
            ambientId,
            level
        ]
    }

    private static func package(payload: [UInt8], dataType: UInt8, sequence: UInt8) -> Data {
        var inner: [UInt8] = [dataType, sequence]
        inner.append(contentsOf: int32BigEndian(payload.count))
        inner.append(contentsOf: payload)
        inner.append(checksum(inner))

        var framed: [UInt8] = [startMarker]
        framed.append(contentsOf: escape(inner))
        framed.append(endMarker)
        return Data(framed)
    }

    private static func int32BigEndian(_ value: Int) -> [UInt8] {
        [
            UInt8((value >> 24) & 0xff),
            UInt8((value >> 16) & 0xff),
            UInt8((value >> 8) & 0xff),
            UInt8(value & 0xff)
        ]
    }

    private static func checksum(_ bytes: [UInt8]) -> UInt8 {
        bytes.reduce(0) { $0 &+ $1 }
    }

    private static func escape(_ bytes: [UInt8]) -> [UInt8] {
        var result: [UInt8] = []
        result.reserveCapacity(bytes.count)

        for byte in bytes {
            switch byte {
            case endMarker:
                result.append(contentsOf: [escapeMarker, escaped60])
            case escapeMarker:
                result.append(contentsOf: [escapeMarker, escaped61])
            case startMarker:
                result.append(contentsOf: [escapeMarker, escaped62])
            default:
                result.append(byte)
            }
        }

        return result
    }

    private static func unescape(_ bytes: [UInt8]) -> [UInt8] {
        var result: [UInt8] = []
        var index = 0

        while index < bytes.count {
            let byte = bytes[index]
            if byte == escapeMarker, index + 1 < bytes.count {
                index += 1
                switch bytes[index] {
                case escaped60:
                    result.append(endMarker)
                case escaped61:
                    result.append(escapeMarker)
                case escaped62:
                    result.append(startMarker)
                default:
                    result.append(bytes[index])
                }
            } else {
                result.append(byte)
            }
            index += 1
        }

        return result
    }
}

struct SonyFrame {
    let dataType: UInt8
    let sequence: UInt8
    let payload: Data
}

extension Data {
    var xm4Hex: String {
        map { String(format: "%02X", $0) }.joined(separator: " ")
    }
}
