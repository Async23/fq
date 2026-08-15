import XCTest

@testable import FQMacOS

final class TerminalBracketedPasteDecoderTests: XCTestCase {
  func testCollectsUTF8PayloadUntilTheBracketedPasteTerminator() {
    var decoder = TerminalBracketedPasteDecoder()
    let bytes = Array("访达\nGhostty".utf8) + TerminalBracketedPasteDecoder.endSequence
    var completions: [Int] = []

    for (index, byte) in bytes.enumerated() where decoder.consume(byte) {
      completions.append(index)
    }

    XCTAssertEqual(completions, [bytes.count - 1])
    XCTAssertEqual(decoder.text, "访达\nGhostty")
    XCTAssertFalse(decoder.isOverflowed)
  }

  func testPreservesPartialAndOverlappingTerminatorPrefixesInThePayload() {
    var decoder = TerminalBracketedPasteDecoder()
    let partialPrefix: [UInt8] = [27, 91, 50, 48, 88, 27]
    let bytes = partialPrefix + TerminalBracketedPasteDecoder.endSequence

    for byte in bytes {
      _ = decoder.consume(byte)
    }

    XCTAssertEqual(decoder.payload, partialPrefix)
  }

  func testStopsGrowingAfterTheMaximumPayloadSize() {
    var decoder = TerminalBracketedPasteDecoder(maximumPayloadBytes: 3)

    for byte in Array("four".utf8) {
      _ = decoder.consume(byte)
    }

    XCTAssertEqual(decoder.text, "fou")
    XCTAssertTrue(decoder.isOverflowed)
  }
}
