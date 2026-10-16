import CoreText
import Flutter
import UIKit

/// V2-5a §6.3: the system's monospaced font (SF Mono). Its real name is hidden, so Flutter cannot ask
/// for it: the font is rebuilt in memory as an sfnt from its own tables and handed to Dart, which
/// registers it as "SF Mono" before `runApp`.
///
/// A32: the bytes stay in memory. Nothing is written, cached, sent or logged.
enum SystemMonoFont {
  static func register(messenger: FlutterBinaryMessenger) {
    let channel = FlutterMethodChannel(name: "pro.shellx.design/system_font", binaryMessenger: messenger)
    channel.setMethodCallHandler { call, result in
      guard call.method == "monospaced" else {
        result(FlutterMethodNotImplemented)
        return
      }
      let font = UIFont.monospacedSystemFont(ofSize: 13, weight: .regular)
      let italic = font.fontDescriptor.withSymbolicTraits(.traitItalic).map { UIFont(descriptor: $0, size: 13) as CTFont }
      DispatchQueue.global(qos: .userInitiated).async {
        let answer = SystemMonoFontTables.answer(regular: font as CTFont, italic: italic)
        DispatchQueue.main.async { result(answer) }
      }
    }
  }
}

/// The part both runners share, word for word (`apps/desktop/macos/Runner/SystemMonoFont.swift`).
enum SystemMonoFontTables {
  /// The 134 Vietnamese letters with marks (U+1EA0–U+1EF9 and the 44 in Latin-1 and Latin Extended-A
  /// and -B) and the five combining marks Vietnamese input methods produce.
  static let vietnamese: [UInt16] =
    Array(0x1EA0...0x1EF9)
    + [
      0x00C0, 0x00C1, 0x00C2, 0x00C3, 0x00C8, 0x00C9, 0x00CA, 0x00CC, 0x00CD, 0x00D2, 0x00D3,
      0x00D4, 0x00D5, 0x00D9, 0x00DA, 0x00DD, 0x00E0, 0x00E1, 0x00E2, 0x00E3, 0x00E8, 0x00E9,
      0x00EA, 0x00EC, 0x00ED, 0x00F2, 0x00F3, 0x00F4, 0x00F5, 0x00F9, 0x00FA, 0x00FD, 0x0102,
      0x0103, 0x0110, 0x0111, 0x0128, 0x0129, 0x0168, 0x0169, 0x01A0, 0x01A1, 0x01AF, 0x01B0,
    ]
    + [0x0300, 0x0301, 0x0303, 0x0309, 0x0323]

  /// `{regular, italic?, missing}`, or the `unavailable` error.
  static func answer(regular: CTFont, italic: CTFont?) -> Any {
    guard let upright = sfnt(of: regular) else {
      return FlutterError(code: "unavailable", message: nil, details: nil)
    }
    var missing = Set(self.missing(in: regular))
    var reply: [String: Any] = ["regular": FlutterStandardTypedData(bytes: upright)]
    if let italic = italic, let slanted = sfnt(of: italic) {
      missing.formUnion(self.missing(in: italic))
      reply["italic"] = FlutterStandardTypedData(bytes: slanted)
    }
    reply["missing"] = missing.sorted()
    return reply
  }

  /// The code points of [vietnamese] that [font] has no glyph for.
  static func missing(in font: CTFont) -> [Int] {
    var missing: [Int] = []
    for unit in vietnamese {
      var character = unit
      var glyph: CGGlyph = 0
      if !CTFontGetGlyphsForCharacters(font, &character, &glyph, 1) || glyph == 0 {
        missing.append(Int(unit))
      }
    }
    return missing
  }

  /// [font] as an sfnt file: its tables sorted by tag, each 4-byte aligned with its checksum;
  /// `head.checkSumAdjustment` left at 0. Nil when CoreText gives no tables.
  static func sfnt(of font: CTFont) -> Data? {
    guard let list = CTFontCopyAvailableTables(font, []) else { return nil }
    var tables: [(tag: UInt32, data: Data)] = []
    for index in 0..<CFArrayGetCount(list) {
      // The array holds the tags themselves, not CF objects (CTFont.h).
      let tag = UInt32(truncatingIfNeeded: UInt(bitPattern: CFArrayGetValueAtIndex(list, index)))
      if let table = CTFontCopyTable(font, tag, []) {
        tables.append((tag, table as Data))
      }
    }
    tables.sort { $0.tag < $1.tag }
    let tags = Set(tables.map { $0.tag })
    let version: UInt32
    if tags.contains(0x676C_7966) {  // 'glyf'
      version = 0x0001_0000
    } else if tags.contains(0x4346_4620) {  // 'CFF '
      version = 0x4F54_544F  // 'OTTO'
    } else {
      return nil
    }
    let count = tables.count
    var power = 1
    var log2 = 0
    while power * 2 <= count {
      power *= 2
      log2 += 1
    }
    var out = Data()
    out.appendBigEndian(version)
    out.appendBigEndian(UInt16(count))
    out.appendBigEndian(UInt16(power * 16))
    out.appendBigEndian(UInt16(log2))
    out.appendBigEndian(UInt16(count * 16 - power * 16))
    var records = Data()
    var body = Data()
    var offset = 12 + 16 * count
    for (tag, table) in tables {
      var bytes = Data(table)
      if tag == 0x6865_6164, bytes.count >= 12 {  // 'head': checkSumAdjustment = 0
        bytes.replaceSubrange(8..<12, with: [0, 0, 0, 0])
      }
      let length = bytes.count
      let padded = (length + 3) & ~3
      bytes.append(contentsOf: [UInt8](repeating: 0, count: padded - length))
      records.appendBigEndian(tag)
      records.appendBigEndian(checksum(bytes))
      records.appendBigEndian(UInt32(offset))
      records.appendBigEndian(UInt32(length))
      body.append(bytes)
      offset += padded
    }
    out.append(records)
    out.append(body)
    return out
  }

  /// The sfnt table checksum: the sum of the big-endian 32-bit words, wrapping.
  static func checksum(_ data: Data) -> UInt32 {
    var sum: UInt32 = 0
    data.withUnsafeBytes { (raw: UnsafeRawBufferPointer) in
      var index = 0
      while index + 3 < raw.count {
        let word =
          UInt32(raw[index]) << 24 | UInt32(raw[index + 1]) << 16 | UInt32(raw[index + 2]) << 8
          | UInt32(raw[index + 3])
        sum = sum &+ word
        index += 4
      }
    }
    return sum
  }
}

extension Data {
  fileprivate mutating func appendBigEndian(_ value: UInt32) {
    append(contentsOf: [UInt8(value >> 24 & 0xFF), UInt8(value >> 16 & 0xFF), UInt8(value >> 8 & 0xFF), UInt8(value & 0xFF)])
  }

  fileprivate mutating func appendBigEndian(_ value: UInt16) {
    append(contentsOf: [UInt8(value >> 8 & 0xFF), UInt8(value & 0xFF)])
  }
}
