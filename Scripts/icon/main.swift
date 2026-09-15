import AppKit
import CoreGraphics

/// Gera o iconset do Vigia. Desenhado por código para que qualquer ajuste seja
/// um diff revisável e as dez resoluções saiam sempre consistentes.
///
/// A forma: uma seta descendo para dentro de um dispositivo — a imagem entrando
/// no pendrive.
func drawIcon(size: CGFloat, context ctx: CGContext) {
    let rect = CGRect(x: 0, y: 0, width: size, height: size)
    ctx.setAllowsAntialiasing(true)

    let inset = size * 0.086
    let plate = rect.insetBy(dx: inset, dy: inset)
    let radius = plate.width * 0.2237
    let shape = CGPath(roundedRect: plate, cornerWidth: radius, cornerHeight: radius, transform: nil)

    // Laranja de forja, escurecendo para baixo.
    ctx.saveGState()
    ctx.addPath(shape)
    ctx.clip()
    let colors = [
        NSColor(srgbRed: 0.16, green: 0.22, blue: 0.42, alpha: 1).cgColor,
        NSColor(srgbRed: 0.15, green: 0.35, blue: 0.62, alpha: 1).cgColor,
        NSColor(srgbRed: 0.20, green: 0.55, blue: 0.78, alpha: 1).cgColor,
    ]
    let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                              colors: colors as CFArray, locations: [0, 0.55, 1])!
    ctx.drawLinearGradient(gradient, start: CGPoint(x: plate.minX, y: plate.maxY),
                           end: CGPoint(x: plate.maxX, y: plate.minY), options: [])
    ctx.setBlendMode(.softLight)
    ctx.setFillColor(NSColor(white: 1, alpha: 0.30).cgColor)
    ctx.move(to: CGPoint(x: plate.minX, y: plate.maxY))
    ctx.addLine(to: CGPoint(x: plate.maxX, y: plate.maxY))
    ctx.addLine(to: CGPoint(x: plate.minX, y: plate.midY))
    ctx.closePath()
    ctx.fillPath()
    ctx.setBlendMode(.normal)
    ctx.restoreGState()

    let center = CGPoint(x: plate.midX, y: plate.midY)
    let white = NSColor.white.cgColor

    // A lente: um anel grosso com o círculo escuro dentro e um brilho — a
    // forma que se reconhece como câmera mesmo em 16 pixels.
    ctx.saveGState()
    let outer = plate.width * 0.26
    ctx.setStrokeColor(NSColor.white.cgColor)
    ctx.setLineWidth(plate.width * 0.085)
    ctx.strokeEllipse(in: CGRect(x: center.x - outer, y: center.y - outer,
                                 width: outer * 2, height: outer * 2))

    let pupil = plate.width * 0.125
    ctx.setFillColor(NSColor(white: 1, alpha: 0.92).cgColor)
    ctx.fillEllipse(in: CGRect(x: center.x - pupil, y: center.y - pupil,
                               width: pupil * 2, height: pupil * 2))

    // O reflexo, deslocado para cima e para a esquerda como numa lente real.
    let glint = plate.width * 0.045
    ctx.setFillColor(NSColor(white: 1, alpha: 0.55).cgColor)
    ctx.fillEllipse(in: CGRect(x: center.x - outer * 0.55 - glint,
                               y: center.y + outer * 0.42 - glint,
                               width: glint * 2, height: glint * 2))
    ctx.restoreGState()
}

func writePNG(size: Int, to url: URL) {
    let ctx = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8,
                        bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    drawIcon(size: CGFloat(size), context: ctx)
    let rep = NSBitmapImageRep(cgImage: ctx.makeImage()!)
    rep.size = NSSize(width: size, height: size)
    try! rep.representation(using: .png, properties: [:])!.write(to: url)
}

let out = URL(filePath: CommandLine.arguments[1], directoryHint: .isDirectory)
try? FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
for (size, name) in [(16, "icon_16x16"), (32, "icon_16x16@2x"), (32, "icon_32x32"),
                     (64, "icon_32x32@2x"), (128, "icon_128x128"), (256, "icon_128x128@2x"),
                     (256, "icon_256x256"), (512, "icon_256x256@2x"), (512, "icon_512x512"),
                     (1024, "icon_512x512@2x")] {
    writePNG(size: size, to: out.appending(path: "\(name).png"))
}
