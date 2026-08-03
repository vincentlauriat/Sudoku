// Renders the Sudoku app icon (1024x1024 PNG): blue squircle, white 3x3 grid,
// rounded digits, and a green "play" cell hinting at the auto-solve mode.
import AppKit

let size = 1024.0
let image = NSImage(size: NSSize(width: size, height: size))
image.lockFocus()

// macOS Big Sur icon grid: 824pt squircle centered in 1024, radius ~185.
let inset = 100.0
let squircle = NSBezierPath(
    roundedRect: NSRect(x: inset, y: inset, width: size - 2 * inset, height: size - 2 * inset),
    xRadius: 185, yRadius: 185
)
let gradient = NSGradient(
    starting: NSColor(calibratedRed: 0.16, green: 0.36, blue: 0.86, alpha: 1),
    ending: NSColor(calibratedRed: 0.05, green: 0.16, blue: 0.45, alpha: 1)
)!
gradient.draw(in: squircle, angle: -60)

// 3x3 grid, centered.
let gridSize = 560.0
let origin = (size - gridSize) / 2
let cell = gridSize / 3
let grid = NSRect(x: origin, y: origin, width: gridSize, height: gridSize)

NSColor.white.withAlphaComponent(0.92).setStroke()
let outer = NSBezierPath(roundedRect: grid, xRadius: 28, yRadius: 28)
outer.lineWidth = 22
outer.stroke()

for i in 1..<3 {
    let offset = origin + Double(i) * cell
    let v = NSBezierPath()
    v.move(to: NSPoint(x: offset, y: origin + 8))
    v.line(to: NSPoint(x: offset, y: origin + gridSize - 8))
    v.lineWidth = 12
    v.stroke()
    let h = NSBezierPath()
    h.move(to: NSPoint(x: origin + 8, y: offset))
    h.line(to: NSPoint(x: origin + gridSize - 8, y: offset))
    h.lineWidth = 12
    h.stroke()
}

// Digits (row, col from top-left) -> value.
func drawDigit(_ value: String, row: Int, col: Int, color: NSColor) {
    let font = NSFont.systemFont(ofSize: 128, weight: .bold)
    let rounded = NSFont(descriptor: font.fontDescriptor.withDesign(.rounded)!, size: 128) ?? font
    let attributes: [NSAttributedString.Key: Any] = [.font: rounded, .foregroundColor: color]
    let text = NSAttributedString(string: value, attributes: attributes)
    let bounds = text.size()
    let x = origin + Double(col) * cell + (cell - bounds.width) / 2
    let y = origin + Double(2 - row) * cell + (cell - bounds.height) / 2
    text.draw(at: NSPoint(x: x, y: y))
}

drawDigit("5", row: 0, col: 0, color: .white)
drawDigit("3", row: 0, col: 2, color: NSColor.white.withAlphaComponent(0.75))
drawDigit("7", row: 1, col: 0, color: NSColor.white.withAlphaComponent(0.75))
drawDigit("9", row: 2, col: 2, color: .white)
drawDigit("1", row: 2, col: 1, color: NSColor.white.withAlphaComponent(0.6))

// Center cell: green rounded square with a play triangle (auto-solve).
let pad = 26.0
let centerRect = NSRect(
    x: origin + cell + pad, y: origin + cell + pad,
    width: cell - 2 * pad, height: cell - 2 * pad
)
NSColor(calibratedRed: 0.18, green: 0.78, blue: 0.45, alpha: 1).setFill()
NSBezierPath(roundedRect: centerRect, xRadius: 34, yRadius: 34).fill()

let triangle = NSBezierPath()
let cx = centerRect.midX + 8, cy = centerRect.midY, r = 44.0
triangle.move(to: NSPoint(x: cx - r * 0.6, y: cy + r * 0.9))
triangle.line(to: NSPoint(x: cx - r * 0.6, y: cy - r * 0.9))
triangle.line(to: NSPoint(x: cx + r * 0.9, y: cy))
triangle.close()
NSColor.white.setFill()
triangle.fill()

image.unlockFocus()

guard let tiff = image.tiffRepresentation,
      let rep = NSBitmapImageRep(data: tiff),
      let png = rep.representation(using: .png, properties: [:]) else {
    fatalError("PNG rendering failed")
}
let out = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "icon_1024.png"
try! png.write(to: URL(fileURLWithPath: out))
print("Wrote \(out)")
