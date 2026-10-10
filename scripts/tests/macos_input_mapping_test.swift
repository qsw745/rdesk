// Standalone checks for flutter_client/macos/Runner/DesktopInputMapping.swift.
//
// Run from the repository root (no Xcode build, nothing is posted to the system):
//
//   out="$(mktemp -d)/macos_input_mapping_test" && xcrun swiftc -parse-as-library -o "$out" \
//     flutter_client/macos/Runner/DesktopInputMapping.swift \
//     scripts/tests/macos_input_mapping_test.swift && "$out"

import CoreGraphics
import Foundation

@main
enum MacInputMappingTest {
  static var failures = 0

  static func expect<T: Equatable>(_ name: String, _ actual: T, _ expected: T) {
    if actual == expected {
      print("ok   \(name)")
    } else {
      failures += 1
      print("FAIL \(name): expected \(expected), got \(actual)")
    }
  }

  static func point(_ x: Double, _ y: Double, in bounds: CGRect) -> CGPoint? {
    DesktopInputMapping.globalPoint(normalizedX: x, normalizedY: y, in: bounds)
  }

  static func utf16(_ text: String) -> DesktopInputMapping.TextStroke {
    .unicode(Array(text.utf16))
  }

  static func main() {
    let main = CGRect(x: 0, y: 0, width: 2560, height: 1440)
    let left = CGRect(x: -1728, y: 323, width: 1728, height: 1117)
    let above = CGRect(x: 416, y: -1117, width: 1728, height: 1117)

    // 主显示器：归一化坐标按 bounds 线性换算。
    expect("主屏中心", point(0.5, 0.5, in: main), CGPoint(x: 1280, y: 720))
    expect("主屏原点", point(0, 0, in: main), CGPoint(x: 0, y: 0))

    // 副屏在左侧 / 上方时原点为负，点击不能再落回主屏。
    expect("左侧副屏中心", point(0.5, 0.5, in: left), CGPoint(x: -864, y: 881.5))
    expect("左侧副屏原点", point(0, 0, in: left), CGPoint(x: -1728, y: 323))
    expect("上方副屏中心", point(0.5, 0.5, in: above), CGPoint(x: 1280, y: -558.5))

    // 边界：1.0 留在所选显示器内，越界值被收拢，非法值被拒绝。
    expect("右下角留在屏内", point(1, 1, in: main), CGPoint(x: 2559, y: 1439))
    expect("左侧副屏右边缘不越到主屏", point(1, 0, in: left), CGPoint(x: -1, y: 323))
    expect("越界值收拢", point(-0.2, 1.7, in: main), CGPoint(x: 0, y: 1439))
    expect("NaN 被拒绝", point(.nan, 0.5, in: main), nil)
    expect("无穷大被拒绝", point(0.5, .infinity, in: main), nil)
    expect("空 bounds 被拒绝", point(0.5, 0.5, in: .zero), nil)
    expect("null bounds 被拒绝", point(0.5, 0.5, in: .null), nil)

    // 显示器顺序与索引：主屏在前，其余按 ID；索引越界时与采集一致地收拢。
    let ordered = DesktopInputMapping.orderedDisplays([7, 3, 5], main: 5)
    expect("主屏排第一", ordered, [5, 3, 7])
    expect("索引 1", DesktopInputMapping.display(at: 1, in: ordered), 3)
    expect("索引过大收拢到最后一块", DesktopInputMapping.display(at: 9, in: ordered), 7)
    expect("负索引收拢到主屏", DesktopInputMapping.display(at: -1, in: ordered), 5)
    expect("没有显示器", DesktopInputMapping.display(at: 0, in: []), nil)

    // 拖动路径：不含起点，最后一点精确等于终点。
    let path = DesktopInputMapping.dragPath(
      from: CGPoint(x: -100, y: 0), to: CGPoint(x: 100, y: 50), steps: 4)
    expect("拖动路径", path, [
      CGPoint(x: -50, y: 12.5), CGPoint(x: 0, y: 25),
      CGPoint(x: 50, y: 37.5), CGPoint(x: 100, y: 50),
    ])
    expect("步数不足时只到终点",
           DesktopInputMapping.dragPath(from: .zero, to: CGPoint(x: 3, y: 4), steps: 0),
           [CGPoint(x: 3, y: 4)])

    // 文本：按用户可见字符拆分，代理对与组合序列不被拆开。
    expect("ASCII 与中文",
           DesktopInputMapping.textStrokes(for: "a你"), [utf16("a"), utf16("你")])
    expect("代理对留在同一事件",
           DesktopInputMapping.textStrokes(for: "😀"), [.unicode([0xD83D, 0xDE00])])
    expect("ZWJ 表情留在同一事件",
           DesktopInputMapping.textStrokes(for: "👨‍👩‍👧"), [utf16("👨‍👩‍👧")])
    expect("换行与制表符走真实按键",
           DesktopInputMapping.textStrokes(for: "a\n\tb\r\nc"), [
             utf16("a"), .key(36), .key(48), utf16("b"), .key(36), utf16("c"),
           ])
    expect("空文本", DesktopInputMapping.textStrokes(for: ""), [])

    // 超过单事件上限的组合序列按标量拆开，不被静默截断。
    let stacked = "e" + String(repeating: "\u{0301}", count: 30)
    let strokes = DesktopInputMapping.textStrokes(for: stacked)
    expect("超长组合序列拆成 31 个事件", strokes.count, 31)
    let rejoined = strokes.flatMap { stroke -> [UInt16] in
      if case .unicode(let units) = stroke { return units }
      return []
    }
    expect("拆分后内容不丢失", rejoined, Array(stacked.utf16))

    if failures > 0 {
      print("\(failures) 项失败")
      exit(1)
    }
    print("全部通过")
  }
}
