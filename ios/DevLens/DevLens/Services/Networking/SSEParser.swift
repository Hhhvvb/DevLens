import Foundation

nonisolated struct SSEEvent {
    let name: String
    let data: String
}

nonisolated struct SSEParser {
    private var lineBuffer = Data()
    private var eventName = "message"
    private var dataLines: [String] = []
    private var skipNextLF = false

    mutating func append(_ byte: UInt8) -> SSEEvent? {
        if skipNextLF {
            skipNextLF = false

            if byte == 10 {
                return nil
            }
        }

        if byte == 13 {
            skipNextLF = true
            return finishLine()
        }

        if byte == 10 {
            return finishLine()
        }

        lineBuffer.append(byte)
        return nil
    }

    private mutating func finishLine() -> SSEEvent? {
        let line = String(
            decoding: lineBuffer,
            as: UTF8.self
        )

        lineBuffer.removeAll(keepingCapacity: true)

        if line.isEmpty {
            defer {
                eventName = "message"
                dataLines.removeAll(keepingCapacity: true)
            }

            guard !dataLines.isEmpty else {
                return nil
            }

            return SSEEvent(
                name: eventName.isEmpty ? "message" : eventName,
                data: dataLines.joined(separator: "\n")
            )
        }

        if line.hasPrefix(":") {
            return nil
        }

        let parts = line.split(
            separator: ":",
            maxSplits: 1,
            omittingEmptySubsequences: false
        )

        let field = String(parts[0])
        var value = parts.count == 2 ? String(parts[1]) : ""

        if value.first == " " {
            value.removeFirst()
        }

        switch field {
        case "event":
            eventName = value
        case "data":
            dataLines.append(value)

        default:
            break
        }

        return nil
    }
}
