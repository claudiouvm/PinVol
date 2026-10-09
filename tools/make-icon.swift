// Genera el ícono de PinVol (1024 px). Uso: swift tools/make-icon.swift salida.png
import AppKit

let S = 1024
let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: S, pixelsHigh: S, bitsPerSample: 8, samplesPerPixel: 4,
                           hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

let tile = NSRect(x: 100, y: 100, width: 824, height: 824)
let shape = NSBezierPath(roundedRect: tile, xRadius: 186, yRadius: 186)

// Sombra suave bajo el icono
NSGraphicsContext.saveGraphicsState()
let shadow = NSShadow()
shadow.shadowColor = NSColor.black.withAlphaComponent(0.35)
shadow.shadowOffset = NSSize(width: 0, height: -14)
shadow.shadowBlurRadius = 28
shadow.set()
NSColor.black.setFill()
shape.fill()
NSGraphicsContext.restoreGraphicsState()

// Fondo en degradado violeta → azul
NSGraphicsContext.saveGraphicsState()
shape.addClip()
NSGradient(colors: [NSColor(red: 0.50, green: 0.33, blue: 1.00, alpha: 1),
                    NSColor(red: 0.16, green: 0.45, blue: 1.00, alpha: 1),
                    NSColor(red: 0.05, green: 0.70, blue: 0.98, alpha: 1)])!
    .draw(in: tile, angle: -55)
// Brillo superior
NSGradient(starting: NSColor.white.withAlphaComponent(0.28), ending: NSColor.white.withAlphaComponent(0))!
    .draw(in: NSRect(x: tile.minX, y: tile.midY, width: tile.width, height: tile.height / 2), angle: -90)
NSGraphicsContext.restoreGraphicsState()

// Glifo blanco: altavoz con ondas
let cfg = NSImage.SymbolConfiguration(pointSize: 430, weight: .semibold)
    .applying(NSImage.SymbolConfiguration(paletteColors: [.white]))
let glyph = NSImage(systemSymbolName: "speaker.wave.3.fill", accessibilityDescription: nil)!.withSymbolConfiguration(cfg)!
let g = glyph.size
NSGraphicsContext.saveGraphicsState()
let glow = NSShadow()
glow.shadowColor = NSColor(red: 0.05, green: 0.1, blue: 0.5, alpha: 0.35)
glow.shadowOffset = NSSize(width: 0, height: -10)
glow.shadowBlurRadius = 22
glow.set()
glyph.draw(in: NSRect(x: tile.midX - g.width / 2 - 8, y: tile.midY - g.height / 2, width: g.width, height: g.height))
NSGraphicsContext.restoreGraphicsState()

NSGraphicsContext.restoreGraphicsState()
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
