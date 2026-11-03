// Векторная иконка Mac Tweaks по сетке Apple: холст 1024, плитка 824 (continuous corners), знак ~56% плитки.
// swift icon.swift <outdir>   → icon-v1.png, icon-v2.png, icon-v3.png
import AppKit
import SwiftUI

struct Style {
    let name: String
    let tileTop: NSColor, tileBottom: NSColor
    let glyphTop: NSColor, glyphBottom: NSColor
    let glyphShadow: CGFloat
}

let styles = [
    // белый ключ на синем, как Mail / App Store
    Style(name: "v1", tileTop: NSColor(srgbRed: 0.33, green: 0.64, blue: 1.00, alpha: 1),
          tileBottom: NSColor(srgbRed: 0.05, green: 0.40, blue: 0.95, alpha: 1),
          glyphTop: .white, glyphBottom: NSColor(white: 0.93, alpha: 1), glyphShadow: 0.22),
    // светлый ключ на графите, как Терминал / Системные настройки
    Style(name: "v2", tileTop: NSColor(srgbRed: 0.36, green: 0.37, blue: 0.40, alpha: 1),
          tileBottom: NSColor(srgbRed: 0.15, green: 0.15, blue: 0.17, alpha: 1),
          glyphTop: NSColor(white: 0.97, alpha: 1), glyphBottom: NSColor(white: 0.76, alpha: 1), glyphShadow: 0.35),
    // цветной ключ на белой плитке, как Заметки / Напоминания
    Style(name: "v3", tileTop: .white, tileBottom: NSColor(white: 0.93, alpha: 1),
          glyphTop: NSColor(srgbRed: 0.20, green: 0.62, blue: 1.00, alpha: 1),
          glyphBottom: NSColor(srgbRed: 0.04, green: 0.38, blue: 0.92, alpha: 1), glyphShadow: 0.15),
]

let S: CGFloat = 1024, tileSize: CGFloat = 824
let tile = CGRect(x: (S - tileSize) / 2, y: (S - tileSize) / 2 + 8, width: tileSize, height: tileSize)
let tilePath = RoundedRectangle(cornerRadius: tileSize * 0.225, style: .continuous).path(in: tile).cgPath

/// Рожковый ключ, лежащий горизонтально, длина 1 (от -0.5 до 0.5), центр в нуле.
func wrenchParts() -> (solid: CGPath, cuts: CGPath) {
    let solid = CGMutablePath()
    let w: CGFloat = 0.17
    solid.addPath(RoundedRectangle(cornerRadius: w / 2, style: .continuous)
        .path(in: CGRect(x: -0.40, y: -w / 2, width: 0.62, height: w)).cgPath)
    solid.addEllipse(in: CGRect(x: 0.29 - 0.22, y: -0.22, width: 0.44, height: 0.44)) // головка
    solid.addEllipse(in: CGRect(x: -0.40 - 0.13, y: -0.13, width: 0.26, height: 0.26)) // хвост
    let cuts = CGMutablePath()
    let jaw: CGFloat = 0.17
    cuts.addRect(CGRect(x: 0.31, y: -jaw / 2, width: 0.4, height: jaw))
    cuts.addEllipse(in: CGRect(x: 0.31 - jaw / 2, y: -jaw / 2, width: jaw, height: jaw))
    cuts.addEllipse(in: CGRect(x: -0.40 - 0.055, y: -0.055, width: 0.11, height: 0.11))
    return (solid, cuts)
}

func gradient(_ ctx: CGContext, _ top: NSColor, _ bottom: NSColor, in rect: CGRect) {
    let g = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB),
                       colors: [top.cgColor, bottom.cgColor] as CFArray, locations: [0, 1])!
    ctx.drawLinearGradient(g, start: CGPoint(x: rect.midX, y: rect.maxY),
                           end: CGPoint(x: rect.midX, y: rect.minY), options: [])
}

func render(_ st: Style) -> CGImage {
    let ctx = CGContext(data: nil, width: Int(S), height: Int(S), bitsPerComponent: 8, bytesPerRow: 0,
                        space: CGColorSpace(name: CGColorSpace.sRGB)!,
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    // плитка с тенью
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -8), blur: 20, color: CGColor(gray: 0, alpha: 0.28))
    ctx.addPath(tilePath); ctx.setFillColor(.black); ctx.fillPath()
    ctx.restoreGState()
    ctx.saveGState()
    ctx.addPath(tilePath); ctx.clip()
    gradient(ctx, st.tileTop, st.tileBottom, in: tile)
    ctx.restoreGState()

    // ключ: 45°, длина 0.80 плитки по диагонали ≈ 0.56 по стороне
    let len = tileSize * 0.74
    var t = CGAffineTransform(translationX: tile.midX, y: tile.midY)
        .rotated(by: .pi / 4).scaledBy(x: len, y: len)
    let (solid, cuts) = wrenchParts()
    let solidP = solid.copy(using: &t)!, cutsP = cuts.copy(using: &t)!
    let bounds = solidP.boundingBox

    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -10), blur: 18, color: CGColor(gray: 0, alpha: st.glyphShadow))
    ctx.beginTransparencyLayer(auxiliaryInfo: nil)
    ctx.saveGState()
    ctx.addPath(solidP); ctx.clip()
    gradient(ctx, st.glyphTop, st.glyphBottom, in: bounds)
    ctx.restoreGState()
    ctx.setBlendMode(.clear)
    ctx.addPath(cutsP); ctx.fillPath()
    ctx.endTransparencyLayer()
    ctx.restoreGState()

    // тонкая кромка плитки
    ctx.addPath(tilePath)
    ctx.setStrokeColor(CGColor(gray: st.name == "v3" ? 0 : 1, alpha: st.name == "v3" ? 0.08 : 0.15))
    ctx.setLineWidth(2); ctx.strokePath()
    return ctx.makeImage()!
}

let outDir = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "."
for st in styles {
    let rep = NSBitmapImageRep(cgImage: render(st))
    try! rep.representation(using: .png, properties: [:])!
        .write(to: URL(fileURLWithPath: "\(outDir)/icon-\(st.name).png"))
}
