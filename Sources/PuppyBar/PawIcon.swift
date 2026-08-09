import AppKit

/// The paws. Drawn in code rather than shipped as a PNG so it stays crisp on any
/// display and, as a template image, automatically inverts for light/dark menu bars.
enum PawIcon {

    /// A puppy paw print: four toe beans above a heart-ish main pad.
    static func image(size: CGFloat = 18) -> NSImage {
        let image = NSImage(size: NSSize(width: size, height: size), flipped: false) { rect in
            NSColor.black.setFill() // template mode recolours this to match the menu bar

            let w = rect.width, h = rect.height

            /// Fills an ellipse given in 0...1 coordinates, optionally tilted about its own centre.
            func blob(cx: CGFloat, cy: CGFloat, rx: CGFloat, ry: CGFloat, tilt: CGFloat = 0) {
                let rect = NSRect(x: -rx * w, y: -ry * h, width: rx * 2 * w, height: ry * 2 * h)
                let path = NSBezierPath(ovalIn: rect)
                let transform = NSAffineTransform()
                transform.translateX(by: cx * w, yBy: cy * h)
                transform.rotate(byDegrees: tilt)
                path.transform(using: transform as AffineTransform)
                path.fill()
            }

            // Four toes. The outer pair sit lower, are slightly smaller, and splay outward —
            // that asymmetry is what stops it reading as a generic flower.
            blob(cx: 0.155, cy: 0.585, rx: 0.098, ry: 0.132, tilt: 22)
            blob(cx: 0.385, cy: 0.735, rx: 0.108, ry: 0.150, tilt: 8)
            blob(cx: 0.630, cy: 0.735, rx: 0.108, ry: 0.150, tilt: -8)
            blob(cx: 0.855, cy: 0.585, rx: 0.098, ry: 0.132, tilt: -22)

            // Main pad, built as overlapping fills so the top edge comes out trilobed
            // like a real paw rather than a flat oval.
            // Each lobe stays inside the body's silhouette horizontally, otherwise the
            // union pinches and you get dents at the shoulders instead of a smooth edge.
            blob(cx: 0.500, cy: 0.205, rx: 0.285, ry: 0.175)  // body
            blob(cx: 0.335, cy: 0.310, rx: 0.108, ry: 0.108)  // left lobe
            blob(cx: 0.500, cy: 0.350, rx: 0.128, ry: 0.128)  // centre lobe, tallest
            blob(cx: 0.665, cy: 0.310, rx: 0.108, ry: 0.108)  // right lobe

            return true
        }
        image.isTemplate = true // menu bar tints it; works in light + dark, and when highlighted
        return image
    }

    /// Larger, non-template paw for the Connect window and the app icon.
    static func filled(size: CGFloat, color: NSColor) -> NSImage {
        let base = image(size: size)
        let out = NSImage(size: base.size)
        out.lockFocus()
        color.set()
        let rect = NSRect(origin: .zero, size: base.size)
        base.draw(in: rect)
        rect.fill(using: .sourceAtop)
        out.unlockFocus()
        return out
    }
}
