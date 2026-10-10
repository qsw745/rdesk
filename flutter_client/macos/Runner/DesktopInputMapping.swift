import CoreGraphics

/// Pure mapping from remote input requests to what `DesktopHostPlugin` posts.
///
/// Depends on CoreGraphics types only, so it compiles and runs on its own:
/// see `scripts/tests/macos_input_mapping_test.swift`.
enum DesktopInputMapping {
  /// One keyboard event pair `performTextInput` posts.
  enum TextStroke: Equatable {
    /// A real key, for characters applications expect as key presses.
    case key(CGKeyCode)
    /// UTF-16 units delivered through `CGEventKeyboardSetUnicodeString`.
    case unicode([UInt16])
  }

  static let returnKeyCode: CGKeyCode = 36
  static let tabKeyCode: CGKeyCode = 48

  /// `CGEventKeyboardSetUnicodeString` silently drops units past this count.
  static let maxUnicodeUnitsPerEvent = 20

  /// Display order shared with `listDisplays` and the capture path: main
  /// display first, then ascending display ID.
  static func orderedDisplays(
    _ ids: [CGDirectDisplayID],
    main: CGDirectDisplayID
  ) -> [CGDirectDisplayID] {
    ids.sorted { a, b in
      if a == main { return true }
      if b == main { return false }
      return a < b
    }
  }

  /// The display a `switchDisplay` index refers to. Out-of-range indexes
  /// clamp the same way capture does, so input lands on the visible display.
  static func display(
    at index: Int,
    in ordered: [CGDirectDisplayID]
  ) -> CGDirectDisplayID? {
    guard !ordered.isEmpty else { return nil }
    return ordered[max(0, min(index, ordered.count - 1))]
  }

  /// Maps a point normalized to the captured frame (0...1, origin top-left)
  /// into the global display space CGEvent uses. `bounds` is the selected
  /// display's `CGDisplayBounds`; its origin is negative for a display placed
  /// left of or above the main one.
  static func globalPoint(
    normalizedX: Double,
    normalizedY: Double,
    in bounds: CGRect
  ) -> CGPoint? {
    guard
      normalizedX.isFinite, normalizedY.isFinite,
      !bounds.isInfinite, bounds.width >= 1, bounds.height >= 1
    else {
      return nil
    }
    let x = bounds.minX + CGFloat(min(max(normalizedX, 0), 1)) * bounds.width
    let y = bounds.minY + CGFloat(min(max(normalizedY, 0), 1)) * bounds.height
    // 1.0 would otherwise land on the first point of the neighbouring display.
    return CGPoint(x: min(x, bounds.maxX - 1), y: min(y, bounds.maxY - 1))
  }

  /// Evenly spaced points after `start`, ending exactly on `end`.
  static func dragPath(from start: CGPoint, to end: CGPoint, steps: Int) -> [CGPoint] {
    guard steps > 1 else { return [end] }
    return (1...steps).map { step in
      if step == steps { return end }
      let t = CGFloat(step) / CGFloat(steps)
      return CGPoint(
        x: start.x + (end.x - start.x) * t,
        y: start.y + (end.y - start.y) * t
      )
    }
  }

  /// Splits text into strokes, one per user-perceived character so surrogate
  /// pairs and combining sequences stay inside a single event.
  static func textStrokes(for text: String) -> [TextStroke] {
    text.flatMap { character -> [TextStroke] in
      if character.isNewline { return [.key(returnKeyCode)] }
      if character == "\t" { return [.key(tabKeyCode)] }
      let units = Array(character.utf16)
      if units.count <= maxUnicodeUnitsPerEvent { return [.unicode(units)] }
      return character.unicodeScalars.map { .unicode(Array(String($0).utf16)) }
    }
  }
}
