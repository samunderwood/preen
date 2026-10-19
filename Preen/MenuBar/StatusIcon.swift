// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit

/// The menu bar glyphs, as template images so they follow the menu bar's appearance.
enum StatusIcon {
    /// A feather, tilted like a quill.
    static let feather: NSImage = {
        let image = NSImage(size: NSSize(width: 18, height: 18), flipped: false) { _ in
            guard let context = NSGraphicsContext.current else { return false }
            let transform = NSAffineTransform()
            transform.translateX(by: 9, yBy: 9)
            transform.rotate(byDegrees: -38)
            transform.concat()

            NSColor.black.set()
            let vane = NSBezierPath()
            vane.move(to: NSPoint(x: 0, y: -4.2))
            vane.curve(to: NSPoint(x: 0, y: 8.2), controlPoint1: NSPoint(x: -4.6, y: -2.2), controlPoint2: NSPoint(x: -3.9, y: 5.2))
            vane.curve(to: NSPoint(x: 0, y: -4.2), controlPoint1: NSPoint(x: 3.9, y: 5.2), controlPoint2: NSPoint(x: 4.6, y: -2.2))
            vane.fill()

            let stem = NSBezierPath()
            stem.move(to: NSPoint(x: 0, y: -8.2))
            stem.line(to: NSPoint(x: 0, y: -3.6))
            stem.lineWidth = 1.4
            stem.lineCapStyle = .round
            stem.stroke()

            // The shaft and two splits in the barbs, cut out of the vane.
            context.compositingOperation = .clear
            let shaft = NSBezierPath()
            shaft.move(to: NSPoint(x: 0, y: -4.4))
            shaft.line(to: NSPoint(x: 0, y: 5.6))
            shaft.lineWidth = 0.9
            shaft.lineCapStyle = .round
            shaft.stroke()

            for (side, y) in [(CGFloat(-1), CGFloat(2.4)), (1, -0.6)] {
                let split = NSBezierPath()
                split.move(to: NSPoint(x: side * 4.4, y: y + 1.1))
                split.line(to: NSPoint(x: side * 1.1, y: y - 0.9))
                split.line(to: NSPoint(x: side * 4.4, y: y - 0.2))
                split.close()
                split.fill()
            }
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "Preen"
        return image
    }()

    /// Shown for a moment after a link is cleaned.
    static let cleaned: NSImage = {
        let configuration = NSImage.SymbolConfiguration(pointSize: 13, weight: .semibold)
        let image = NSImage(systemSymbolName: "checkmark", accessibilityDescription: "Link cleaned")!
            .withSymbolConfiguration(configuration)!
        image.isTemplate = true
        return image
    }()
}
