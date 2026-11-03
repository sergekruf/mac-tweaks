// Лист сравнения иконок: каждая в 256, 64 и 32 px на светлом и тёмном фоне.
// swift sheet.swift out.png a.png b.png ...
import AppKit

let args = Array(CommandLine.arguments.dropFirst())
let out = args[0], icons = args.dropFirst().compactMap { NSImage(contentsOfFile: $0) }
let col: CGFloat = 400, W = col * CGFloat(icons.count), H: CGFloat = 760

let image = NSImage(size: NSSize(width: W, height: H))
image.lockFocus()
NSColor(white: 0.95, alpha: 1).setFill(); NSRect(x: 0, y: H / 2, width: W, height: H / 2).fill()
NSColor(white: 0.12, alpha: 1).setFill(); NSRect(x: 0, y: 0, width: W, height: H / 2).fill()

for (i, icon) in icons.enumerated() {
    let x0 = CGFloat(i) * col
    let label = "\(i + 1)" as NSString
    label.draw(at: NSPoint(x: x0 + 16, y: H - 40),
               withAttributes: [.font: NSFont.boldSystemFont(ofSize: 28), .foregroundColor: NSColor.black])
    for (base, big) in [(H / 2, true), (0, false)] {
        if big { icon.draw(in: NSRect(x: x0 + 72, y: base + 60, width: 256, height: 256)) }
        else {
            icon.draw(in: NSRect(x: x0 + 72, y: base + 230, width: 128, height: 128))
            icon.draw(in: NSRect(x: x0 + 220, y: base + 262, width: 64, height: 64))
            icon.draw(in: NSRect(x: x0 + 300, y: base + 278, width: 32, height: 32))
            icon.draw(in: NSRect(x: x0 + 72, y: base + 60, width: 128, height: 128))
        }
    }
}
image.unlockFocus()
let rep = NSBitmapImageRep(data: image.tiffRepresentation!)!
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: out))
