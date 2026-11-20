import SwiftUI
import AppKit

/// Displays the Sentor Centaur logo image from the app bundle (with scratch fallback).
struct CentaurLogoView: View {
    var size: CGFloat = 36
    var showBadge: Bool = true

    private var logoImage: NSImage? {
        if let bundlePath = Bundle.main.path(forResource: "sentor-logo", ofType: "png"),
           let img = NSImage(contentsOfFile: bundlePath) {
            return img
        }
        let fallbackPath = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("Assets/sentor-logo-1024.png").path
        return NSImage(contentsOfFile: fallbackPath)
    }

    var body: some View {
        Group {
            if let img = logoImage {
                Image(nsImage: img)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: size, height: size)
                    .clipShape(RoundedRectangle(cornerRadius: size * 0.22, style: .continuous))
            } else {
                RoundedRectangle(cornerRadius: size * 0.22, style: .continuous)
                    .fill(SentorTheme.surfaceLinen)
                    .frame(width: size, height: size)
            }
        }
    }
}
