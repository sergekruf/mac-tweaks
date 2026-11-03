// Ряд настоящих иконок macOS рядом с нашими вариантами: 128 px и 32 px.
// swift compare.swift out.png ours1.png ours2.png ...
import AppKit

let args = Array(CommandLine.arguments.dropFirst())
let system = ["Mail", "Notes", "Numbers", "System Settings", "Utilities/Terminal"].compactMap { name -> (String, NSImage)? in
    for base in ["/System/Applications", "/Applications"] {
        let path = "\(base)/\(name).app"
        if FileManager.default.fileExists(atPath: path) {
            return ((name as NSString).lastPathComponent, NSWorkspace.shared.icon(forFile: path))
        }
    }
    return nil
}
let ours = args.dropFirst().enumerated().compactMap { i, p in NSImage(contentsOfFile: p).map { ("Вариант \(i + 1)", $0) } }
let items = system + ours

let cell: CGFloat = 170, W = cell * CGFloat(items.count) + 40, H: CGFloat = 520
let image = NSImage(size: NSSize(width: W, height: H))
image.lockFocus()
NSColor(srgbRed: 0.86, green: 0.93, blue: 0.99, alpha: 1).setFill(); NSRect(x: 0, y: 260, width: W, height: 260).fill()
NSColor(white: 0.13, alpha: 1).setFill(); NSRect(x: 0, y: 0, width: W, height: 260).fill()
let para = NSMutableParagraphStyle(); para.alignment = .center
for (i, (name, icon)) in items.enumerated() {
    let x = 20 + CGFloat(i) * cell
    icon.draw(in: NSRect(x: x + 21, y: 330, width: 128, height: 128))
    (name as NSString).draw(in: NSRect(x: x, y: 295, width: cell, height: 24), withAttributes: [
        .font: NSFont.systemFont(ofSize: 17, weight: i >= system.count ? .bold : .regular),
        .foregroundColor: NSColor.black, .paragraphStyle: para])
    icon.draw(in: NSRect(x: x + 53, y: 140, width: 64, height: 64))
    icon.draw(in: NSRect(x: x + 69, y: 70, width: 32, height: 32))
}
image.unlockFocus()
let rep = NSBitmapImageRep(data: image.tiffRepresentation!)!
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: args[0]))
