import Foundation

/// Splits a byte stream into `\n`-terminated lines (AD-7: one JSON object per line).
///
/// Complete lines come back without their newline. Bytes after the last newline stay pending;
/// the Event Server drops them at EOF (an incomplete write). When the pending fragment grows past
/// `maxLineBytes` the buffer is discarded and `overflow` is reported.
struct LineSplitter {
    let maxLineBytes: Int
    private(set) var pending: [UInt8] = []
    /// Bytes of `pending` already searched for a newline.
    private var scanned = 0

    init(maxLineBytes: Int) {
        self.maxLineBytes = maxLineBytes
    }

    mutating func append(_ bytes: some Collection<UInt8>) -> (lines: [Data], overflow: Bool) {
        pending.append(contentsOf: bytes)
        var lines: [Data] = []
        var start = 0
        var index = scanned
        while index < pending.count {
            if pending[index] == 0x0A {
                lines.append(Data(pending[start..<index]))
                start = index + 1
            }
            index += 1
        }
        if start > 0 { pending.removeFirst(start) }
        scanned = pending.count
        guard pending.count <= maxLineBytes else {
            pending.removeAll()
            scanned = 0
            return (lines, true)
        }
        return (lines, false)
    }
}
