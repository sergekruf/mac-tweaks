import AppKit
import SwiftUI

/// Знак Mac Tweaks для строки меню: тот же ключ, что в design/icon/icon.swift, но монохромный template.
/// Рисуется вектором при каждой отрисовке, поэтому чёткий и на @1x, и на @2x.
enum WrenchGlyph {
    /// Копия wrenchParts() из design/icon/icon.swift: рожковый ключ длиной 1, центр в нуле.
    /// Меняете геометрию там — поменяйте и здесь.
    static func parts() -> (solid: CGPath, cuts: CGPath) {
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

    /// Ключ под 45°, как на иконке, вписанный в rect.
    static func fitted(in rect: CGRect) -> (solid: CGPath, cuts: CGPath) {
        var rotate = CGAffineTransform(rotationAngle: .pi / 4)
        let (s, c) = parts()
        let solid = s.copy(using: &rotate)!, cuts = c.copy(using: &rotate)!
        let b = solid.boundingBoxOfPath
        let k = min(rect.width / b.width, rect.height / b.height)
        var t = CGAffineTransform(translationX: rect.midX, y: rect.midY)
            .scaledBy(x: k, y: k).translatedBy(x: -b.midX, y: -b.midY)
        return (solid.copy(using: &t)!, cuts.copy(using: &t)!)
    }

    /// Обычный режим — ключ. Режим «не засыпать» — залитая плитка с ключом-прорезью, как у иконки приложения.
    static func statusImage(active: Bool) -> NSImage {
        let image = NSImage(size: NSSize(width: 18, height: 18), flipped: false) { rect in
            guard let ctx = NSGraphicsContext.current?.cgContext else { return false }
            ctx.setFillColor(.black)
            ctx.beginTransparencyLayer(auxiliaryInfo: nil)
            if active {
                let tile = rect.insetBy(dx: 1, dy: 1)
                let tilePath = RoundedRectangle(cornerRadius: tile.width * 0.27, style: .continuous).path(in: tile).cgPath
                ctx.addPath(tilePath); ctx.fillPath()
                let (solid, cuts) = fitted(in: tile.insetBy(dx: 2.6, dy: 2.6))
                ctx.setBlendMode(.clear)
                ctx.addPath(solid); ctx.fillPath()
                ctx.setBlendMode(.normal)
                ctx.addPath(tilePath); ctx.clip()
                ctx.addPath(cuts); ctx.fillPath()
            } else {
                let (solid, cuts) = fitted(in: rect.insetBy(dx: 1, dy: 1))
                ctx.addPath(solid); ctx.fillPath()
                ctx.setBlendMode(.clear)
                ctx.addPath(cuts); ctx.fillPath()
            }
            ctx.endTransparencyLayer()
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = active ? "Mac Tweaks: не засыпает" : "Mac Tweaks"
        return image
    }
}
