import AppKit

@main
struct IconGenerator {
    static func main() throws {
        guard CommandLine.arguments.count == 2 else { throw IconError.arguments }
        let output = URL(fileURLWithPath: CommandLine.arguments[1])
        let size = NSSize(width: 1024, height: 1024)
        let image = NSImage(size: size)
        image.lockFocus()

        let canvas = NSRect(origin: .zero, size: size)
        let appTile = NSBezierPath(roundedRect: canvas.insetBy(dx: 24, dy: 24), xRadius: 224, yRadius: 224)
        let tileGradient = NSGradient(colors: [
            NSColor(calibratedRed: 0.34, green: 0.25, blue: 0.10, alpha: 1),
            NSColor(calibratedRed: 0.11, green: 0.11, blue: 0.08, alpha: 1)
        ])!
        tileGradient.draw(in: appTile, angle: -42)

        NSColor(calibratedRed: 0.82, green: 0.70, blue: 0.44, alpha: 0.32).setStroke()
        appTile.lineWidth = 5
        appTile.stroke()

        let ambient = NSBezierPath(ovalIn: NSRect(x: 90, y: 570, width: 590, height: 410))
        NSColor(calibratedRed: 0.82, green: 0.61, blue: 0.24, alpha: 0.13).setFill()
        ambient.fill()

        let medallionRect = NSRect(x: 202, y: 202, width: 620, height: 620)
        let medallion = NSBezierPath(ovalIn: medallionRect)
        NSGraphicsContext.current?.saveGraphicsState()
        let shadow = NSShadow()
        shadow.shadowColor = NSColor.black.withAlphaComponent(0.42)
        shadow.shadowBlurRadius = 54
        shadow.shadowOffset = NSSize(width: 0, height: -24)
        shadow.set()
        NSColor(calibratedRed: 0.94, green: 0.93, blue: 0.89, alpha: 1).setFill()
        medallion.fill()
        NSGraphicsContext.current?.restoreGraphicsState()

        NSColor(calibratedRed: 0.84, green: 0.70, blue: 0.41, alpha: 0.58).setStroke()
        medallion.lineWidth = 8
        medallion.stroke()

        let monogram = NSBezierPath()
        monogram.move(to: NSPoint(x: 365, y: 355))
        monogram.line(to: NSPoint(x: 502, y: 664))
        monogram.line(to: NSPoint(x: 664, y: 355))
        monogram.lineWidth = 58
        monogram.lineCapStyle = .round
        monogram.lineJoinStyle = .round
        NSColor(calibratedRed: 0.12, green: 0.11, blue: 0.075, alpha: 1).setStroke()
        monogram.stroke()

        let capitalArc = NSBezierPath()
        capitalArc.move(to: NSPoint(x: 414, y: 445))
        capitalArc.line(to: NSPoint(x: 486, y: 445))
        capitalArc.line(to: NSPoint(x: 542, y: 514))
        capitalArc.line(to: NSPoint(x: 604, y: 470))
        capitalArc.lineWidth = 46
        capitalArc.lineCapStyle = .round
        capitalArc.lineJoinStyle = .round
        NSColor(calibratedRed: 0.59, green: 0.47, blue: 0.27, alpha: 1).setStroke()
        capitalArc.stroke()

        let endpoint = NSBezierPath(ovalIn: NSRect(x: 626, y: 454, width: 50, height: 50))
        NSColor(calibratedRed: 0.12, green: 0.11, blue: 0.075, alpha: 1).setFill()
        endpoint.fill()

        image.unlockFocus()
        guard let tiff = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff),
              let png = bitmap.representation(using: .png, properties: [:]) else { throw IconError.render }
        try png.write(to: output, options: .atomic)
    }
}

enum IconError: Error { case arguments, render }
