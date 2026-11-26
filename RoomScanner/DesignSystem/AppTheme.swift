import SwiftUI
#if canImport(UIKit)
import UIKit
public typealias AppPlatformColor = UIColor
#elseif canImport(AppKit)
import AppKit
public typealias AppPlatformColor = NSColor
#endif

/// Charte graphique et styles dWalkScan
/// - Primary Yellow: #facc15 (main color)
/// - Secondary Yellow: #fef08a (soft background tint: #fef3c7)
/// - Dark Charcoal: #111110 (deep warm charcoal: #272000) for text
public enum AppTheme {
    // MARK: - Palette SwiftUI Colors

    /// Primary Yellow: #facc15 (main color)
    public static let primaryYellow = DS.ColorToken.brand.color

    /// Secondary Yellow: #fef08a
    public static let secondaryYellow = DS.ColorToken.brandSubtle.color

    /// Soft background tint: #fef3c7
    public static let softBackgroundTint = DS.ColorToken.brandSurface.color

    /// Dark Charcoal: #111110 (text & dark chrome)
    public static let darkCharcoal = DS.ColorToken.onBrand.color

    /// Deep warm charcoal: #272000 (text & rich contrast)
    public static let deepWarmCharcoal = DS.ColorToken.brandInk.color

    // MARK: - CoreGraphics Colors

    public static let primaryCGColor = ExportPalette.primary
    public static let secondaryCGColor = ExportPalette.secondary
    public static let softBackgroundTintCGColor = ExportPalette.softBackground
    public static let darkCharcoalCGColor = ExportPalette.ink
    public static let deepWarmCharcoalCGColor = ExportPalette.warmInk

    // MARK: - Platform Colors (RealityKit / SceneBuilder)

    public static var primaryPlatformColor: AppPlatformColor {
        DS.ColorToken.brand.platformColor
    }

    public static var secondaryPlatformColor: AppPlatformColor {
        DS.ColorToken.brandSubtle.platformColor
    }
}

// MARK: - Liquid Glass Modifiers

public struct LiquidGlassModifier: ViewModifier {
    public var cornerRadius: CGFloat = 16
    public var tint: Color? = nil
    public var hasBorder: Bool = true
    public var shadowRadius: CGFloat = 10

    public func body(content: Content) -> some View {
        content.modifier(DSFloatingSurface(radius:cornerRadius))
    }

}

public struct LiquidGlassCardModifier: ViewModifier {
    public var cornerRadius: CGFloat = 14

    public func body(content: Content) -> some View {
        content.padding().modifier(DSFloatingSurface(radius:cornerRadius))
    }

}

public extension View {
    /// Adaptive system material with a quiet separator and restrained shadow.
    func liquidGlass(cornerRadius: CGFloat = 16, tint: Color? = nil, hasBorder: Bool = true, shadowRadius: CGFloat = 10) -> some View {
        modifier(LiquidGlassModifier(cornerRadius: cornerRadius, tint: tint, hasBorder: hasBorder, shadowRadius: shadowRadius))
    }

    /// Liquid Glass style card with soft border and subtle specular reflection.
    func liquidGlassCard(cornerRadius: CGFloat = 14) -> some View {
        modifier(LiquidGlassCardModifier(cornerRadius: cornerRadius))
    }
}

/// dWalkScan brand logo across iOS, iPadOS, and macOS.
public struct BrandLogoView: View {
    public var size: CGFloat = 40

    public init(size: CGFloat = 40) {
        self.size = size
    }

    public var body: some View {
        Image("AppLogo")
            .resizable()
            .aspectRatio(contentMode: .fit)
            .frame(width: size, height: size)
            .clipShape(RoundedRectangle(cornerRadius: size * 0.22, style: .continuous))
    }
}
