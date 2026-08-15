struct TerminalBracketedPasteDecoder {
  static let endSequence: [UInt8] = [27, 91, 50, 48, 49, 126]

  private(set) var payload: [UInt8] = []
  private(set) var isOverflowed = false
  private var matchedEndBytes = 0
  private let maximumPayloadBytes: Int

  init(maximumPayloadBytes: Int = 65_536) {
    self.maximumPayloadBytes = max(0, maximumPayloadBytes)
  }

  mutating func consume(_ byte: UInt8) -> Bool {
    guard !isOverflowed else {
      return false
    }

    if byte == Self.endSequence[matchedEndBytes] {
      matchedEndBytes += 1
      if matchedEndBytes == Self.endSequence.count {
        matchedEndBytes = 0
        return true
      }
      return false
    }

    if matchedEndBytes > 0 {
      append(contentsOf: Self.endSequence.prefix(matchedEndBytes))
      matchedEndBytes = 0
      guard !isOverflowed else {
        return false
      }
      if byte == Self.endSequence[0] {
        matchedEndBytes = 1
        return false
      }
    }

    append(byte)
    return false
  }

  var text: String {
    String(decoding: payload, as: UTF8.self)
  }

  private mutating func append(_ byte: UInt8) {
    guard payload.count < maximumPayloadBytes else {
      isOverflowed = true
      return
    }
    payload.append(byte)
  }

  private mutating func append<S: Sequence>(contentsOf bytes: S) where S.Element == UInt8 {
    for byte in bytes {
      append(byte)
      if isOverflowed {
        return
      }
    }
  }
}
