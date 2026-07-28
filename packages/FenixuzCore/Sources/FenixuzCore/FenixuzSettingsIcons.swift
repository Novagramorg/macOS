//
//  FenixuzSettingsIcons.swift
//  Telegram-Mac
//
//  iOS portasi: submodules/Fenixuz/ProMessager/Sources/FenixuzSettingsIcons.swift
//
//  FenixPro Settings'dagi rangli kvadrat ikonkalar — iOS Settings uslubi:
//  30×30, 7pt burchak, to'liq rangli fon, oq SF Symbol o'rtada. iOS bilan 1:1
//  (aynan bir xil 12 rang, bir xil hex). Mac row'lari `icon: CGImage?` qabul
//  qiladi, shuning uchun CGImage qaytaramiz.
//

import Cocoa

public enum FenixuzIconColor {
    case red, green, blue, lightBlue, teal, orange, purple, pink, gray, violet, yellow, gold

    var nsColor: NSColor {
        switch self {
        case .red:       return NSColor(red: 1.00, green: 0.27, blue: 0.23, alpha: 1.0)  // FF453A
        case .green:     return NSColor(red: 0.20, green: 0.78, blue: 0.35, alpha: 1.0)  // 34C759
        case .blue:      return NSColor(red: 0.00, green: 0.48, blue: 1.00, alpha: 1.0)  // 0079FF
        case .lightBlue: return NSColor(red: 0.20, green: 0.68, blue: 0.90, alpha: 1.0)  // 32ADE6
        case .teal:      return NSColor(red: 0.00, green: 0.78, blue: 0.75, alpha: 1.0)  // 00C7BE
        case .orange:    return NSColor(red: 1.00, green: 0.62, blue: 0.04, alpha: 1.0)  // FF9F0A
        case .purple:    return NSColor(red: 0.69, green: 0.32, blue: 0.87, alpha: 1.0)  // AF52DE
        case .pink:      return NSColor(red: 1.00, green: 0.18, blue: 0.33, alpha: 1.0)  // FF2D55
        case .gray:      return NSColor(red: 0.56, green: 0.56, blue: 0.58, alpha: 1.0)  // 8E8E93
        case .violet:    return NSColor(red: 0.37, green: 0.36, blue: 0.90, alpha: 1.0)  // 5E5CE6
        case .yellow:    return NSColor(red: 1.00, green: 0.80, blue: 0.00, alpha: 1.0)  // FFCC00
        case .gold:      return NSColor(red: 0.83, green: 0.69, blue: 0.22, alpha: 1.0)  // D4AF37 — tilla
        }
    }
}

/// 30×30 rangli kvadrat ichida oq SF Symbol — iOS bilan 1:1.
public func fenixuzSettingsIcon(systemName: String, color: FenixuzIconColor) -> CGImage? {
    let size = NSSize(width: 30, height: 30)

    // 1) Oq rangga bo'yalgan SF Symbol (shaffof fonda — faqat symbol piksellari oqaradi).
    var whiteSymbol: NSImage?
    if #available(macOS 11.0, *), let base = NSImage(systemSymbolName: systemName, accessibilityDescription: nil) {
        let cfg = NSImage.SymbolConfiguration(pointSize: 16, weight: .semibold)
        let symbol = base.withSymbolConfiguration(cfg) ?? base
        let sw = min(symbol.size.width, 20)
        let sh = min(symbol.size.height, 20)
        let s = NSImage(size: NSSize(width: sw, height: sh))
        s.lockFocus()
        symbol.draw(in: NSRect(x: 0, y: 0, width: sw, height: sh))
        NSColor.white.set()
        NSGraphicsContext.current?.compositingOperation = .sourceAtop
        NSBezierPath(rect: NSRect(x: 0, y: 0, width: sw, height: sh)).fill()
        s.unlockFocus()
        whiteSymbol = s
    }

    // 2) Rangli rounded-square fon + o'rtada oq symbol.
    let image = NSImage(size: size)
    image.lockFocus()
    let bg = NSBezierPath(roundedRect: NSRect(origin: .zero, size: size), xRadius: 7, yRadius: 7)
    color.nsColor.setFill()
    bg.fill()
    if let ws = whiteSymbol {
        let rect = NSRect(
            x: (size.width - ws.size.width) / 2,
            y: (size.height - ws.size.height) / 2,
            width: ws.size.width,
            height: ws.size.height
        )
        ws.draw(in: rect)
    }
    image.unlockFocus()

    guard let upright = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
        return nil
    }
    // Settings rows draw their icon into a FLIPPED CGContext (see GeneralInteractedRowView),
    // which is why every built-in icon is generated with `.precomposed(flipVertical: true)`.
    // Our CGImage isn't pre-flipped, so without this it renders upside-down (obvious on the
    // vertically-asymmetric glyphs like trash/mic). Flip it vertically to match the convention.
    let w = upright.width
    let h = upright.height
    guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                              space: CGColorSpaceCreateDeviceRGB(),
                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
        return upright
    }
    ctx.translateBy(x: 0, y: CGFloat(h))
    ctx.scaleBy(x: 1, y: -1)
    ctx.draw(upright, in: CGRect(x: 0, y: 0, width: w, height: h))
    return ctx.makeImage() ?? upright
}
