import AppKit
import Foundation

enum TargetIconProvider {
    private static let side: CGFloat = 48

    static func iconDataURL(app: NSRunningApplication) -> String? {
        guard let icon = app.icon else { return nil }
        return pngDataURL(from: icon)
    }

    static func iconDataURL(bundleId: String) -> String? {
        let clean = bundleId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return nil }

        if let running = NSRunningApplication.runningApplications(withBundleIdentifier: clean).first,
           let dataURL = iconDataURL(app: running) {
            return dataURL
        }

        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: clean) else { return nil }
        let icon = NSWorkspace.shared.icon(forFile: url.path)
        return pngDataURL(from: icon)
    }

    private static func pngDataURL(from image: NSImage) -> String? {
        let size = NSSize(width: side, height: side)
        let target = NSImage(size: size)
        target.lockFocus()
        NSColor.clear.setFill()
        NSRect(origin: .zero, size: size).fill()
        image.draw(in: NSRect(origin: .zero, size: size), from: .zero, operation: .copy, fraction: 1)
        target.unlockFocus()

        guard let tiff = target.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let png = rep.representation(using: .png, properties: [:]) else {
            return nil
        }
        return "data:image/png;base64,\(png.base64EncodedString())"
    }
}
